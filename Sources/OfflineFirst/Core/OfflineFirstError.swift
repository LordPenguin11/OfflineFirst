import Foundation

/// Errors that can occur within the OfflineFirst framework.
public enum OfflineFirstError: Error, LocalizedError {
    /// The device is not connected to the internet.
    case noNetworkConnection
    /// A download operation failed.
    case downloadFailed(reason: String)
    /// The framework has not been configured.
    case notConfigured
    /// An operation failed to encode/decode.
    case encodingError(Error)
    /// A database operation failed.
    case databaseError(Error)
    /// An unknown error occurred.
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noNetworkConnection:
            return "No network connection available"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .notConfigured:
            return "OfflineFirst framework has not been configured"
        case .encodingError(let error):
            return "Encoding/decoding error: \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
