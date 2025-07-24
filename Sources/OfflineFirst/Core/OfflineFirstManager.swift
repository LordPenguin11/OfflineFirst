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
    
    /// Queues a write operation to be executed when the network is available.
    ///
    /// Use this method to register a function call that should be executed against your backend. The operation is saved to a persistent queue
    /// and will be automatically attempted when the device comes online. If the execution fails, it will be retried with an exponential backoff strategy.
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the function to be executed. This should match a key in your `OperationExecutor`'s handler dictionary.
    ///   - parameters: An `Encodable` object representing the parameters for the function. These will be encoded to `Data` for storage.
    /// - Throws: An error if the framework has not been configured, or if the operation fails to be encoded or saved to the database.
    public func queueWrite(functionIdentifier: String, parameters: Encodable) throws {
        guard let writeQueue = writeQueue, isConfigured else {
            fatalError("OfflineFirstManager must be configured before calling queueWrite.")
        }
        
        let paramsData = try JSONEncoder().encode(parameters)
        
        let operation = WriteOperation(
            functionIdentifier: functionIdentifier,
            parameters: paramsData
        )
        
        try writeQueue.add(operation: operation)
    }
    
    /// Queues a multipart write operation (with file attachments) to be executed when the network is available.
    ///
    /// Use this method to register a multipart/form-data operation that includes file uploads. The operation is saved to a persistent queue
    /// and will be automatically attempted when the device comes online. If the execution fails, it will be retried with an exponential backoff strategy.
    ///
    /// - Parameters:
    ///   - functionIdentifier: A unique string that identifies the function to be executed. This should match a key in your `OperationExecutor`'s handler dictionary.
    ///   - parameters: An `Encodable` object representing the parameters for the function. These will be encoded to `Data` for storage.
    ///   - attachments: An array of `FileAttachment` objects representing the files to be uploaded as part of this operation.
    /// - Throws: An error if the framework has not been configured, or if the operation fails to be encoded or saved to the database.
    public func queueMultipartWrite(functionIdentifier: String, parameters: Encodable, attachments: [FileAttachment]) throws {
        guard let writeQueue = writeQueue, isConfigured else {
            fatalError("OfflineFirstManager must be configured before calling queueMultipartWrite.")
        }
        
        let paramsData = try JSONEncoder().encode(parameters)
        
        let operation = MultipartWriteOperation(
            functionIdentifier: functionIdentifier,
            parameters: paramsData,
            attachments: attachments
        )
        
        try writeQueue.add(multipartOperation: operation)
    }
    
    // Note: Sync functionality will be refined in a future iteration
    // to properly handle array responses and conflict resolution
    /*
    /// Synchronizes data for a given network endpoint, handling conflicts with the provided resolver.
    ///
    /// This function fetches data from a remote source, compares it with the local data in your Core Data store,
    /// and uses a `ConflictResolver` to merge any differences. This is the primary mechanism for keeping the on-device cache up-to-date.
    ///
    /// - Parameters:
    ///   - endpoint: The `RequestEndpoint` to fetch data from. The response type must be `Decodable`.
    ///   - responseType: The type of the expected response data.
    ///   - resolver: An object conforming to `ConflictResolver` that defines the logic for handling data conflicts between the remote and local versions of an object.
    /// - Throws: An error if the framework is not configured, or if the network request or data processing fails.
    public func sync<T, R>(endpoint: RequestEndpoint, responseType: T.Type, resolver: R) async throws where T: Decodable, R: ConflictResolver, T == R.ManagedObjectType {
        guard let dataSynchronizer = dataSynchronizer, isConfigured else {
            fatalError("OfflineFirstManager must be configured before calling sync.")
        }
        
        try await dataSynchronizer.sync(endpoint: endpoint, responseType: responseType, resolver: resolver)
    }
    */
    
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
