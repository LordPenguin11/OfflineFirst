import Foundation
import Network
import Combine

/// Monitors network connectivity and publishes status updates.
internal class ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aspyn.offlinefirst.connectivitymonitor")
    
    private let statusSubject = CurrentValueSubject<Bool, Never>(false)
    
    /// A publisher that emits the network status.
    /// `true` if the network is available, `false` otherwise.
    internal var isOnline: AnyPublisher<Bool, Never> {
        statusSubject.eraseToAnyPublisher()
    }
    
    /// The last known network status.
    internal var isConnected: Bool {
        return monitor.currentPath.status == .satisfied
    }
    
    internal init() {
        // Set initial value
        statusSubject.send(monitor.currentPath.status == .satisfied)
        
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            self?.statusSubject.send(isConnected)
        }
    }
    
    /// Starts monitoring for network changes.
    internal func start() {
        monitor.start(queue: queue)
    }
    
    /// Stops monitoring for network changes.
    internal func stop() {
        monitor.cancel()
    }
}
