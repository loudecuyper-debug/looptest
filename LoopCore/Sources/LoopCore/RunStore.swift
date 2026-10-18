import Foundation

/// Bewaart alles als JSON in één map op de iPhone:
///
///     coach.json            plan-invoer + aanpassingen van de coach
///     runs/<id>.json        één bestand per loop, met route
///     runs-index.json       korte samenvatting per loop, voor lijsten en grafieken
///     meta.json             datum van de laatste backup
///     planned-routes.json   zelf geplande routes
public struct RunStore: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
    }

    /// Standaardlocatie in de app: Documenten/LoopApp.
    public static func appDefault() throws -> RunStore {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try RunStore(directory: docs.appendingPathComponent("LoopApp", isDirectory: true))
    }

    var coachURL: URL { directory.appendingPathComponent("coach.json") }
    var indexURL: URL { directory.appendingPathComponent("runs-index.json") }
    var metaURL: URL { directory.appendingPathComponent("meta.json") }
    var plannedRoutesURL: URL { directory.appendingPathComponent("planned-routes.json") }
    var runsDirectory: URL { directory.appendingPathComponent("runs", isDirectory: true) }
    func runURL(_ id: UUID) -> URL { runsDirectory.appendingPathComponent("\(id.uuidString).json") }

    // MARK: - Coach

    public func loadCoach() throws -> Coach? {
        try read(Coach.self, from: coachURL)
    }

    public func save(_ coach: Coach) throws {
        try write(coach, to: coachURL)
    }

    // MARK: - Loopjes

    /// Bewaart een loop en werkt het overzicht bij. Dezelfde id opnieuw bewaren overschrijft.
    public func save(_ run: CompletedRun) throws {
        try write(run, to: runURL(run.id))
        var index = try summaries().filter { $0.id != run.id }
        index.append(run.summary)
        try write(sorted(index), to: indexURL)
    }

    public func loadRun(id: UUID) throws -> CompletedRun? {
        try read(CompletedRun.self, from: runURL(id))
    }

    /// Alle samenvattingen, nieuwste eerst.
    public func summaries() throws -> [RunSummary] {
        try read([RunSummary].self, from: indexURL) ?? []
    }

    /// Alle volledige loopjes, nieuwste eerst (leest alle routes in, enkel voor backup en PR's).
    public func allRuns() throws -> [CompletedRun] {
        try summaries().compactMap { try loadRun(id: $0.id) }
    }

    public func deleteRun(id: UUID) throws {
        let url = runURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try write(try summaries().filter { $0.id != id }, to: indexURL)
    }

    // MARK: - Geplande routes

    /// Alle geplande routes, nieuwste eerst.
    public func plannedRoutes() throws -> [PlannedRoute] {
        try read([PlannedRoute].self, from: plannedRoutesURL) ?? []
    }

    /// Bewaart een route. Dezelfde id opnieuw bewaren overschrijft.
    public func save(_ route: PlannedRoute) throws {
        var all = try plannedRoutes().filter { $0.id != route.id }
        all.append(route)
        try write(all.sorted { $0.created > $1.created }, to: plannedRoutesURL)
    }

    public func deletePlannedRoute(id: UUID) throws {
        try write(try plannedRoutes().filter { $0.id != id }, to: plannedRoutesURL)
    }

    // MARK: - Backup

    public func lastBackupDate() -> Date? {
        (try? read(StoreMeta.self, from: metaURL))?.lastBackup
    }

    /// Alles in één bestand, om in de Bestanden-app te bewaren.
    public func makeBackup(now: Date = Date()) throws -> Data {
        let backup = Backup(createdAt: now, coach: try loadCoach(), runs: try allRuns(),
                            plannedRoutes: try plannedRoutes())
        let data = try Self.encoder.encode(backup)
        try write(StoreMeta(lastBackup: now), to: metaURL)
        return data
    }

    /// Zet een backup terug. Vervangt alles wat er nu staat.
    @discardableResult
    public func restore(from data: Data) throws -> Backup {
        let backup = try Self.decoder.decode(Backup.self, from: data)
        guard backup.version <= Backup.currentVersion else { throw StoreError.backupTooNew }

        for s in try summaries() {
            try? FileManager.default.removeItem(at: runURL(s.id))
        }
        try write([RunSummary](), to: indexURL)
        if let coach = backup.coach {
            try save(coach)
        } else if FileManager.default.fileExists(atPath: coachURL.path) {
            try FileManager.default.removeItem(at: coachURL)
        }
        for run in backup.runs { try save(run) }
        // Oudere backups hebben nog geen routes: dan blijven de huidige staan.
        if let routes = backup.plannedRoutes {
            try write(routes.sorted { $0.created > $1.created }, to: plannedRoutesURL)
        }
        return backup
    }

    /// Herinnering om een backup te maken: na `everyDays` dagen, en enkel als er al loopjes zijn.
    public func shouldRemindBackup(now: Date = Date(), everyDays: Int = 21) throws -> Bool {
        guard try !summaries().isEmpty else { return false }
        guard let last = lastBackupDate() else { return true }
        return now.timeIntervalSince(last) >= Double(everyDays) * 86_400
    }

    // MARK: - Intern

    public enum StoreError: Error, Equatable {
        case backupTooNew
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    private func sorted(_ index: [RunSummary]) -> [RunSummary] {
        index.sorted { $0.date > $1.date }
    }
}

struct StoreMeta: Codable {
    var lastBackup: Date?
}

/// Inhoud van een backupbestand.
public struct Backup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var createdAt: Date
    public var coach: Coach?
    public var runs: [CompletedRun]
    /// Sinds 18 okt 2026. Optioneel, zodat oudere backups nog gelezen kunnen worden.
    public var plannedRoutes: [PlannedRoute]?

    public init(version: Int = Backup.currentVersion, createdAt: Date, coach: Coach?, runs: [CompletedRun],
                plannedRoutes: [PlannedRoute]? = nil) {
        self.version = version
        self.createdAt = createdAt
        self.coach = coach
        self.runs = runs
        self.plannedRoutes = plannedRoutes
    }

    /// Bestandsnaam, bv. "LoopApp-backup-2026-10-15.json".
    public static func fileName(for date: Date, calendar: Calendar = PlanCalendar.default) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "LoopApp-backup-%04ld-%02ld-%02ld.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
