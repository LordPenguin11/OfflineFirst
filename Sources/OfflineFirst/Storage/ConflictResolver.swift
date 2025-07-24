import Foundation
import CoreData

/// A protocol for resolving conflicts between a remote object and a local `NSManagedObject`.
///
/// When the `DataSynchronizer` fetches data from the server, it may find that a local version of an object
/// already exists. This protocol allows you to define application-specific logic to decide how to merge the two.
public protocol ConflictResolver {
    /// The remote object type (Decodable & Mappable) that this resolver handles.
    associatedtype RemoteObjectType: Decodable & Mappable
    /// The `NSManagedObject` type that this resolver handles.
    associatedtype ManagedObjectType: NSManagedObject
    
    /// Resolves a conflict between a remote object and a local managed object.
    ///
    /// This method receives the remote object and the Core Data context, and should:
    /// 1. Look for an existing local version using the remote object's uniqueIdentifier
    /// 2. Apply your conflict resolution logic (client-wins, server-wins, or merge)
    /// 3. Return the resolved Core Data entity
    ///
    /// - Parameters:
    ///   - remoteData: The typed remote object fetched from the server.
    ///   - context: The Core Data context to work with.
    /// - Returns: The resolved Core Data entity that should be saved to the local database.
    func resolve(remoteData: RemoteObjectType, in context: NSManagedObjectContext) -> ManagedObjectType
}
