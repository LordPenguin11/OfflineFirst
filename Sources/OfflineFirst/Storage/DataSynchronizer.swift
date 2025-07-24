import Foundation
import CoreData
import AspynNetwork
import AspynNetwork

/// Handles the synchronization of data from a remote source to the local Core Data store.
internal class DataSynchronizer {
    
    private let coreDataManager: CoreDataManager
    private let network: NetworkProtocol
    
    /// Initializes the synchronizer.
    /// - Parameters:
    ///   - coreDataManager: The manager for Core Data operations.
    ///   - network: The network client for fetching remote data.
    internal init(coreDataManager: CoreDataManager, network: NetworkProtocol) {
        self.coreDataManager = coreDataManager
        self.network = network
    }
    
    /// Synchronizes single object data from a remote endpoint with the local Core Data store.
    /// - Parameters:
    ///   - endpoint: The endpoint to fetch data from.
    ///   - responseType: The type of the expected response data.
    ///   - resolver: The conflict resolver to use for merging data.
    /// - Returns: The synchronized Core Data entity
    /// - Throws: An error if the network request or data processing fails.
    internal func sync<T, R>(endpoint: RequestEndpoint, responseType: T.Type, resolver: R) async throws -> R.ManagedObjectType where T: Decodable & Mappable, R: ConflictResolver, T == R.RemoteObjectType, T.ManagedObjectType == R.ManagedObjectType {
        
        let remoteObject: T = try await network.request(request: endpoint)
        
        let context = coreDataManager.provider.newBackgroundContext()
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let syncedEntity = resolver.resolve(remoteData: remoteObject, in: context)
                    try context.save()
                    continuation.resume(returning: syncedEntity)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Synchronizes array data from a remote endpoint with the local Core Data store.
    /// - Parameters:
    ///   - endpoint: The endpoint to fetch data from.
    ///   - responseType: The type of the expected response data (array element type).
    ///   - resolver: The conflict resolver to use for merging data.
    /// - Returns: Array of synchronized Core Data entities
    /// - Throws: An error if the network request or data processing fails.
    internal func syncArray<T, R>(endpoint: RequestEndpoint, responseType: T.Type, resolver: R) async throws -> [R.ManagedObjectType] where T: Decodable & Mappable, R: ConflictResolver, T == R.RemoteObjectType, T.ManagedObjectType == R.ManagedObjectType {
        
        let remoteObjects: [T] = try await network.request(request: endpoint)
        
        let context = coreDataManager.provider.newBackgroundContext()
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    var syncedEntities: [R.ManagedObjectType] = []
                    
                    for remoteObject in remoteObjects {
                        let syncedEntity = resolver.resolve(remoteData: remoteObject, in: context)
                        syncedEntities.append(syncedEntity)
                    }
                    
                    try context.save()
                    continuation.resume(returning: syncedEntities)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetches and caches a single object, always returning a Core Data entity.
    /// This is the core method for offline-first single object retrieval.
    internal func fetchAndCache<T: Decodable & Mappable>(
        endpoint: RequestEndpoint,
        responseType: T.Type
    ) async throws -> T.ManagedObjectType {
        
        let remoteObject: T = try await network.request(request: endpoint)
        
        let context = coreDataManager.provider.newBackgroundContext()
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let entity = try remoteObject.toManagedObject(in: context)
                    try context.save()
                    continuation.resume(returning: entity)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Fetches and caches array data, always returning Core Data entities.
    /// This is the core method for offline-first array retrieval.
    internal func fetchAndCacheArray<T: Decodable & Mappable>(
        endpoint: RequestEndpoint,
        responseType: T.Type
    ) async throws -> [T.ManagedObjectType] {
        
        let remoteObjects: [T] = try await network.request(request: endpoint)
        
        let context = coreDataManager.provider.newBackgroundContext()
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    var entities: [T.ManagedObjectType] = []
                    
                    for remoteObject in remoteObjects {
                        let entity = try remoteObject.toManagedObject(in: context)
                        entities.append(entity)
                    }
                    
                    try context.save()
                    continuation.resume(returning: entities)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
