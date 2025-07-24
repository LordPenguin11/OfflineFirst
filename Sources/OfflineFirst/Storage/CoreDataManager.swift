import Foundation
import CoreData

/// Manages all interactions with the Core Data stack,
/// providing a simplified interface for saving and fetching data.
internal class CoreDataManager {
    
    private let provider: CoreDataProvider
    
    /// Initializes the manager with a `CoreDataProvider`.
    /// - Parameter provider: The application-specific provider for the Core Data stack.
    internal init(provider: CoreDataProvider) {
        self.provider = provider
    }
    
    /// Saves a `Mappable` object to the persistent store, performing an "upsert".
    /// It finds an existing object with the same unique identifier or creates a new one.
    /// - Parameter object: The `Mappable` object to save.
    /// - Throws: An error if the save operation fails.
    internal func save<T: Mappable>(object: T) throws {
        let context = provider.newBackgroundContext()
        let _ = try object.toManagedObject(in: context)
        
        if context.hasChanges {
            try context.save()
        }
    }
    
    /// Fetches an existing `NSManagedObject` that corresponds to a `Mappable` object.
    /// - Parameters:
    ///   - object: The `Mappable` object to find a match for.
    ///   - context: The context to fetch from.
    /// - Returns: The existing `NSManagedObject` or `nil` if not found.
    internal func findExisting<T: Mappable>(for object: T, in context: NSManagedObjectContext) -> T.ManagedObjectType? {
        let fetchRequest = T.ManagedObjectType.fetchRequest()
        // This assumes the unique identifier attribute on the NSManagedObject is named "id".
        // This might need to be made more flexible in a future iteration.
        fetchRequest.predicate = NSPredicate(format: "id == %@", object.uniqueIdentifier)
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first as? T.ManagedObjectType
        } catch {
            print("Failed to fetch existing object: \(error)")
            return nil
        }
    }
}
