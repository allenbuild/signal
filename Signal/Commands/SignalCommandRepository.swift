import Foundation

public enum SignalCommandRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case nonFileURL
    case missingDocument
    case fileTooLarge(Int)
    case nonRegularFile

    public var errorDescription: String? {
        switch self {
        case .nonFileURL:
            "Command documents must use file URLs."
        case .missingDocument:
            "No saved command document exists."
        case .fileTooLarge(let bytes):
            "The command document is too large (\(bytes) bytes)."
        case .nonRegularFile:
            "The command document must be a regular, non-symbolic-link file."
        }
    }
}

public actor SignalCommandRepository {
    public static let activeFilename = "active-v1.json"

    private let directory: URL
    private let validator: SignalCommandValidator

    public init(
        directory: URL? = nil,
        validator: SignalCommandValidator = .init()
    ) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.directory = directory
            ?? applicationSupport
                .appendingPathComponent("Signal", isDirectory: true)
                .appendingPathComponent("Commands", isDirectory: true)
        self.validator = validator
    }

    public func loadOrInstallDefaults() throws -> SignalCommandDocument {
        let fileURL = activeDocumentURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = SignalDefaultCommandCatalog.document
            try save(defaults)
            return defaults
        }
        return try decodeDocument(at: fileURL)
    }

    public func load() throws -> SignalCommandDocument {
        guard FileManager.default.fileExists(atPath: activeDocumentURL.path) else {
            throw SignalCommandRepositoryError.missingDocument
        }
        return try decodeDocument(at: activeDocumentURL)
    }

    public func save(_ document: SignalCommandDocument) throws {
        try validator.validate(document)
        let data = try encodedData(for: document)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: activeDocumentURL, options: .atomic)
    }

    public func importDocument(from source: URL) throws -> SignalCommandDocument {
        try decodeDocument(at: source)
    }

    @discardableResult
    public func installImportedDocument(from source: URL) throws -> SignalCommandDocument {
        let document = try importDocument(from: source)
        try save(document)
        return document
    }

    public func export(_ document: SignalCommandDocument, to destination: URL) throws {
        guard destination.isFileURL else {
            throw SignalCommandRepositoryError.nonFileURL
        }
        try validator.validate(document)
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw SignalCommandRepositoryError.nonRegularFile
            }
        }
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try encodedData(for: document).write(to: destination, options: .atomic)
    }

    public func encodedData(for document: SignalCommandDocument) throws -> Data {
        try validator.validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try validator.validateClosedJSON(data)
        return data
    }

    private var activeDocumentURL: URL {
        directory.appendingPathComponent(Self.activeFilename, isDirectory: false)
    }

    private func decodeDocument(at url: URL) throws -> SignalCommandDocument {
        guard url.isFileURL else {
            throw SignalCommandRepositoryError.nonFileURL
        }
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SignalCommandRepositoryError.nonRegularFile
        }
        if let size = values.fileSize, size > SignalCommandValidator.maximumImportBytes {
            throw SignalCommandRepositoryError.fileTooLarge(size)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= SignalCommandValidator.maximumImportBytes else {
            throw SignalCommandRepositoryError.fileTooLarge(data.count)
        }
        try validator.validateClosedJSON(data)
        let document = try JSONDecoder().decode(SignalCommandDocument.self, from: data)
        try validator.validate(document)
        return document
    }
}
