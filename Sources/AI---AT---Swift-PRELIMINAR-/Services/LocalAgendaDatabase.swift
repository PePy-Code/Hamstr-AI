import Foundation

public struct LocalAgendaDatabase: AgendaPersistenceProviding {
    private let fileURL: URL

    public init(
        fileURL: URL? = nil
    ) {
        self.fileURL = Self.resolveFileURL(fileURL: fileURL, fileManager: .default)
    }

    /// Compatibility initializer.
    /// - Important: `fileManager` is used only to resolve the default database path when `fileURL` is `nil`.
    @available(*, deprecated, message: "Use init(fileURL:) instead. fileManager is only used to resolve default path when fileURL is nil.")
    public init(
        fileURL: URL? = nil,
        fileManager: FileManager
    ) {
        self.fileURL = Self.resolveFileURL(fileURL: fileURL, fileManager: fileManager)
    }

    private static func resolveFileURL(fileURL: URL?, fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("AcademicTrainer", isDirectory: true)
        return fileURL ?? directoryURL.appendingPathComponent("agenda.json")
    }

    public func load() throws -> AgendaStorageSnapshot? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgendaStorageSnapshot.self, from: data)
    }

    public func save(_ snapshot: AgendaStorageSnapshot) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
