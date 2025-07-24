import Foundation
import CoreData
import AspynNetwork

/// Handles the synchronization of data from a remote source to the local Core Data store.
internal class DataSynchronizer {
    
    private let coreDataManager: CoreDataManager
    private let network: AspynNetwork
    
    /// Initializes the synchronizer.
    /// - Parameters:
    ///   - coreDataManager: The manager for Core Data operations.
    ///   - network: The network client for fetching remote data.
    internal init(coreDataManager: CoreDataManager, network: AspynNetwork) {
        self.coreDataManager = coreDataManager
        self.network = network
    }
    
    /// Synchronizes data for a given endpoint.
    /// - Parameters:
    ///   - endpoint: The network endpoint to fetch data from.
    ///   - resolver: The conflict resolver to use for merging data.
    /// - Throws: An error if the network request or data processing fails.
    internal func sync<T, R>(endpoint: T, resolver: R) async throws where T: Endpoint, T.Response: Decodable, R: ConflictResolver, T.Response == R.ManagedObjectType {
        
        let remoteObjects = try await network.request(endpoint)
        
        let context = coreDataManager.provider.newBackgroundContext()
        
        try await context.perform {
            for remoteObject in remoteObjects {
                let local = self.coreDataManager.findExisting(for: remoteObject, in: context)
                
                let finalObject = resolver.resolve(remote: remoteObject, local: local)
                
                // The mapping from remote to managed is implicit via the resolver's return type
                // and the save method will handle the upsert.
                try self.coreDataManager.save(object: finalObject)
            }
        }
    }
}
