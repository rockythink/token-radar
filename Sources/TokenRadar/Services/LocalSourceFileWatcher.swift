import Darwin
import Foundation

final class LocalSourceFileWatcher {
    private struct WatchedItem {
        var descriptor: CInt
        var source: DispatchSourceFileSystemObject
    }

    private let queue = DispatchQueue(label: "com.elazer.TokenRadar.LocalSourceFileWatcher")
    private let debounceInterval: TimeInterval
    private let onChange: @MainActor () -> Void
    private var roots: [URL] = []
    private var watchedItems: [String: WatchedItem] = [:]
    private var debounceWorkItem: DispatchWorkItem?

    init(
        debounceInterval: TimeInterval = 1.5,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    func start(roots: [URL]) {
        let normalizedRoots = roots.map(\.standardizedFileURL)
        queue.async { [weak self] in
            guard let self else { return }
            self.roots = normalizedRoots
            self.rebuildWatches()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.roots = []
            self.cancelAllWatches()
        }
    }

    deinit {
        debounceWorkItem?.cancel()
        watchedItems.values.forEach { watch in
            watch.source.cancel()
        }
    }

    private func handleFileSystemEvent() {
        rebuildWatches()
        scheduleDebouncedChange()
    }

    private func rebuildWatches() {
        let nextItems = Set(roots.flatMap(existingWatchItems))
        let currentPaths = Set(watchedItems.keys)

        for removedPath in currentPaths.subtracting(nextItems.map(\.path)) {
            removeWatch(path: removedPath)
        }

        for item in nextItems where watchedItems[item.path] == nil {
            addWatch(item)
        }
    }

    private func existingWatchItems(root: URL) -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        var items = [root.standardizedFileURL]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return items
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            else {
                continue
            }
            if values.isDirectory == true || (values.isRegularFile == true && url.pathExtension.lowercased() == "jsonl") {
                items.append(url.standardizedFileURL)
            }
        }

        return items
    }

    private func addWatch(_ item: URL) {
        let path = item.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        watchedItems[path] = WatchedItem(descriptor: descriptor, source: source)
        source.resume()
    }

    private func removeWatch(path: String) {
        guard let watch = watchedItems.removeValue(forKey: path) else { return }
        watch.source.cancel()
    }

    private func cancelAllWatches() {
        let watches = watchedItems.values
        watchedItems.removeAll()
        watches.forEach { watch in
            watch.source.cancel()
        }
    }

    private func scheduleDebouncedChange() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onChange()
            }
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
