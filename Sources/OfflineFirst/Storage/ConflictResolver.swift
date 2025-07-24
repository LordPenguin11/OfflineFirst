import Foundation
import CoreData

/// A protocol for resolving conflicts between a remote object and a local `NSManagedObject`.
///
/// When the `DataSynchronizer` fetches data from the server, it may find that a local version of an object
/// already exists. This protocol allows you to define application-specific logic to decide how to merge the two.
public protocol ConflictResolver {
    /// The `NSManagedObject` type that this resolver handles.
    associatedtype ManagedObjectType: NSManagedObject
    
    /// Resolves a conflict between a remote object and a local managed object.
    ///
    /// - Parameters:
    ///   - remote: The `Decodable` object fetched from the server.
    ///   - local: The existing local `NSManagedObject`, or `nil` if no local version was found.
    /// - Returns: The resolved object that should be saved to the local database. This could be the remote object, the local object, or a merged combination.
    func resolve(remote: Decodable, local: ManagedObjectType?) -> ManagedObjectType
}
