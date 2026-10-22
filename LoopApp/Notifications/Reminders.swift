import Foundation
import UserNotifications
import LoopCore

/// Keuzes voor meldingen (Instellingen › Meldingen, 22 okt 2026).
enum ReminderSettings {
    static let training = "remindTraining"     // op de dag zelf, standaard aan
    static let time = "remindTime"             // minuten na middernacht, standaard 8:00
    static let evening = "remindEvening"       // de avond ervoor om 20:00, standaard uit
    static let expiry = "remindExpiry"         // app verloopt, standaard aan

    static let defaultTime = 8 * 60
    static let eveningTime = 20 * 60

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    static var trainingOn: Bool { bool(training, true) }
    static var eveningOn: Bool { bool(evening, false) }
    static var expiryOn: Bool { bool(expiry, true) }
    static var minutes: Int { UserDefaults.standard.object(forKey: time) as? Int ?? defaultTime }
    static var anyOn: Bool { trainingOn || eveningOn || expiryOn }

    /// "08:00"
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// Lokale meldingen: geen server en geen betaald account nodig.
/// Bij elke wijziging worden alle geplande meldingen opnieuw berekend (iOS houdt er max 64 bij;
/// de app plant er hooguit 30: twee weken trainingen, de avond ervoor en twee voor het verlopen).
enum Reminders {
    /// Zoveel dagen vooruit. Elke keer dat de app opent, schuift dat venster mee.
    static let daysAhead = 14

    private static var center: UNUserNotificationCenter { .current() }

    struct Item {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// Vraagt toestemming als dat nog niet gebeurd is. Geeft terug of meldingen mogen.
    @discardableResult
    static func requestIfNeeded() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return status == .authorized || status == .provisional }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Vervangt alle geplande meldingen van de app door `items`.
    static func apply(_ items: [Item]) {
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        for item in items.sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.id.hasPrefix("expiry") ? "expiry" : "training"
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Vervaldatum van deze installatie, uit het profiel dat iloader meegeeft
    /// (gratis Apple ID: 7 dagen na het installeren). Nil als er geen profiel is.
    static let expiryDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }()

    /// Meldingen voor het verlopen: de avond ervoor om 19:00 en die dag om 9:00
    /// (of 2 uur vooraf als de app vroeger op de dag verloopt).
    static func expiryItems(expiry: Date, now: Date, calendar cal: Calendar = .current) -> [Item] {
        let day = cal.startOfDay(for: expiry)
        let time = DateText.time(expiry)
        let body = "Installeer Runner opnieuw via iloader (Import IPA) om de app te kunnen blijven openen. Je gegevens blijven bewaard."
        var items: [Item] = []
        if let evening = cal.date(byAdding: .hour, value: -5, to: day), evening > now {
            items.append(Item(id: "expiry.evening", date: evening,
                              title: "Runner verloopt morgen om \(time)", body: body))
        }
        if let morning = cal.date(byAdding: .hour, value: 9, to: day) {
            let at = min(morning, expiry.addingTimeInterval(-2 * 3600))
            if at > now {
                items.append(Item(id: "expiry.day", date: at, title: "Runner verloopt vandaag om \(time)", body: body))
            }
        }
        return items
    }
}

extension AppModel {
    /// Alle meldingen opnieuw plannen: na elke wijziging aan het plan of de loopjes,
    /// bij elke terugkeer naar de app en bij een andere keuze in Instellingen.
    func rescheduleReminders(now: Date = Date()) {
        let cal = Calendar.current
        var items: [Reminders.Item] = []
        let morning = ReminderSettings.trainingOn
        let evening = ReminderSettings.eveningOn

        if coach != nil, !isSick, morning || evening {
            let today = cal.startOfDay(for: now)
            for offset in 0..<Reminders.daysAhead {
                guard let date = cal.date(byAdding: .day, value: offset, to: today),
                      let day = planDay(for: date), let w = workout(at: day), let planWeek = self.week(day),
                      run(for: day) == nil else { continue }
                let zones = planWeek.zones
                let summary = "\(TimeText.distance(w.estimatedDistance(zones: zones))) · \(Fmt.minutes(w.estimatedDuration(zones: zones)))"
                let body = "\(summary). \(WorkoutText.describe(w, zones: zones))"
                if morning, let at = cal.date(byAdding: .minute, value: ReminderSettings.minutes, to: date), at > now {
                    items.append(.init(id: "training.\(day.index)", date: at, title: "Vandaag: \(w.title)", body: body))
                }
                if evening, let at = cal.date(byAdding: .minute, value: ReminderSettings.eveningTime - 24 * 60, to: date),
                   at > now {
                    items.append(.init(id: "evening.\(day.index)", date: at, title: "Morgen: \(w.title)", body: body))
                }
            }
        }

        if ReminderSettings.expiryOn, let expiry = Reminders.expiryDate, expiry > now {
            items += Reminders.expiryItems(expiry: expiry, now: now, calendar: cal)
        }
        Reminders.apply(items)
    }
}
