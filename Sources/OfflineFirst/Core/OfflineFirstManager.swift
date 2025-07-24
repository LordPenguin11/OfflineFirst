import Foundation
import Combine
import AspynNetwork
import AspynNetwork

//
//  OfflineFirstManager.swift
//  OfflineFirst
//
//  Created by Long Vo on 24/07/2024.
//

/// The main entry point for the OfflineFirst framework.
///
/// This singleton class manages the write queue and data synchronization, providing a unified interface for all offline capabilities.
///
/// ## Overview
/// The `OfflineFirstManager` is the central coordinator for the framework. Before using any of its features, you must configure it by calling the `configure(executor:coreDataProvider:network:)` method once at app startup.
///
/// Once configured, you can:
/// - Queue write operations using `queueWrite(functionIdentifier:parameters:)`. These operations are persisted and executed automatically when the device is online.
/// - Synchronize remote data with the local Core Data store using `sync(endpoint:resolver:)`.
///
/// ## Example Usage
/// ```swift
/// // In your app's setup (e.g., AppDelegate or a DI container)
/// let myExecutor = MyAppOperationExecutor(apiClient: myApiClient)
/// let myCoreDataProvider = MyCoreDataProvider()
/// let myNetworkClient = AspynNetwork()
///
/// OfflineFirstManager.shared.configure(
///     executor: myExecutor,
///     coreDataProvider: myCoreDataProvider,
///     network: myNetworkClient
/// )
///
/// // Later, in your ViewModel or UI
/// do {
///     let params = ["title": "New Post", "content": "Hello, offline world!"]
///     try OfflineFirstManager.shared.queueWrite(functionIdentifier: "createPost", parameters: params)
/// } catch {
///     print("Failed to queue write: \(error)")
/// }
/// ```
public class OfflineFirstManager {
    
    /// The shared singleton instance of the manager. Access all framework functionality through this property.
    public static let shared = OfflineFirstManager()
    
    private var writeQueue: WriteQueue?
    private var connectivityMonitor: ConnectivityMonitor?
    private var coreDataManager: CoreDataManager?
    private var dataSynchronizer: DataSynchronizer?
    
    /// A batch download manager for downloading multiple files efficiently.
    /// Only available after the framework has been configured.
    public private(set) var batchDownloadManager: BatchDownloadManager?
    
    /// A publisher that emits details of operations that have been aborted.
    ///
    /// Your UI can subscribe to this publisher to be notified when an operation has permanently failed
    /// (either by reaching the maximum number of retries or by encountering an unrecoverable error).
    /// This allows you to inform the user, update the UI state, or perform any necessary cleanup.
    public let abortedOperationPublisher = PassthroughSubject<(operation: WriteOperation, error: Error), Never>()
    
    private var isConfigured = false
    
    private init() {}
    
    /// Configures the OfflineFirstManager with the necessary components provided by the application.
    ///
    /// This method must be called once, typically at application startup, before any other framework methods are used.
    /// It sets up the entire offline stack, including the database, network monitor, and data synchronizer.
    ///
    /// - Parameters:
    ///   - executor: An object conforming to `OperationExecutor`. This is your application-specific logic that knows how to execute the queued write operations (e.g., by calling your `APIClient`).
    ///   - coreDataProvider: An object conforming to `CoreDataProvider`. This provides the framework with access to your app's Core Data stack (the view context and background contexts).
    ///   - network: An object conforming to `NetworkProtocol` that handles your app's network requests.
    ///   - retryPolicy: A `RetryPolicy` struct that defines the rules for retrying failed operations.
    public func configure(
        executor: OperationExecutor,
        coreDataProvider: CoreDataProvider,
        network: NetworkProtocol,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) throws {
        guard !isConfigured else {
            print("OfflineFirstManager is already configured.")
            return
        }
        
        // Setup Core Data stack
        self.coreDataManager = CoreDataManager(provider: coreDataProvider)
        self.dataSynchronizer = DataSynchronizer(coreDataManager: self.coreDataManager!, network: network)
        
        // Setup Write Queue
        let dbManager = try DatabaseManager()
        self.connectivityMonitor = ConnectivityMonitor()
        self.writeQueue = WriteQueue(
            dbManager: dbManager,
            executor: executor,
            connectivityMonitor: self.connectivityMonitor!,
            retryPolicy: retryPolicy,
            abortedOperationPublisher: abortedOperationPublisher
        )
        
        // Setup Batch Download Manager
        self.batchDownloadManager = BatchDownloadManager(network: network)
        
        self.isConfigured = true
    }
    
    /// Performs an offline-first write operation with automatic Core Data mapping.
    /// **True Offline-First Logic**: Maps parameters to Core Data immediately, then queues the network operation.
    ///
    /// **HTTP Semantics Guide:**
    /// - **POST**: Parameters should create new entities (generate new IDs)
    /// - **PUT/PATCH**: Parameters should update existing entities (find by existing ID)
    /// - **DELETE**: Use `performDelete` instead of this method
    ///
    /// **Flow (both online and offline):**
    /// 1. Map parameters to Core Data entity immediately using Mappable protocol
    /// 2. Queue network operation for eventual consistency
    /// 3. Return Core Data entity
    ///
    /// **Example POST (Create New):**
    /// ```swift
    /// struct CreateUserParams: Codable, Mappable {
    ///     let name: String
    ///     let email: String
    ///     
    ///     func toManagedObject(in context: NSManagedObjectContext) throws -> UserEntity {
    ///         let user = UserEntity(context: context)
    ///         user.id = UUID().uuidString  // Generate new ID
    ///         user.name = self.name
    ///         user.status = "creating"     // Optimistic state
    ///         return user
    ///     }
    /// }
    /// ```
    ///
    /// **Example PUT/PATCH (Update Existing):**
    /// ```swift
    /// struct UpdateUserParams: Codable, Mappable {
    ///     let id: String  // Must know which entity to update
    ///     let name: String
    ///     
    ///     func toManagedObject(in context: NSManagedObjectContext) throws -> UserEntity {
    ///         let request = UserEntity.fetchRequest()
    ///         request.predicate = NSPredicate(format: "id == %@", self.id)
    ///         
    ///         guard let user = try context.fetch(request).first else {
    ///             throw OfflineFirstError.databaseError(NSError(...)) // Entity not found
    ///         }
    ///         
    ///         user.name = self.name
    ///         user.status = "updating"  // Optimistic state
    ///         return user
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the function to be executed
    ///   - parameters: A `Mappable` object that can be automatically mapped to Core Data
    /// - Returns: The Core Data entity that was created/updated
    /// - Throws: An error if the framework has not been configured, or if the operation fails
    public func performWrite<T: Encodable & Mappable>(
        functionIdentifier: String,
        parameters: T
    ) async throws -> T.ManagedObjectType {
        guard let writeQueue = writeQueue,
              let coreDataManager = coreDataManager,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        // Step 1: Map to Core Data FIRST (offline-first principle)
        let entity = try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    // Automatically map parameters to Core Data using Mappable protocol
                    let mappedEntity = try parameters.toManagedObject(in: backgroundContext)
                    try backgroundContext.save()
                    continuation.resume(returning: mappedEntity)
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
        
        // Step 2: Queue the network operation for eventual consistency
        do {
            let paramsData = try JSONEncoder().encode(parameters)
            let operation = WriteOperation(
                functionIdentifier: functionIdentifier,
                parameters: paramsData
            )
            try writeQueue.add(operation: operation)
        } catch {
            print("Warning: Failed to queue write operation: \(error)")
            // Don't fail the entire operation - Core Data is already updated
        }
        
        return entity
    }
    
    /// Advanced write method for cases requiring custom optimistic updates.
    /// Use `performWrite` with Mappable parameters for most cases.
    public func performWriteWithCustomUpdate<T: NSManagedObject>(
        functionIdentifier: String,
        parameters: Encodable,
        optimisticUpdate: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        guard let writeQueue = writeQueue,
              let coreDataManager = coreDataManager,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        // Step 1: Update Core Data FIRST (offline-first principle)
        let entity = try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    let updatedEntity = try optimisticUpdate(backgroundContext)
                    try backgroundContext.save()
                    continuation.resume(returning: updatedEntity)
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
        
        // Step 2: Queue the network operation for eventual consistency
        do {
            let paramsData = try JSONEncoder().encode(parameters)
            let operation = WriteOperation(
                functionIdentifier: functionIdentifier,
                parameters: paramsData
            )
            try writeQueue.add(operation: operation)
        } catch {
            print("Warning: Failed to queue write operation: \(error)")
            // Don't fail the entire operation - Core Data is already updated
        }
        
        return entity
    }
    
    /// Performs an offline-first delete operation.
    /// **True Offline-First Logic**: Removes entity from Core Data immediately, then queues the network operation.
    ///
    /// **HTTP DELETE Semantics:**
    /// 1. Find and remove entity from Core Data immediately
    /// 2. Queue delete operation for server consistency
    /// 3. No return value (entity is deleted)
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the delete operation
    ///   - parameters: An `Encodable` object containing the identifier of the entity to delete
    ///   - entityFinder: A closure that finds and removes the entity from Core Data
    /// - Throws: An error if the framework has not been configured, entity not found, or operation fails
    public func performDelete<T: Encodable>(
        functionIdentifier: String,
        parameters: T,
        entityFinder: @escaping (NSManagedObjectContext, T) throws -> NSManagedObject?
    ) async throws {
        guard let writeQueue = writeQueue,
              let coreDataManager = coreDataManager,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        // Step 1: Remove from Core Data FIRST (offline-first principle)
        try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    if let entityToDelete = try entityFinder(backgroundContext, parameters) {
                        backgroundContext.delete(entityToDelete)
                        try backgroundContext.save()
                        continuation.resume(returning: ())
                    } else {
                        // Entity not found locally - this might be okay for deletes
                        print("Warning: Entity not found locally for delete operation")
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
        
        // Step 2: Queue the delete operation for server consistency
        do {
            let paramsData = try JSONEncoder().encode(parameters)
            let operation = WriteOperation(
                functionIdentifier: functionIdentifier,
                parameters: paramsData
            )
            try writeQueue.add(operation: operation)
        } catch {
            print("Warning: Failed to queue delete operation: \(error)")
            // Entity is already deleted locally, so this is not critical
        }
    }
    
    /// Convenient delete method for entities with simple ID-based lookup.
    /// **HTTP DELETE Semantics**: Removes entity by ID from Core Data, then queues network operation.
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the delete operation
    ///   - entityId: The unique identifier of the entity to delete
    ///   - entityType: The Core Data entity type to delete
    /// - Throws: An error if the framework has not been configured or operation fails
    public func performDelete<EntityType: NSManagedObject>(
        functionIdentifier: String,
        entityId: String,
        entityType: EntityType.Type
    ) async throws {
        struct DeleteParams: Codable {
            let id: String
        }
        
        let params = DeleteParams(id: entityId)
        
        try await performDelete(
            functionIdentifier: functionIdentifier,
            parameters: params
        ) { context, deleteParams in
            let fetchRequest = NSFetchRequest<EntityType>(entityName: String(describing: entityType))
            fetchRequest.predicate = NSPredicate(format: "id == %@", deleteParams.id)
            
            return try context.fetch(fetchRequest).first
        }
    }
    
    /// Legacy method for backward compatibility - only queues operation without Core Data update.
    /// 
    /// **Note**: This method only queues the operation without updating Core Data.
    /// Consider using `performWrite` or `performDelete` for true offline-first behavior.
    public func queueWrite(functionIdentifier: String, parameters: Encodable) throws {
        guard let writeQueue = writeQueue, isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        let paramsData = try JSONEncoder().encode(parameters)
        
        let operation = WriteOperation(
            functionIdentifier: functionIdentifier,
            parameters: paramsData
        )
        
        try writeQueue.add(operation: operation)
    }
    
    /// Performs an offline-first multipart write operation (with file attachments).
    /// **True Offline-First Logic**: Updates Core Data immediately, then queues the network operation.
    ///
    /// **Flow (both online and offline):**
    /// 1. Update Core Data immediately with optimistic data (including file metadata)
    /// 2. Queue multipart network operation for eventual consistency
    /// 3. Return Core Data entity
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the function to be executed
    ///   - parameters: An `Encodable` object representing the parameters for the function
    ///   - attachments: An array of `FileAttachment` objects representing the files to be uploaded
    ///   - optimisticUpdate: A closure that creates/updates the Core Data entity optimistically
    /// - Returns: The Core Data entity that was created/updated
    /// - Throws: An error if the framework has not been configured, or if the operation fails
    public func performMultipartWrite<T: NSManagedObject>(
        functionIdentifier: String,
        parameters: Encodable,
        attachments: [FileAttachment],
        optimisticUpdate: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        guard let writeQueue = writeQueue,
              let coreDataManager = coreDataManager,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        // Step 1: Update Core Data FIRST (offline-first principle)
        let entity = try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    let updatedEntity = try optimisticUpdate(backgroundContext)
                    try backgroundContext.save()
                    continuation.resume(returning: updatedEntity)
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
        
        // Step 2: Queue the multipart network operation for eventual consistency
        do {
            let paramsData = try JSONEncoder().encode(parameters)
            let operation = MultipartWriteOperation(
                functionIdentifier: functionIdentifier,
                parameters: paramsData,
                attachments: attachments
            )
            try writeQueue.add(multipartOperation: operation)
        } catch {
            print("Warning: Failed to queue multipart write operation: \(error)")
            // Don't fail the entire operation - Core Data is already updated
        }
        
        return entity
    }
    
    /// Legacy method for backward compatibility - only queues the multipart operation.
    ///
    /// **Note**: This method only queues the operation without updating Core Data.
    /// Consider using `performMultipartWrite` for true offline-first behavior.
    public func queueMultipartWrite(functionIdentifier: String, parameters: Encodable, attachments: [FileAttachment]) throws {
        guard let writeQueue = writeQueue, isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        let paramsData = try JSONEncoder().encode(parameters)
        
        let operation = MultipartWriteOperation(
            functionIdentifier: functionIdentifier,
            parameters: paramsData,
            attachments: attachments
        )
        
        try writeQueue.add(multipartOperation: operation)
    }
    
    /// Fetches single object data from network if online, caches it locally, and always returns Core Data objects.
    /// This is the core offline-first method that ensures GET requests always return cached Core Data entities.
    ///
    /// **Critical Behavior:**
    /// - If online: Fetches from network → Maps to Core Data → Saves → Returns Core Data entity
    /// - If offline: Returns existing Core Data entity from cache
    /// - Always returns Core Data objects, never raw network responses
    ///
    /// - Parameters:
    ///   - endpoint: The `RequestEndpoint` to fetch data from
    ///   - responseType: The expected response model type (must be Decodable & Mappable)
    ///   - entityType: The Core Data entity type to return
    /// - Returns: Core Data entity of the specified type
    /// - Throws: OfflineFirstError if not configured, no cache available offline, or mapping fails
    public func fetchAndCache<ResponseType: Decodable & Mappable, EntityType: NSManagedObject>(
        endpoint: RequestEndpoint,
        responseType: ResponseType.Type,
        entityType: EntityType.Type
    ) async throws -> EntityType where ResponseType.ManagedObjectType == EntityType {
        guard let dataSynchronizer = dataSynchronizer,
              let connectivityMonitor = connectivityMonitor,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        let isOnline = connectivityMonitor.isConnected
        
        if isOnline {
            do {
                // Fetch from network and cache using DataSynchronizer
                let entity = try await dataSynchronizer.fetchAndCache(endpoint: endpoint, responseType: responseType)
                return entity as! EntityType
            } catch {
                print("Network fetch failed, falling back to cache: \(error)")
                // Network failed, try cache
                return try await getCachedEntity(entityType: entityType, endpoint: endpoint)
            }
        } else {
            // Offline, use cache only
            return try await getCachedEntity(entityType: entityType, endpoint: endpoint)
        }
    }
    
    /// Fetches array data from network if online, caches it locally, and always returns Core Data objects.
    /// This is the array version of fetchAndCache for endpoints that return arrays.
    ///
    /// **Critical Behavior:**
    /// - If online: Fetches array from network → Maps each item to Core Data → Saves → Returns Core Data entities
    /// - If offline: Returns existing Core Data entities from cache
    /// - Always returns Core Data objects, never raw network responses
    ///
    /// - Parameters:
    ///   - endpoint: The `RequestEndpoint` to fetch data from
    ///   - responseType: The expected response model type (must be Decodable & Mappable)
    ///   - entityType: The Core Data entity type to return
    /// - Returns: Array of Core Data entities of the specified type
    /// - Throws: OfflineFirstError if not configured, no cache available offline, or mapping fails
    public func fetchAndCacheArray<ResponseType: Decodable & Mappable, EntityType: NSManagedObject>(
        endpoint: RequestEndpoint,
        responseType: ResponseType.Type,
        entityType: EntityType.Type
    ) async throws -> [EntityType] where ResponseType.ManagedObjectType == EntityType {
        guard let dataSynchronizer = dataSynchronizer,
              let connectivityMonitor = connectivityMonitor,
              isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        let isOnline = connectivityMonitor.isConnected
        
        if isOnline {
            do {
                // Fetch array from network and cache using DataSynchronizer
                let entities = try await dataSynchronizer.fetchAndCacheArray(endpoint: endpoint, responseType: responseType)
                return entities as! [EntityType]
            } catch {
                print("Network fetch failed, falling back to cache: \(error)")
                // Network failed, try cache
                return try await getCachedEntities(entityType: entityType, endpoint: endpoint)
            }
        } else {
            // Offline, use cache only
            return try await getCachedEntities(entityType: entityType, endpoint: endpoint)
        }
    }
    
    /// Gets a cached Core Data entity based on the endpoint.
    private func getCachedEntity<T: NSManagedObject>(
        entityType: T.Type,
        endpoint: RequestEndpoint
    ) async throws -> T {
        guard let coreDataManager = coreDataManager else {
            throw OfflineFirstError.notConfigured
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    let fetchRequest = NSFetchRequest<T>(entityName: String(describing: entityType))
                    
                    // Try to get cached data - this is a simplified version
                    // In practice, we might need to cache based on endpoint parameters
                    let results = try backgroundContext.fetch(fetchRequest)
                    
                    if let entity = results.first {
                        continuation.resume(returning: entity)
                    } else {
                        continuation.resume(throwing: OfflineFirstError.noNetworkConnection)
                    }
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
    }
    
    /// Synchronizes data with conflict resolution from a remote endpoint with the local Core Data store.
    /// This method fetches data from the remote source and uses a ConflictResolver to handle any conflicts.
    ///
    /// - Parameters:
    ///   - endpoint: The `RequestEndpoint` to fetch data from
    ///   - responseType: The expected response model type (must be Decodable & Mappable)
    ///   - resolver: The conflict resolver to handle data conflicts
    /// - Returns: The synchronized Core Data entity
    /// - Throws: OfflineFirstError if not configured or sync fails
    public func sync<ResponseType: Decodable & Mappable, ResolverType: ConflictResolver>(
        endpoint: RequestEndpoint,
        responseType: ResponseType.Type,
        resolver: ResolverType
    ) async throws -> ResolverType.ManagedObjectType 
    where ResponseType == ResolverType.RemoteObjectType, 
          ResponseType.ManagedObjectType == ResolverType.ManagedObjectType {
        guard let dataSynchronizer = dataSynchronizer, isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        return try await dataSynchronizer.sync(endpoint: endpoint, responseType: responseType, resolver: resolver)
    }
    
    /// Synchronizes array data with conflict resolution from a remote endpoint with the local Core Data store.
    /// This method fetches array data from the remote source and uses a ConflictResolver to handle any conflicts.
    ///
    /// - Parameters:
    ///   - endpoint: The `RequestEndpoint` to fetch data from
    ///   - responseType: The expected response model type (must be Decodable & Mappable)
    ///   - resolver: The conflict resolver to handle data conflicts
    /// - Returns: Array of synchronized Core Data entities
    /// - Throws: OfflineFirstError if not configured or sync fails
    public func syncArray<ResponseType: Decodable & Mappable, ResolverType: ConflictResolver>(
        endpoint: RequestEndpoint,
        responseType: ResponseType.Type,
        resolver: ResolverType
    ) async throws -> [ResolverType.ManagedObjectType] 
    where ResponseType == ResolverType.RemoteObjectType, 
          ResponseType.ManagedObjectType == ResolverType.ManagedObjectType {
        guard let dataSynchronizer = dataSynchronizer, isConfigured else {
            throw OfflineFirstError.notConfigured
        }
        
        return try await dataSynchronizer.syncArray(endpoint: endpoint, responseType: responseType, resolver: resolver)
    }
    
    /// Gets cached Core Data entities based on the endpoint.
    private func getCachedEntities<T: NSManagedObject>(
        entityType: T.Type,
        endpoint: RequestEndpoint
    ) async throws -> [T] {
        guard let coreDataManager = coreDataManager else {
            throw OfflineFirstError.notConfigured
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let backgroundContext = coreDataManager.provider.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    let fetchRequest = NSFetchRequest<T>(entityName: String(describing: entityType))
                    let results = try backgroundContext.fetch(fetchRequest)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: OfflineFirstError.databaseError(error))
                }
            }
        }
    }
    
    /// Downloads multiple files concurrently using the batch download manager.
    ///
    /// This is a convenience method that provides access to the framework's batch download capabilities.
    /// The download operation will only proceed if the device is online.
    ///
    /// - Parameters:
    ///   - tasks: The download tasks to execute.
    ///   - configuration: Configuration options for the batch download. Uses default configuration if not provided.
    /// - Returns: A publisher that emits the final download results and completes when all downloads are finished.
    /// - Throws: A fatal error if the framework has not been configured.
    public func downloadBatch(
        tasks: [DownloadTask],
        configuration: BatchDownloadConfiguration = .default
    ) -> AnyPublisher<[DownloadResult], Error> {
        guard let batchDownloadManager = batchDownloadManager, isConfigured else {
            fatalError("OfflineFirstManager must be configured before calling downloadBatch.")
        }
        
        return batchDownloadManager.downloadBatch(tasks: tasks, configuration: configuration)
    }
}
