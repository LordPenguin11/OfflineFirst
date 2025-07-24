import Foundation
import CoreData

/// A protocol that the application must implement to provide the Core Data stack to the framework.
///
/// The framework requires access to your app's `NSManagedObjectContext` to save and synchronize data.
/// Your app should have a class or struct that conforms to this protocol and provides the required contexts.
///
/// ## Example Implementation
/// ```swift
/// class MyCoreDataProvider: CoreDataProvider {
///     private let persistentContainer: NSPersistentContainer
///
///     init() {
///         persistentContainer = NSPersistentContainer(name: "MyDataModel")
///         persistentContainer.loadPersistentStores { _, error in
///             if let error = error {
///                 fatalError("Failed to load Core Data stack: \(error)")
///             }
///         }
///     }
///
///     var viewContext: NSManagedObjectContext {
///         return persistentContainer.viewContext
///     }
///
///     func newBackgroundContext() -> NSManagedObjectContext {
///         return persistentContainer.newBackgroundContext()
///     }
/// }
/// ```
public protocol CoreDataProvider {
    /// The main view context, typically used for UI-related operations on the main thread.
    var viewContext: NSManagedObjectContext { get }
    
    /// Creates and returns a new background context for performing write and sync operations off the main thread.
    func newBackgroundContext() -> NSManagedObjectContext
}
