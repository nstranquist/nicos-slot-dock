import Foundation

/// Debounced file watcher for `com.apple.dock.plist` (or any test URL).
/// Calls `onChange` on the main queue after membership may have changed.
final class DockPlistWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.nstranquist.nicos-slot-dock.dock-watch")

    init(debounceInterval: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start(watching url: URL) {
        stop()
        let path = url.path
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            SlotDockTelemetry.systemDock.warning("Dock plist watch open failed — falling back to poll path=\(path, privacy: .public)")
            startPoll(url: url)
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleFire()
        }
        src.setCancelHandler { [weak self] in
            if let self, self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
        }
        source = src
        src.resume()
        SlotDockTelemetry.systemDock.info(
            "Dock plist watch started path=\(path, privacy: .public) debounceMS=\(Int(self.debounceInterval * 1000), privacy: .public)"
        )
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
        pollTimer?.cancel()
        pollTimer = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    private var pollTimer: DispatchSourceTimer?

    private func startPoll(url: URL) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        let path = url.path
        timer.setEventHandler { [weak self] in
            guard FileManager.default.fileExists(atPath: path) else { return }
            // Re-open on background queue; start is thread-safe via stop().
            self?.start(watching: URL(fileURLWithPath: path))
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
