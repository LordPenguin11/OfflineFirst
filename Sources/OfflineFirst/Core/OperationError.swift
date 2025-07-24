import Foundation

/// An error type that provides more context about a failed operation, specifically the HTTP status code.
///
/// Your application's custom error types thrown by the `OperationExecutor` should conform to this protocol
/// to allow the framework to make decisions based on the HTTP status code.
public protocol OperationError: Error {
    /// The HTTP status code associated with the error (e.g., 404, 500).
    var httpStatusCode: Int? { get }
}
