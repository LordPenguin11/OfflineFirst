import Foundation
import Combine
import AspynNetwork

//
//  BatchDownloadManager.swift
//  OfflineFirst
//
//  Created by Long Vo on 24/07/2024.
//

/// Represents a single download task in a batch download operation.
public struct DownloadTask {
    /// Unique identifier for this download task.
    public let id: UUID
    /// The URL to download from.
    public let url: URL
    /// The local file URL where the downloaded content will be saved.
    public let destinationURL: URL
    /// Optional metadata associated with this download.
    public let metadata: [String: Any]?
    
    /// Creates a new download task.
    /// - Parameters:
    ///   - url: The URL to download from.
    ///   - destinationURL: The local file URL where the content will be saved.
    ///   - metadata: Optional metadata to associate with this download.
    public init(url: URL, destinationURL: URL, metadata: [String: Any]? = nil) {
        self.id = UUID()
        self.url = url
        self.destinationURL = destinationURL
        self.metadata = metadata
    }
}

/// Represents the result of a single download task.
public struct DownloadResult {
    /// The original download task.
    public let task: DownloadTask
    /// The result of the download operation.
    public let result: Result<URL, Error>
    /// The time when the download completed.
    public let completedAt: Date
    
    /// Creates a new download result.
    /// - Parameters:
    ///   - task: The original download task.
    ///   - result: The result of the download operation.
    internal init(task: DownloadTask, result: Result<URL, Error>) {
        self.task = task
        self.result = result
        self.completedAt = Date()
    }
}

/// Configuration options for batch download operations.
public struct BatchDownloadConfiguration {
    /// Maximum number of concurrent downloads. Default is 3.
    public let maxConcurrentDownloads: Int
    /// Timeout interval for each download in seconds. Default is 30.
    public let timeoutInterval: TimeInterval
    /// Whether to continue downloading other files if one fails. Default is true.
    public let continueOnError: Bool
    /// Custom HTTP headers to include with each request.
    public let headers: [String: String]
    
    /// Creates a new batch download configuration.
    /// - Parameters:
    ///   - maxConcurrentDownloads: Maximum number of concurrent downloads.
    ///   - timeoutInterval: Timeout interval for each download in seconds.
    ///   - continueOnError: Whether to continue if one download fails.
    ///   - headers: Custom HTTP headers to include.
    public init(
        maxConcurrentDownloads: Int = 3,
        timeoutInterval: TimeInterval = 30,
        continueOnError: Bool = true,
        headers: [String: String] = [:]
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.timeoutInterval = timeoutInterval
        self.continueOnError = continueOnError
        self.headers = headers
    }
    
    /// Default configuration with standard settings.
    public static let `default` = BatchDownloadConfiguration()
}

/// Progress information for a batch download operation.
public struct BatchDownloadProgress {
    /// Number of downloads completed (successfully or with error).
    public let completed: Int
    /// Total number of downloads in the batch.
    public let total: Int
    /// Number of successful downloads.
    public let successful: Int
    /// Number of failed downloads.
    public let failed: Int
    /// Overall progress as a percentage (0.0 to 1.0).
    public var progress: Double {
        guard total > 0 else { return 0.0 }
        return Double(completed) / Double(total)
    }
    
    /// Creates new progress information.
    /// - Parameters:
    ///   - completed: Number of completed downloads.
    ///   - total: Total number of downloads.
    ///   - successful: Number of successful downloads.
    ///   - failed: Number of failed downloads.
    internal init(completed: Int, total: Int, successful: Int, failed: Int) {
        self.completed = completed
        self.total = total
        self.successful = successful
        self.failed = failed
    }
}

/// A utility class for managing batch download operations with offline-first capabilities.
///
/// The `BatchDownloadManager` provides an efficient way to download multiple files concurrently
/// while respecting network connectivity and providing progress updates.
///
/// ## Example Usage
/// ```swift
/// let downloadManager = BatchDownloadManager(network: myNetworkClient)
/// 
/// let tasks = [
///     DownloadTask(url: URL(string: "https://example.com/file1.pdf")!, 
///                  destinationURL: documentsURL.appendingPathComponent("file1.pdf")),
///     DownloadTask(url: URL(string: "https://example.com/file2.jpg")!, 
///                  destinationURL: documentsURL.appendingPathComponent("file2.jpg"))
/// ]
/// 
/// let config = BatchDownloadConfiguration(maxConcurrentDownloads: 2)
/// 
/// downloadManager.downloadBatch(tasks: tasks, configuration: config)
///     .sink(
///         receiveCompletion: { completion in
///             switch completion {
///             case .finished:
///                 print("All downloads completed")
///             case .failure(let error):
///                 print("Batch download failed: \(error)")
///             }
///         },
///         receiveValue: { results in
///             print("Downloaded \(results.count) files")
///         }
///     )
///     .store(in: &cancellables)
/// ```
public class BatchDownloadManager {
    
    private let network: NetworkProtocol
    private let connectivityMonitor: ConnectivityMonitor
    private let fileManager: FileManager
    
    /// A publisher that emits progress updates during batch download operations.
    public let progressPublisher = PassthroughSubject<BatchDownloadProgress, Never>()
    
    /// Creates a new batch download manager.
    /// - Parameter network: The network client to use for downloads.
    public init(network: NetworkProtocol) {
        self.network = network
        self.connectivityMonitor = ConnectivityMonitor()
        self.fileManager = FileManager.default
    }
    
    /// Downloads a batch of files concurrently.
    /// - Parameters:
    ///   - tasks: The download tasks to execute.
    ///   - configuration: Configuration options for the batch download.
    /// - Returns: A publisher that emits the final download results and completes when all downloads are finished.
    public func downloadBatch(
        tasks: [DownloadTask],
        configuration: BatchDownloadConfiguration = .default
    ) -> AnyPublisher<[DownloadResult], Error> {
        
        // Check if we're online
        guard connectivityMonitor.isConnected else {
            return Fail(error: OfflineFirstError.noNetworkConnection)
                .eraseToAnyPublisher()
        }
        
        // Validate tasks
        guard !tasks.isEmpty else {
            return Just([])
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Create directories for destination URLs if needed
        createDestinationDirectories(for: tasks)
        
        let semaphore = DispatchSemaphore(value: configuration.maxConcurrentDownloads)
        let progress = ProgressTracker(total: tasks.count)
        
        let publishers = tasks.map { task in
            downloadSingle(task: task, configuration: configuration, semaphore: semaphore, progress: progress)
        }
        
        return Publishers.MergeMany(publishers)
            .collect()
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    /// Downloads a single file as part of a batch operation.
    private func downloadSingle(
        task: DownloadTask,
        configuration: BatchDownloadConfiguration,
        semaphore: DispatchSemaphore,
        progress: ProgressTracker
    ) -> AnyPublisher<DownloadResult, Never> {
        
        return Future<DownloadResult, Never> { promise in
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait() // Wait for available slot
                
                defer {
                    semaphore.signal() // Release slot when done
                }
                
                // Create URL request
                var request = URLRequest(url: task.url)
                request.timeoutInterval = configuration.timeoutInterval
                
                // Add custom headers
                for (key, value) in configuration.headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                
                // Perform download
                let downloadResult = self.performDownload(request: request, destinationURL: task.destinationURL)
                let result = DownloadResult(task: task, result: downloadResult)
                
                // Update progress
                progress.update(with: result)
                self.progressPublisher.send(progress.currentProgress)
                
                promise(.success(result))
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Performs the actual download operation.
    private func performDownload(request: URLRequest, destinationURL: URL) -> Result<URL, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var downloadResult: Result<URL, Error>?
        
        let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                downloadResult = .failure(error)
                return
            }
            
            guard let tempURL = tempURL else {
                downloadResult = .failure(OfflineFirstError.downloadFailed(reason: "No temporary file URL"))
                return
            }
            
            do {
                // Remove existing file if it exists
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }
                
                // Move downloaded file to destination
                try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                downloadResult = .success(destinationURL)
                
            } catch {
                downloadResult = .failure(error)
            }
        }
        
        task.resume()
        semaphore.wait()
        
        return downloadResult ?? .failure(OfflineFirstError.downloadFailed(reason: "Unknown error"))
    }
    
    /// Creates destination directories for download tasks if they don't exist.
    private func createDestinationDirectories(for tasks: [DownloadTask]) {
        let directories = Set(tasks.map { $0.destinationURL.deletingLastPathComponent() })
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create directory \(directory): \(error)")
            }
        }
    }
}

/// Internal class to track progress across concurrent downloads.
private class ProgressTracker {
    private let total: Int
    private var completed = 0
    private var successful = 0
    private var failed = 0
    private let lock = NSLock()
    
    init(total: Int) {
        self.total = total
    }
    
    func update(with result: DownloadResult) {
        lock.lock()
        defer { lock.unlock() }
        
        completed += 1
        
        switch result.result {
        case .success:
            successful += 1
        case .failure:
            failed += 1
        }
    }
    
    var currentProgress: BatchDownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        
        return BatchDownloadProgress(
            completed: completed,
            total: total,
            successful: successful,
            failed: failed
        )
    }
}
