import Foundation
import Combine
import SQLite

/// Manages the persistent queue of write operations, processing them when the network is available.
internal class WriteQueue {
    
    private let dbManager: DatabaseManager
    private let executor: OperationExecutor
    private let connectivityMonitor: ConnectivityMonitor
    private var cancellables = Set<AnyCancellable>()
    
    /// A flag to prevent processing the queue multiple times simultaneously.
    private var isProcessing = false
    
    /// Initializes the write queue.
    /// - Parameters:
    ///   - dbManager: The database manager for persistence.
    ///   - executor: The executor responsible for running the operations.
    ///   - connectivityMonitor: The monitor for observing network status.
    internal init(dbManager: DatabaseManager, executor: OperationExecutor, connectivityMonitor: ConnectivityMonitor) {
        self.dbManager = dbManager
        self.executor = executor
        self.connectivityMonitor = connectivityMonitor
        
        subscribeToConnectivityChanges()
    }
    
    /// Adds a new operation to the queue for later processing.
    /// - Parameter operation: The `WriteOperation` to be added.
    /// - Throws: An error if the database insertion fails.
    internal func add(operation: WriteOperation) throws {
        let insert = dbManager.operations.insert(
            dbManager.id <- operation.id,
            dbManager.functionIdentifier <- operation.functionIdentifier,
            dbManager.parameters <- operation.parameters,
            dbManager.createdAt <- operation.createdAt,
            dbManager.retryCount <- operation.retryCount
        )
        try dbManager.db.run(insert)
        
        // Trigger processing immediately if online
        if connectivityMonitor.isOnline.value {
            Task {
                await processQueue()
            }
        }
    }
    
    /// Subscribes to network connectivity changes to automatically process the queue.
    private func subscribeToConnectivityChanges() {
        connectivityMonitor.isOnline
            .sink { [weak self] isOnline in
                if isOnline {
                    Task {
                        await self?.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Processes all pending operations in the queue.
    internal func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        
        do {
            let operations = try fetchPendingOperations()
            
            for var operation in operations {
                do {
                    // Exponential backoff: 2^retryCount seconds
                    let delay = pow(2.0, Double(operation.retryCount))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    try await executor.execute(operation: operation)
                    try delete(operation: operation)
                } catch {
                    print("Failed to execute operation \(operation.id): \(error). Retrying later.")
                    operation.retryCount += 1
                    try update(operation: operation)
                }
            }
        } catch {
            print("Failed to fetch pending operations: \(error)")
        }
        
        isProcessing = false
    }
    
    /// Fetches all pending operations from the database.
    /// - Returns: An array of `WriteOperation`s.
    /// - Throws: An error if the database query fails.
    private func fetchPendingOperations() throws -> [WriteOperation] {
        var operations: [WriteOperation] = []
        for row in try dbManager.db.prepare(dbManager.operations) {
            let operation = WriteOperation(
                id: row[dbManager.id],
                functionIdentifier: row[dbManager.functionIdentifier],
                parameters: row[dbManager.parameters],
                createdAt: row[dbManager.createdAt],
                retryCount: row[dbManager.retryCount]
            )
            operations.append(operation)
        }
        return operations
    }
    
    /// Deletes a specific operation from the database.
    /// - Parameter operation: The `WriteOperation` to be deleted.
    /// - Throws: An error if the database deletion fails.
    private func delete(operation: WriteOperation) throws {
        let item = dbManager.operations.filter(dbManager.id == operation.id)
        try dbManager.db.run(item.delete())
    }
    
    /// Updates a specific operation in the database, typically to increment the retry count.
    /// - Parameter operation: The `WriteOperation` to update.
    /// - Throws: An error if the database update fails.
    private func update(operation: WriteOperation) throws {
        let item = dbManager.operations.filter(dbManager.id == operation.id)
        try dbManager.db.run(item.update(dbManager.retryCount <- operation.retryCount))
    }
}
