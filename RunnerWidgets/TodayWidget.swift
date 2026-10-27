import WidgetKit
import SwiftUI

// Widget "training van vandaag" (27 okt 2026), in stijl D.
// Klein: wat je vandaag loopt (of rustdag en de volgende training) en je weekkilometers.
// Middel: idem, met rechts de komende trainingen. Vergrendelscherm: één regel type, één regel inhoud.
// De gegevens komen van de app (`WidgetSnapshot` in de gedeelde map). Tik = Runner openen.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let real = WidgetShare.read()
        completion(TodayEntry(date: Date(), snapshot: real ?? (context.isPreview ? .sample : nil)))
    }

    /// Een moment nu en één op elke middernacht van de komende week; de app ververst bij elke wijziging.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = WidgetShare.read()
        let now = Date()
        var entries = [TodayEntry(date: now, snapshot: snapshot)]
        let today = calendar.startOfDay(for: now)
        for offset in 1...7 {
            if let d = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(TodayEntry(date: d, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShare.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(W.background, for: .widget)
        }
        .configurationDisplayName("Training van vandaag")
        .description("Je training van vandaag, de volgende training en je weekkilometers.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Wat er vandaag te tonen is

private struct TodayState {
    enum Kind {
        case noData, sick, finished, notStarted(Date), training(WidgetSnapshot.Day), rest
    }

    let kind: Kind
    let next: WidgetSnapshot.Day?
    let upcoming: [WidgetSnapshot.Day]
    let week: WidgetSnapshot.Week?

    init(entry: TodayEntry, calendar: Calendar) {
        guard let s = entry.snapshot else {
            kind = .noData; next = nil; upcoming = []; week = nil
            return
        }
        let date = entry.date
        let today = calendar.startOfDay(for: date)
        next = s.next(after: date, calendar: calendar)
        upcoming = s.days.filter { $0.date > today && !calendar.isDate($0.date, inSameDayAs: date) }
        week = s.week(containing: date, calendar: calendar)
        if let end = s.planEnd, today > end {
            kind = .finished
        } else if s.sick {
            kind = .sick
        } else if let start = s.planStart, today < calendar.startOfDay(for: start) {
            kind = .notStarted(start)
        } else if let day = s.day(date, calendar: calendar) {
            kind = .training(day)
        } else {
            kind = .rest
        }
    }
}

private enum WText {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_BE")
        f.dateFormat = format
        return f
    }

    private static let weekdayF = formatter("EEEE")
    private static let shortF = formatter("EEE d MMM")
    private static let dayShortF = formatter("EEE")

    static func km(_ km: Double) -> String {
        String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") + " km"
    }

    static func summary(_ d: WidgetSnapshot.Day) -> String { "\(km(d.km)) · \(d.minutes) min" }

    /// "Morgen", "Donderdag" of "Do 5 nov".
    static func when(_ date: Date, from now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "Morgen" }
        if days < 7 { return weekdayF.string(from: date).capitalized }
        return shortF.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }

    /// "DO"
    static func dayShort(_ date: Date) -> String {
        dayShortF.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }
}

// MARK: - Weergave

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    var body: some View {
        let state = TodayState(entry: entry, calendar: calendar)
        switch family {
        case .accessoryRectangular:
            LockScreenToday(state: state, date: entry.date, calendar: calendar)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                MainToday(state: state, date: entry.date, calendar: calendar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                UpcomingList(days: Array(state.upcoming.prefix(3)), date: entry.date, calendar: calendar)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            MainToday(state: state, date: entry.date, calendar: calendar)
        }
    }
}

private struct SmallLabel: View {
    let text: String
    var color: Color = W.secondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct MainToday: View {
    let state: TodayState
    let date: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch state.kind {
            case .training(let day):
                SmallLabel(text: day.done ? "Vandaag · gelopen" : "Vandaag")
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: day.color)).frame(width: 8, height: 8)
                    Text(day.extra ? "EXTRA · \(day.label)" : day.label)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color(hex: day.color))
                        .lineLimit(1)
                }
                .padding(.top, 2)
                Text(day.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(W.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if day.done {
                    Label("Gelopen", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(W.good)
                } else {
                    Text(WText.summary(day))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(W.secondary)
                        .monospacedDigit()
                }
            case .rest:
                SmallLabel(text: "Rustdag")
                Text("Geen training vandaag")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(W.text)
                    .lineLimit(2)
                    .padding(.top, 2)
                if let next = state.next {
                    nextLine(next)
                }
            case .notStarted(let start):
                SmallLabel(text: "Je plan start")
                Text(WText.when(start, from: date, calendar: calendar))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(W.text)
                    .padding(.top, 2)
                if let next = state.next {
                    Text(next.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(W.secondary)
                        .lineLimit(1)
                }
            case .sick:
                SmallLabel(text: "Pauze", color: W.accent)
                Text("Ziek gemeld")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(W.text)
                    .padding(.top, 2)
                Text("Duid in Runner aan wanneer je beter bent.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(W.secondary)
                    .lineLimit(3)
            case .finished:
                SmallLabel(text: "Plan afgerond")
                Text("Maak een nieuw plan in Runner.")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(W.text)
                    .lineLimit(3)
                    .padding(.top, 2)
            case .noData:
                SmallLabel(text: "Runner")
                Text("Open Runner om je training te zien.")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(W.text)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if let week = state.week, week.plannedKm > 0 {
                WeekBar(week: week)
            }
        }
    }

    private func nextLine(_ next: WidgetSnapshot.Day) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WText.when(next.date, from: date, calendar: calendar))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(W.secondary)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: next.color)).frame(width: 8, height: 8)
                Text(next.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(W.text)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}

/// "9,5 van 17,6 km" met een oranje balkje.
private struct WeekBar: View {
    let week: WidgetSnapshot.Week

    var body: some View {
        let fraction = min(max(week.doneKm / week.plannedKm, 0), 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(WText.km(week.doneKm).replacingOccurrences(of: " km", with: "")) van \(WText.km(week.plannedKm))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(W.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.track)
                    Capsule().fill(W.accent).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
    }
}

private struct UpcomingList: View {
    let days: [WidgetSnapshot.Day]
    let date: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallLabel(text: "Hierna").padding(.bottom, 6)
            if days.isEmpty {
                Text("Geen trainingen meer gepland.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(W.secondary)
            }
            ForEach(days.indices, id: \.self) { i in
                let d = days[i]
                HStack(spacing: 7) {
                    Text(WText.dayShort(d.date))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(W.secondary)
                        .frame(width: 22, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: d.color)).frame(width: 4, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(W.text)
                            .lineLimit(1)
                        Text(WText.km(d.km))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(W.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LockScreenToday: View {
    let state: TodayState
    let date: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch state.kind {
            case .training(let day):
                Text(day.done ? "Vandaag · gelopen" : "Vandaag · \(day.label.capitalized)")
                    .font(.system(size: 12, weight: .heavy))
                Text(day.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(WText.summary(day)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            case .rest:
                Text("Rustdag").font(.system(size: 12, weight: .heavy))
                if let next = state.next {
                    Text("\(WText.when(next.date, from: date, calendar: calendar)): \(next.title)")
                        .font(.system(size: 14, weight: .bold)).lineLimit(2)
                }
            case .notStarted(let start):
                Text("Plan start").font(.system(size: 12, weight: .heavy))
                Text(WText.when(start, from: date, calendar: calendar)).font(.system(size: 15, weight: .bold))
            case .sick:
                Text("Pauze").font(.system(size: 12, weight: .heavy))
                Text("Ziek gemeld").font(.system(size: 15, weight: .bold))
            case .finished:
                Text("Plan afgerond").font(.system(size: 15, weight: .bold))
            case .noData:
                Text("Open Runner").font(.system(size: 15, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }
}

// MARK: - Voorbeeld voor de widgetgalerij

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: Date())
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: today) ?? today }
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        return WidgetSnapshot(
            created: Date(),
            days: [
                .init(date: day(0), title: "5× 800 m", label: "INTERVAL", color: 0xFF6B3D, km: 7.0, minutes: 42,
                      done: false, extra: false),
                .init(date: day(2), title: "Rustige loop", label: "RUSTIG", color: 0x4CC38A, km: 5.0, minutes: 31,
                      done: false, extra: false),
                .init(date: day(4), title: "Lange loop", label: "LANG", color: 0x5B8CFF, km: 9.0, minutes: 57,
                      done: false, extra: false)
            ],
            weeks: [.init(start: monday, plannedKm: 21, doneKm: 9.5)],
            sick: false, planStart: nil, planEnd: nil)
    }
}
