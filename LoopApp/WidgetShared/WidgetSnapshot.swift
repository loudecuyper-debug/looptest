import Foundation

// Gedeeld tussen de app en RunnerWidgets (27 okt 2026).
// De app schrijft wat de widget "training van vandaag" moet tonen naar de gedeelde map van de
// App Group; de widget leest het daar. Zo heeft de widget geen LoopCore of plan-logica nodig.
//
// De App Group: iloader (isideload) maakt bij het installeren zelf een groep aan,
// "group.<bundle-ID van de app>", en geeft die aan de app en de extensie. De bundle-ID krijgt
// daarbij je team-ID erachter, dus de naam staat niet vast: we lezen ze uit het meegeleverde
// profiel, en anders leiden we ze af uit de bundle-ID. Zonder groep toont de widget "Open Runner".

/// Wat de widget toont: de trainingen van de komende twee weken en de weekkilometers.
struct WidgetSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable {
        /// Begin van de dag.
        var date: Date
        var title: String
        /// Typelabel in hoofdletters, bv. "INTERVAL".
        var label: String
        /// Typekleur als hex.
        var color: UInt32
        var km: Double
        var minutes: Int
        var done: Bool
        var extra: Bool
    }

    struct Week: Codable, Equatable {
        /// Maandag.
        var start: Date
        var plannedKm: Double
        var doneKm: Double
    }

    var created: Date
    var days: [Day]
    var weeks: [Week]
    /// Ziek gemeld: trainingen staan op pauze.
    var sick: Bool
    /// Eerste dag van het plan (voor "Je plan start ...").
    var planStart: Date?
    /// Laatste dag van het plan.
    var planEnd: Date?

    /// Training op een dag, nil = rustdag.
    func day(_ date: Date, calendar: Calendar) -> Day? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Eerstvolgende training na een dag.
    func next(after date: Date, calendar: Calendar) -> Day? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.date > start && !calendar.isDate($0.date, inSameDayAs: date) }
    }

    func week(containing date: Date, calendar: Calendar) -> Week? {
        weeks.first { w in
            guard let end = calendar.date(byAdding: .day, value: 7, to: w.start) else { return false }
            return date >= w.start && date < end
        }
    }
}

enum WidgetShare {
    static let fileName = "widget-today.json"
    /// Naam van de widget, voor `WidgetCenter.reloadTimelines(ofKind:)`.
    static let kind = "RunnerToday"

    /// Groepen die het profiel van deze installatie toestaat, uit embedded.mobileprovision.
    private static var provisionedGroups: [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        let entitlements = plist?["Entitlements"] as? [String: Any]
        return entitlements?["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// "group.<bundle-ID van de app>", ook vanuit de extensie (die heet "<app>.widgets").
    private static var derivedGroup: String? {
        guard var id = Bundle.main.bundleIdentifier else { return nil }
        if id.hasSuffix(".widgets") { id.removeLast(".widgets".count) }
        return "group." + id
    }

    /// Gedeelde map, nil als deze installatie geen App Group heeft.
    static let directory: URL? = {
        var candidates = provisionedGroups
        if let derived = derivedGroup, !candidates.contains(derived) { candidates.append(derived) }
        for group in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return url
            }
        }
        return nil
    }()

    static var isAvailable: Bool { directory != nil }

    private static var fileURL: URL? { directory?.appendingPathComponent(fileName) }

    static func write(_ snapshot: WidgetSnapshot?) {
        guard let url = fileURL else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
