import AppKit
import Foundation
import Network

struct RemoteSessionReconnectTrigger {
    private(set) var wasUnavailable = false

    mutating func update(networkAvailable: Bool) -> Bool {
        guard networkAvailable else {
            wasUnavailable = true
            return false
        }
        defer { wasUnavailable = false }
        return wasUnavailable
    }

    func wake() -> Bool {
        true
    }
}

final class RemoteSessionReconnectMonitor: NSObject, @unchecked Sendable {
    static let shared = RemoteSessionReconnectMonitor()

    private let monitor: NWPathMonitor
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "app.muxy.remote-session-reconnect")
    private var trigger = RemoteSessionReconnectTrigger()
    private var started = false

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.monitor = monitor
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(networkAvailable: path.status == .satisfied)
        }
        monitor.start(queue: queue)
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func handle(networkAvailable: Bool) {
        guard trigger.update(networkAvailable: networkAvailable) else { return }
        postReconnect()
    }

    @objc
    private func handleWake() {
        guard trigger.wake() else { return }
        postReconnect()
    }

    private func postReconnect() {
        DispatchQueue.main.async { [notificationCenter] in
            notificationCenter.post(name: .remoteSessionsShouldReconnect, object: nil)
        }
    }
}
