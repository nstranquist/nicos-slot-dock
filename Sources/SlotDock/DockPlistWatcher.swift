import Foundation

/// Debounced watcher for `com.apple.dock.plist` (or any test URL).
///
/// macOS commonly replaces preference files atomically. Watching the parent
/// directory instead of the file's inode keeps the stream alive across rename
/// and delete events. All mutable watcher state is confined to `queue`.
final class DockPlistWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private var watchedURL: URL?
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.nstranquist.nicos-slot-dock.dock-watch")
    private let queueKey = DispatchSpecificKey<Void>()

    init(debounceInterval: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    func start(watching url: URL) {
        onQueue { [self] in
            stopOnQueue()
            watchedURL = url.standardizedFileURL
            startOnQueue()
        }
    }

    func stop() {
        onQueue { [self] in stopOnQueue() }
    }

    private func onQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func startOnQueue() {
        guard let watchedURL else { return }
        let directory = watchedURL.deletingLastPathComponent()
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            SlotDockTelemetry.systemDock.warning(
                "Dock plist directory watch open failed — falling back to poll path=\(directory.path, privacy: .private)"
            )
            startPollOnQueue()
            return
        }
        pollTimer?.cancel()
        pollTimer = nil

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleFire()
        }
        // The source owns the descriptor after resume. Capture this exact fd
        // so a stop/start cycle cannot close a newly-opened descriptor.
        let descriptor = fd
        src.setCancelHandler {
            close(descriptor)
        }
        source = src
        src.resume()
        SlotDockTelemetry.systemDock.info(
            "Dock plist directory watch started path=\(directory.path, privacy: .private) debounceMS=\(Int(self.debounceInterval * 1000), privacy: .public)"
        )
    }

    private func stopOnQueue() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
        fd = -1
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func startPollOnQueue() {
        guard pollTimer == nil, watchedURL != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.source == nil else { return }
            self.startOnQueue()
        }
        pollTimer = timer
        timer.resume()
    }

    private func scheduleFire() {
        debounceWork?.cancel()
        let onChange = self.onChange
        let work = DispatchWorkItem {
            DispatchQueue.main.async {
                onChange()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
