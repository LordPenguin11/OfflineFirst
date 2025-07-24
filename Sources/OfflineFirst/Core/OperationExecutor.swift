import Foundation

/// A protocol that the application must implement to execute queued write operations.
///
/// The framework calls the `execute(operation:)` method when it's time to replay a stored
/// operation. The implementation should decode the parameters and call the
/// corresponding method on the application's real API client.
///
/// To avoid large switch statements, the recommended approach is to use a dictionary of handlers,
/// where the key is the `functionIdentifier` from the `WriteOperation`.
///
/// ## Example Implementation
/// ```swift
/// class MyAppOperationExecutor: OperationExecutor {
///     typealias Handler = (Data) async throws -> Void
///     private let apiClient: APIClient
///     private var handlers: [String: Handler] = [:]
///
///     init(apiClient: APIClient) {
///         self.apiClient = apiClient
///         registerHandlers()
///     }
///
///     private func registerHandlers() {
///         handlers["createPost"] = { [weak self] data in
///             let params = try JSONDecoder().decode(CreatePostParams.self, from: data)
///             try await self?.apiClient.createPost(title: params.title, content: params.content)
///         }
///         // ... register other handlers
///     }
///
///     func execute(operation: WriteOperation) async throws {
///         guard let handler = handlers[operation.functionIdentifier] else {
///             throw MyError.handlerNotFound
///         }
///         try await handler(operation.parameters)
///     }
/// }
/// ```
public protocol OperationExecutor {
    /// Executes a given write operation.
    ///
    /// The implementation of this method should look up the appropriate handler
    /// based on the `operation.functionIdentifier`, decode the `operation.parameters`,
    /// and execute the corresponding API call.
    ///
    /// - Parameter operation: The `WriteOperation` to be executed.
    /// - Throws: An error if the handler is not found, decoding fails, or the underlying API call fails.
    func execute(operation: WriteOperation) async throws
}
