import Foundation

/// Represents a file attachment for multipart/form-data uploads.
public struct FileAttachment: Codable {
    /// The name of the form field.
    public let fieldName: String
    
    /// The original filename.
    public let fileName: String
    
    /// The MIME type of the file.
    public let mimeType: String
    
    /// The file data.
    public let data: Data
    
    public init(fieldName: String, fileName: String, mimeType: String, data: Data) {
        self.fieldName = fieldName
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

/// Represents a multipart form data request that can be queued for offline execution.
public struct MultipartWriteOperation: Codable {
    /// A unique identifier for the operation.
    public let id: UUID
    
    /// A string that identifies which API function to call.
    public let functionIdentifier: String
    
    /// The regular form parameters (non-file data).
    public let parameters: Data
    
    /// The file attachments for this operation.
    public let attachments: [FileAttachment]
    
    /// The timestamp when the operation was created.
    public let createdAt: Date
    
    /// The number of times this operation has been attempted.
    public var retryCount: Int
    
    public init(
        id: UUID = UUID(),
        functionIdentifier: String,
        parameters: Data,
        attachments: [FileAttachment] = [],
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.functionIdentifier = functionIdentifier
        self.parameters = parameters
        self.attachments = attachments
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
