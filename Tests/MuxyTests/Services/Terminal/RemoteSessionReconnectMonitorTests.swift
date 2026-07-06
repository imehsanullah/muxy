import Testing

@testable import Muxy

@Suite("Remote reconnect trigger")
struct RemoteSessionReconnectMonitorTests {
    @Test("Initial healthy network does not request reconnect")
    func initialHealthyNetwork() {
        var trigger = RemoteSessionReconnectTrigger()
        let shouldReconnect = trigger.update(networkAvailable: true)
        #expect(!shouldReconnect)
    }

    @Test("Recovery requests one reconnect after an outage")
    func recoveryAfterOutage() {
        var trigger = RemoteSessionReconnectTrigger()

        let firstUnavailable = trigger.update(networkAvailable: false)
        let secondUnavailable = trigger.update(networkAvailable: false)
        let recovered = trigger.update(networkAvailable: true)
        let stillHealthy = trigger.update(networkAvailable: true)

        #expect(!firstUnavailable)
        #expect(!secondUnavailable)
        #expect(recovered)
        #expect(!stillHealthy)
    }

    @Test("Wake always requests a disconnected-session check")
    func wake() {
        let trigger = RemoteSessionReconnectTrigger()
        #expect(trigger.wake())
    }
}
