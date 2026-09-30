import Foundation

public enum ArrangementError: LocalizedError {
    case invalidTitle, duplicateTitle, unidentifiedDisplays, differentDisplays, differentResolution, unreadableFile
    public var errorDescription: String? {
        switch self {
        case .invalidTitle: return "Enter a title between 1 and 80 characters, without line breaks."
        case .duplicateTitle: return "An arrangement with that title already exists. Choose another title."
        case .unidentifiedDisplays: return "These displays could not be identified uniquely. Reconnect them and try again."
        case .differentDisplays: return "Connect the same displays used when this arrangement was saved."
        case .differentResolution: return "Restore the saved display resolutions and orientations before selecting this arrangement."
        case .unreadableFile: return "The saved arrangements file could not be read. It has been left unchanged."
        }
    }
}

public struct SavedArrangement: Codable, Identifiable, Equatable {
    public struct Position: Codable, Equatable {
        public let identity: String
        public let width: Double
        public let height: Double
        public let x: Double
        public let y: Double
    }
    public let id: UUID
    public var title: String
    public let positions: [Position]

    public init(title: String, displays: [Display], identities: [UInt32: String]) throws {
        try Layout.validate(displays)
        try Self.validateIdentities(displays, identities)
        self.id = UUID()
        self.title = try Self.cleanTitle(title)
        self.positions = displays.map {
            Position(identity: identities[$0.id]!, width: $0.width, height: $0.height, x: $0.x, y: $0.y)
        }
    }

    public static func cleanTitle(_ title: String) throws -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80,
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ArrangementError.invalidTitle
        }
        return clean
    }

    private static func validateIdentities(_ displays: [Display], _ identities: [UInt32: String]) throws {
        let keys = displays.compactMap { identities[$0.id] }
        guard keys.count == displays.count, !keys.contains(""), Set(keys).count == keys.count else {
            throw ArrangementError.unidentifiedDisplays
        }
    }

    /// Core Graphics numeric IDs can change after reconnecting; match persistent display UUIDs.
    /// Preserve the current main display by translating the saved coordinate system to its origin.
    public func resolve(displays: [Display], identities: [UInt32: String]) throws -> [Display] {
        try Self.validateIdentities(displays, identities)
        guard positions.count == displays.count, Set(positions.map(\.identity)).count == positions.count,
              Set(positions.map(\.identity)) == Set(displays.compactMap { identities[$0.id] }) else {
            throw ArrangementError.differentDisplays
        }
        let byIdentity = Dictionary(uniqueKeysWithValues: positions.map { ($0.identity, $0) })
        guard let main = displays.first(where: \.isMain), let origin = byIdentity[identities[main.id]!] else {
            throw LayoutError.invalid
        }
        let result = try displays.map { display -> Display in
            let saved = byIdentity[identities[display.id]!]!
            guard saved.width == display.width, saved.height == display.height else { throw ArrangementError.differentResolution }
            var next = display
            next.x = saved.x - origin.x; next.y = saved.y - origin.y
            return next
        }
        try Layout.validate(result)
        return result
    }
}

/// Writes atomically and reloads before edits, so a damaged or newer-format file is never overwritten.
public struct ArrangementStore {
    private struct Document: Codable { let version: Int; var arrangements: [SavedArrangement] }
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> [SavedArrangement] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            guard document.version == 1, Set(document.arrangements.map(\.id)).count == document.arrangements.count else {
                throw ArrangementError.unreadableFile
            }
            for item in document.arrangements { _ = try SavedArrangement.cleanTitle(item.title) }
            return document.arrangements.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch { throw ArrangementError.unreadableFile }
    }

    @discardableResult
    public func save(_ arrangement: SavedArrangement) throws -> [SavedArrangement] {
        var items = try load()
        var item = arrangement
        item.title = try SavedArrangement.cleanTitle(item.title)
        guard !items.contains(where: { $0.id != item.id && $0.title.caseInsensitiveCompare(item.title) == .orderedSame }) else {
            throw ArrangementError.duplicateTitle
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        try write(items)
        return try load()
    }

    @discardableResult
    public func remove(id: UUID) throws -> [SavedArrangement] {
        let items = try load().filter { $0.id != id }
        try write(items)
        return items
    }

    private func write(_ items: [SavedArrangement]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: 1, arrangements: items))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
