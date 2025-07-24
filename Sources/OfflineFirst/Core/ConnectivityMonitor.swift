import Foundation
import Combine
import Network
import NetworkMonitor

/// A class that monitors network connectivity and provides a publisher for the network status.
///
/// This class is a wrapper around the `NetworkMonitor` from the `network-monitor-ios` package.
public class ConnectivityMonitor {
    
    /// The underlying network monitor instance.
    private let monitor: NWPathMonitor
    
    /// A publisher that emits the current network status.
    /// `true` if the network is available, `false` otherwise.
    public let isOnline: CurrentValueSubject<Bool, Never>
    
    /// A cancellable for the network status publisher.
    private var cancellable: AnyCancellable?
    
    /// Initializes a new network monitor.
    public init() {
        self.monitor = NWPathMonitor()
        self.isOnline = CurrentValueSubject<Bool, Never>(monitor.currentPath.status == .satisfied)
        
        self.cancellable = monitor.publisher()
            .map { $0.status == .satisfied }
            .removeDuplicates()
            .subscribe(on: DispatchQueue.global(qos: .background))
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] isOnline in
                self?.isOnline.send(isOnline)
            })
        
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }
    
    deinit {
        monitor.cancel()
    }
}
