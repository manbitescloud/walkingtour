import Foundation
import Network

/// Lightweight connectivity monitor — intentionally not @Observable/@MainActor to avoid singleton init crashes.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    var onStatusChange: (@Sendable (Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.walkingtour.networkmonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.isConnected != connected
                self.isConnected = connected
                if changed {
                    self.onStatusChange?(connected)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
