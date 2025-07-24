import Foundation

public struct WriteOperation: Codable {
    /// A unique identifier for the operation.
    public let id: UUID
    
    /// A string that identifies which API function to call (e.g., "createPost(title:content:)").
    /// This should correspond to a key in the `OperationExecutor`.
    public let functionIdentifier: String
    
    /// The encoded parameters for the API function.
    public let parameters: Data
    
    /// The timestamp when the operation was created.
    public let createdAt: Date
    
    /// The number of times this operation has been attempted.
    public var retryCount: Int
    
    public init(id: UUID = UUID(), functionIdentifier: String, parameters: Data, createdAt: Date = Date(), retryCount: Int = 0) {
        self.id = id
        self.functionIdentifier = functionIdentifier
        self.parameters = parameters
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
