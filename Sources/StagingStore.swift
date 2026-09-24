import AppKit
import Darwin

enum ItemKind {
    case file, folder, package
}

struct StagedItem {
    let id: UUID
    let url: URL
    let displayName: String
    let kind: ItemKind
    let byteCount: Int64?
}

protocol StagingStoreDelegate: AnyObject {
    func stagingStoreDidChange(_ store: StagingStore)
}

/// Holds copies in a temp folder. Clearing deletes those copies only.
final class StagingStore {
    private let fm = FileManager.default
    private let lock = NSLock()
    private let root: URL
    private var stagingDirectory: URL
    private var generation = 0
    private var jobs = Set<UUID>()
    private var promises: [NSFilePromiseReceiver] = []
    private let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private(set) var items: [StagedItem] = []
    private(set) var lastError: String?
    private(set) var isImporting = false
    weak var delegate: StagingStoreDelegate?

    init(root: URL) {
        self.root = root
        self.stagingDirectory = root
        try? fm.removeItem(at: root)
        _ = bumpGeneration()
    }

    static func live() -> StagingStore {
        StagingStore(root: cleanupAndMakeRoot())
    }

    func importFileURLs(_ urls: [URL]) {
        let job = beginJob()
        let gen = currentGeneration()
        let dir = currentDirectory()
        ioQueue.addOperation { [weak self] in
            guard let self else { return }
            let result = self.copyFiles(urls, into: dir, generation: gen)
            DispatchQueue.main.async {
                self.finish(job: job, generation: gen, items: result.items, error: result.error)
            }
        }
    }

    func importImageData(_ data: Data) {
        guard let png = Self.pngData(from: data) else {
            lastError = "无法保存拖入的图片"
            delegate?.stagingStoreDidChange(self)
            return
        }
        let job = beginJob()
        let gen = currentGeneration()
        let dir = currentDirectory()
        ioQueue.addOperation { [weak self] in
            guard let self else { return }
            let result = self.writePNG(png, into: dir, generation: gen)
            DispatchQueue.main.async {
                self.finish(job: job, generation: gen, items: result.items, error: result.error)
            }
        }
    }

    func receive(_ receivers: [NSFilePromiseReceiver]) {
        for promise in receivers {
            promises.append(promise)
            let job = beginJob()
            let gen = currentGeneration()
            let dir = currentDirectory()
            promise.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: ioQueue) { [weak self] url, error in
                let made = error == nil ? [self?.makeItem(url: url)].compactMap { $0 } : []
                let message = error.map { "未能放入文件：\($0.localizedDescription)" }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.promises.removeAll { $0 === promise }
                    self.finish(job: job, generation: gen, items: made, error: message)
                }
            }
        }
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let url = items.remove(at: index).url
        delegate?.stagingStoreDidChange(self)
        ioQueue.addOperation {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func clear() {
        let old = currentDirectory()
        _ = bumpGeneration()
        items = []
        jobs.removeAll()
        isImporting = false
        lastError = nil
        ioQueue.addOperation {
            try? FileManager.default.removeItem(at: old)
        }
        delegate?.stagingStoreDidChange(self)
    }

    func shutdown() {
        _ = bumpGeneration()
        ioQueue.waitUntilAllOperationsAreFinished()
        try? fm.removeItem(at: root)
    }

    func waitForIO() {
        ioQueue.waitUntilAllOperationsAreFinished()
    }

    @discardableResult
    func importNow(_ urls: [URL]) -> [StagedItem] {
        let result = copyFiles(urls, into: currentDirectory(), generation: currentGeneration())
        apply(result.items, error: result.error)
        return result.items
    }

    @discardableResult
    func importImageNow(_ data: Data) -> URL? {
        guard let png = Self.pngData(from: data) else { return nil }
        let result = writePNG(png, into: currentDirectory(), generation: currentGeneration())
        apply(result.items, error: result.error)
        return result.items.first?.url
    }

    static func runSelfTest() {
        do {
            try executeSelfTest()
            print("自测通过")
        } catch {
            fputs("自测失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func executeSelfTest() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("transfer-ball-test-\(UUID().uuidString)", isDirectory: true)
        let srcDir = fm.temporaryDirectory.appendingPathComponent("transfer-ball-src-\(UUID().uuidString)", isDirectory: true)
        let store = StagingStore(root: root)
        defer {
            store.shutdown()
            try? fm.removeItem(at: srcDir)
        }
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let file = srcDir.appendingPathComponent("笔记.txt")
        try "你好".write(to: file, atomically: true, encoding: .utf8)
        let folder = srcDir.appendingPathComponent("资料", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let imported = store.importNow([file, folder])
        expect(imported.count == 2, "应放入 2 个项目")
        expect(imported[0].kind == .file, "第一个应是文件")
        expect(imported[1].kind == .folder, "第二个应是文件夹")
        expect(fm.fileExists(atPath: file.path), "原文件被移走了")
        expect(try String(contentsOf: imported[0].url, encoding: .utf8) == "你好", "副本内容不对")
        expect(fm.fileExists(atPath: imported[1].url.appendingPathComponent("a.txt").path), "文件夹内容丢失")

        let again = store.importNow([file])
        expect(again.first?.displayName == "笔记 2.txt", "重名应为 笔记 2.txt")
        store.remove(id: again[0].id)
        store.waitForIO()
        expect(store.items.count == 2, "移除后数量不对")
        expect(!fm.fileExists(atPath: again[0].url.path), "移除后副本还在")

        let missing = store.importNow([URL(fileURLWithPath: "/tmp/\(UUID().uuidString).txt")])
        expect(missing.isEmpty, "缺失文件不应进入中转区")
        expect(store.lastError != nil, "缺失文件应提示错误")

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let png = rep.representation(using: .png, properties: [:]) else {
            expect(false, "无法创建测试图片")
            return
        }
        let imageURL = store.importImageNow(png)
        expect(imageURL != nil, "图片未保存")
        let saved = try Data(contentsOf: imageURL!)
        expect(saved.starts(with: [0x89, 0x50, 0x4E, 0x47]), "保存的不是 PNG")

        let survivor = imported[0].url
        store.clear()
        store.waitForIO()
        expect(store.items.isEmpty, "清空后中转区还应有项目")
        expect(!fm.fileExists(atPath: survivor.path), "清空后副本还在")
        expect(fm.fileExists(atPath: file.path), "清空时删除了原文件")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("自测失败：\(message)\n", stderr)
            exit(1)
        }
    }

    private func apply(_ newItems: [StagedItem], error: String?) {
        if let error {
            lastError = error
        } else if !newItems.isEmpty {
            lastError = nil
        }
        if !newItems.isEmpty {
            items.insert(contentsOf: newItems, at: 0)
        }
        delegate?.stagingStoreDidChange(self)
    }

    @discardableResult
    private func beginJob() -> UUID {
        let id = UUID()
        jobs.insert(id)
        let wasImporting = isImporting
        isImporting = true
        if !wasImporting {
            delegate?.stagingStoreDidChange(self)
        }
        return id
    }

    private func finish(job: UUID, generation gen: Int, items newItems: [StagedItem], error: String?) {
        jobs.remove(job)
        defer {
            isImporting = !jobs.isEmpty
            delegate?.stagingStoreDidChange(self)
        }
        guard gen == currentGeneration() else {
            for item in newItems {
                try? fm.removeItem(at: item.url)
            }
            return
        }
        apply(newItems, error: error)
    }

    private func copyFiles(_ urls: [URL], into directory: URL, generation gen: Int) -> (items: [StagedItem], error: String?) {
        var made: [StagedItem] = []
        var failures: [String] = []
        for url in urls {
            if currentGeneration() != gen { return ([], nil) }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let source: URL
            if let alias = try? URL(resolvingAliasFileAt: url, options: [.withoutUI]) {
                source = alias.standardizedFileURL
            } else {
                source = url.standardizedFileURL
            }
            if isInside(source, root) { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else {
                failures.append("找不到「\(url.lastPathComponent)」")
                continue
            }
            let dest = uniqueDestination(for: source.lastPathComponent, in: directory)
            do {
                try fm.copyItem(at: source, to: dest)
                made.append(makeItem(url: dest))
            } catch {
                failures.append("「\(source.lastPathComponent)」\(error.localizedDescription)")
            }
        }
        return (made, failureMessage(failures))
    }

    private func writePNG(_ data: Data, into directory: URL, generation gen: Int) -> (items: [StagedItem], error: String?) {
        if currentGeneration() != gen { return ([], nil) }
        let dest = uniqueDestination(for: "图片.png", in: directory)
        do {
            try data.write(to: dest, options: .atomic)
            return ([makeItem(url: dest)], nil)
        } catch {
            return ([], "无法保存图片：\(error.localizedDescription)")
        }
    }

    private func failureMessage(_ failures: [String]) -> String? {
        guard let first = failures.first else { return nil }
        if failures.count == 1 { return "未能放入：\(first)" }
        return "有 \(failures.count) 个项目未能放入。\(first)"
    }

    private func makeItem(url: URL) -> StagedItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        let kind: ItemKind
        if values?.isPackage == true {
            kind = .package
        } else if values?.isDirectory == true {
            kind = .folder
        } else {
            kind = .file
        }
        let bytes: Int64? = kind == .file ? values?.fileSize.map(Int64.init) : nil
        return StagedItem(id: UUID(), url: url, displayName: url.lastPathComponent, kind: kind, byteCount: bytes)
    }

    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        let cleaned = (name as NSString).lastPathComponent
        let baseName = cleaned.isEmpty ? "未命名" : cleaned
        func candidate(_ value: String) -> URL { directory.appendingPathComponent(value) }
        if !fm.fileExists(atPath: candidate(baseName).path) { return candidate(baseName) }
        let ns = baseName as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var index = 2
        while index < 10000 {
            let next = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            if !fm.fileExists(atPath: candidate(next).path) { return candidate(next) }
            index += 1
        }
        return directory.appendingPathComponent(UUID().uuidString + "-" + baseName)
    }

    private func isInside(_ url: URL, _ directory: URL) -> Bool {
        let dir = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == dir || path.hasPrefix(dir + "/")
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func currentDirectory() -> URL {
        lock.lock()
        defer { lock.unlock() }
        return stagingDirectory
    }

    @discardableResult
    private func bumpGeneration() -> Int {
        lock.lock()
        generation += 1
        let next = root.appendingPathComponent("g\(generation)", isDirectory: true)
        stagingDirectory = next
        lock.unlock()
        try? fm.createDirectory(at: next, withIntermediateDirectories: true)
        return generation
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func cleanupAndMakeRoot() -> URL {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
        let prefix = "com.wcy.transferball.staging-"
        if let names = try? fm.contentsOfDirectory(atPath: parent.path) {
            for name in names where name.hasPrefix(prefix) {
                let pidText = name.dropFirst(prefix.count)
                guard let pid = Int32(pidText), pid != getpid(), !processIsRunning(pid) else { continue }
                try? fm.removeItem(at: parent.appendingPathComponent(name))
            }
        }
        return parent.appendingPathComponent(prefix + String(getpid()), isDirectory: true)
    }

    private static func processIsRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
