import Foundation
import SQLite

/// Manages the connection to the SQLite database and the creation of the operations table.
internal class DatabaseManager {
    
    /// The connection to the SQLite database.
    internal let db: Connection
    
    /// The table for storing `WriteOperation`s.
    internal let operations = Table("operations")
    
    // Columns for the "operations" table
    internal let id = Expression<UUID>("id")
    internal let functionIdentifier = Expression<String>("functionIdentifier")
    internal let parameters = Expression<Data>("parameters")
    internal let createdAt = Expression<Date>("createdAt")
    internal let retryCount = Expression<Int>("retryCount")
    
    /// Initializes the database manager and sets up the database file and table.
    /// - Throws: An error if the database connection or table creation fails.
    internal init() throws {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        db = try Connection("\(path)/offline_first.sqlite3")
        
        try createTableIfNeeded()
    }
    
    /// Creates the "operations" table if it does not already exist.
    private func createTableIfNeeded() throws {
        try db.run(operations.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(functionIdentifier)
            t.column(parameters)
            t.column(createdAt)
            t.column(retryCount)
        })
    }
}
