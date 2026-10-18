import Foundation
import SwiftUI
import LoopCore

/// Een melding van de coach die op Vandaag getoond wordt.
struct CoachMessage: Identifiable {
    let id = UUID()
    let event: CoachEvent

    /// Het voorstel om tempo's aan te passen, als dit er een is.
    var suggestion: LevelSuggestion? {
        if case .levelSuggestion(let s) = event { return s }
        return nil
    }
}

/// Waar je vandaag staat in het plan.
enum PlanMoment: Equatable {
    case notStarted(Date)
    case running(PlanDay)
    case finished
}

enum WorkoutStatus {
    case done, missed, today, upcoming
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

/// Houdt het plan, de coach en de gelopen loopjes bij en bewaart alles lokaal.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var coach: Coach?
    @Published private(set) var plan: TrainingPlan?
    @Published private(set) var runs: [RunSummary] = []
    @Published private(set) var records: [PersonalRecord] = []
    @Published private(set) var plannedRoutes: [PlannedRoute] = []
    @Published var messages: [CoachMessage] = []
    @Published var errorText: String?

    let calendar = PlanCalendar.default
    private let store: RunStore?

    init() {
        let opened = try? RunStore.appDefault()
        store = opened
        if opened == nil {
            errorText = "De opslagmap kon niet geopend worden. Je gegevens worden niet bewaard."
        }
        do {
            coach = try opened?.loadCoach()
            runs = try opened?.summaries() ?? []
            plannedRoutes = try opened?.plannedRoutes() ?? []
        } catch {
            errorText = "Je gegevens konden niet gelezen worden: \(error.localizedDescription)"
        }
        refreshPlan()
        refreshRecords()
    }

    // MARK: - Plan

    func createPlan(_ input: PlanInput) {
        coach = Coach(input: input)
        messages = []
        save()
        refreshPlan()
    }

    /// Waar je op `date` staat in het plan.
    func moment(at date: Date = Date()) -> PlanMoment? {
        guard let plan, let first = plan.weeks.first else { return nil }
        let start = calendar.startOfDay(for: first.startDate)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        if days < 0 { return .notStarted(start) }
        if days >= plan.weeks.count * 7 { return .finished }
        return .running(PlanDay(index: days))
    }

    /// Dag in het plan voor een datum, nil buiten het plan.
    func planDay(for date: Date) -> PlanDay? {
        if case .running(let d) = moment(at: date) { return d }
        return nil
    }

    var today: PlanDay? { planDay(for: Date()) }

    func week(_ day: PlanDay) -> PlanWeek? {
        guard let plan, day.week >= 0, day.week < plan.weeks.count else { return nil }
        return plan.weeks[day.week]
    }

    func workout(at day: PlanDay) -> PlannedWorkout? {
        week(day)?.workout(on: day.day)
    }

    func date(for day: PlanDay) -> Date? {
        week(day)?.date(for: day.day, calendar: calendar)
    }

    /// Eerstvolgende workout na een dag.
    func nextWorkout(after day: PlanDay) -> (day: PlanDay, workout: PlannedWorkout)? {
        guard let plan else { return nil }
        let last = plan.weeks.count * 7
        var i = day.index + 1
        while i < last {
            let d = PlanDay(index: i)
            if let w = workout(at: d) { return (d, w) }
            i += 1
        }
        return nil
    }

    /// Gelopen loop voor een dag in het plan (enkel als de datum ook in die week valt).
    func run(for day: PlanDay) -> RunSummary? {
        guard let week = week(day) else { return nil }
        let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
        return runs.first { $0.planDay == day && $0.date >= week.startDate && $0.date < end }
    }

    func status(of day: PlanDay) -> WorkoutStatus {
        if run(for: day) != nil { return .done }
        switch moment() {
        case .running(let today):
            if day == today { return .today }
            return day < today ? .missed : .upcoming
        case .finished:
            return .missed
        default:
            return .upcoming
        }
    }

    func progress(of week: PlanWeek) -> WeekProgress {
        Stats.progress(of: week, runs: runs, calendar: calendar)
    }

    /// Niveau (VDOT) dat nu geldt.
    var currentVdot: Double? {
        guard let plan else { return nil }
        switch moment() {
        case .running(let d): return plan.weeks[d.week].vdot
        case .finished: return plan.weeks.last?.vdot
        default: return plan.weeks.first?.vdot
        }
    }

    var isSick: Bool { coach?.state.isSick ?? false }

    // MARK: - Coach

    func addExtraRun(on day: PlanDay) {
        mutateCoach { $0.addExtraRun(day) }
    }

    func removeExtraRun(on day: PlanDay) {
        mutateCoach { $0.removeExtraRun(day) }
    }

    func move(_ day: PlanDay, to target: Weekday) -> Coach.MoveOutcome? {
        mutateCoach { $0.moveWorkout(at: day, to: target) }
    }

    func notFeeling(_ reason: NotFeelingReason) {
        guard let today else { return }
        let events = mutateCoach { $0.notFeeling(reason, at: today) } ?? []
        push(events)
    }

    func recovered() {
        guard let today else { return }
        let events = mutateCoach { $0.recovered(at: today) } ?? []
        push(events)
    }

    func accept(_ suggestion: LevelSuggestion, message id: UUID) {
        mutateCoach { $0.accept(suggestion) }
        dismiss(id)
    }

    func dismiss(_ id: UUID) {
        messages.removeAll { $0.id == id }
    }

    private func push(_ events: [CoachEvent]) {
        messages.append(contentsOf: events.map { CoachMessage(event: $0) })
    }

    @discardableResult
    private func mutateCoach<T>(_ change: (inout Coach) -> T) -> T? {
        guard var c = coach else { return nil }
        let result = change(&c)
        coach = c
        save()
        refreshPlan()
        return result
    }

    private func save() {
        guard let coach, let store else { return }
        do {
            try store.save(coach)
        } catch {
            errorText = "Opslaan mislukt: \(error.localizedDescription)"
        }
    }

    private func refreshPlan() {
        plan = coach?.plan(calendar: calendar)
    }

    // MARK: - Loopjes

    /// Workout die op een datum gepland staat en nog niet gelopen is.
    func openWorkout(on date: Date) -> (day: PlanDay, workout: PlannedWorkout)? {
        guard let d = planDay(for: date), let w = workout(at: d), run(for: d) == nil else { return nil }
        return (d, w)
    }

    func addManualRun(date: Date, distanceKm: Double, duration: TimeInterval, rpe: Int?,
                      pain: Bool, note: String?, linkToPlan: Bool) {
        guard let store else { return }
        let planned = linkToPlan ? openWorkout(on: date) : nil
        let run = CompletedRun.manual(date: date, planDay: planned?.day, workout: planned?.workout,
                                      distance: distanceKm * 1000, duration: duration,
                                      rpe: rpe, pain: pain, note: note)
        do {
            try store.save(run)
            runs = try store.summaries()
        } catch {
            errorText = "De loop kon niet bewaard worden: \(error.localizedDescription)"
            return
        }
        refreshRecords()
        if let result = run.coachResult {
            let events = mutateCoach { $0.record(result) } ?? []
            push(events)
        }
    }

    func deleteRun(id: UUID) {
        guard let store else { return }
        do {
            try store.deleteRun(id: id)
            runs = try store.summaries()
        } catch {
            errorText = "Verwijderen mislukt: \(error.localizedDescription)"
        }
        refreshRecords()
    }

    // MARK: - Routes

    /// Alle loopjes met een GPS-route, nieuwste eerst (leest de routes van schijf).
    func gpsRuns() -> [CompletedRun] {
        ((try? store?.allRuns()) ?? []).filter { $0.route.count > 1 }
    }

    func savePlannedRoute(_ route: PlannedRoute) {
        guard let store else { return }
        do {
            try store.save(route)
            plannedRoutes = try store.plannedRoutes()
        } catch {
            errorText = "De route kon niet bewaard worden: \(error.localizedDescription)"
        }
    }

    func deletePlannedRoute(id: UUID) {
        guard let store else { return }
        do {
            try store.deletePlannedRoute(id: id)
            plannedRoutes = try store.plannedRoutes()
        } catch {
            errorText = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }

    /// Rustig tempo (s/km) dat nu geldt, voor de geschatte duur van een route.
    var easyPace: Double? {
        currentVdot.map { PaceZones(vdot: $0).easy.target }
    }

    private func refreshRecords() {
        let all = (try? store?.allRuns()) ?? []
        records = Stats.personalRecords(all)
    }

    // MARK: - Backup

    var lastBackup: Date? { store?.lastBackupDate() }

    var backupReminder: Bool {
        (try? store?.shouldRemindBackup()) ?? false
    }

    func makeBackup() throws -> Data {
        guard let store else { throw AppError("De opslagmap is niet beschikbaar.") }
        let data = try store.makeBackup()
        objectWillChange.send()
        return data
    }

    func restore(_ data: Data) throws {
        guard let store else { throw AppError("De opslagmap is niet beschikbaar.") }
        try store.restore(from: data)
        coach = try store.loadCoach()
        runs = try store.summaries()
        plannedRoutes = try store.plannedRoutes()
        messages = []
        refreshPlan()
        refreshRecords()
    }
}
