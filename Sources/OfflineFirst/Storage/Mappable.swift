import Foundation
import CoreData

/// A protocol defining the contract for mapping a `Decodable` object to a `NSManagedObject`.
///
/// Your application's network response models should conform to this protocol to enable the framework
/// to save them into the Core Data store.
public protocol Mappable {
    /// The `NSManagedObject` type that this object maps to (e.g., `PostEntity`).
    associatedtype ManagedObjectType: NSManagedObject
    
    /// A unique identifier used to find an existing managed object in the store to prevent duplicates.
    /// This should be a stable identifier, such as a UUID or a server-provided ID.
    var uniqueIdentifier: String { get }
    
    /// Maps the properties of this object to a new or existing `NSManagedObject`.
    ///
    /// In this method, you should either create a new `ManagedObjectType` instance or fetch an existing one
    /// using the `uniqueIdentifier`, and then transfer all relevant properties from `self` to the managed object.
    ///
    /// - Parameter context: The `NSManagedObjectContext` in which to create or update the object.
    /// - Returns: The mapped `NSManagedObject`.
    /// - Throws: An error if the mapping fails.
    func toManagedObject(in context: NSManagedObjectContext) throws -> ManagedObjectType
}
