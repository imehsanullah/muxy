import AppKit
import Foundation
import Network

final class RemoteSessionReconnectMonitor: NSObject, @unchecked Sendable {
    static let shared = RemoteSessionReconnectMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.muxy.remoteSessionReconnect")
    private var started = false
    private var wasUnavailable = false

    private override init() {
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path)
        }
        monitor.start(queue: queue)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func handle(_ path: NWPath) {
        if path.status == .satisfied {
            if wasUnavailable {
                postReconnect()
            }
            wasUnavailable = false
            return
        }
        wasUnavailable = true
    }

    @objc
    private func handleWake() {
        postReconnect()
    }

    private func postReconnect() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .remoteSessionsShouldReconnect, object: nil)
        }
    }
}
