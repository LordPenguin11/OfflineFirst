import Foundation

/// Defines the retry strategy for operations that fail.
public struct RetryPolicy {
    /// The maximum number of times an operation should be retried before being aborted.
    public let maxRetries: Int
    
    /// A list of HTTP status codes that should be considered "dead-end" errors.
    /// If the executor throws an error with one of these codes, the operation will be aborted immediately without retrying.
    public let unrecoverableHTTPSatusCodes: [Int]
    
    /// Initializes a new retry policy.
    /// - Parameters:
    ///   - maxRetries: The maximum number of retries. Defaults to 5.
    ///   - unrecoverableHTTPSatusCodes: A list of status codes that should cause immediate failure. Defaults to a standard list of client and server errors.
    public init(
        maxRetries: Int = 5,
        unrecoverableHTTPSatusCodes: [Int] = [300, 400, 403, 404, 405, 406, 410, 415, 422, 501]
    ) {
        self.maxRetries = maxRetries
        self.unrecoverableHTTPSatusCodes = unrecoverableHTTPSatusCodes
    }
}
