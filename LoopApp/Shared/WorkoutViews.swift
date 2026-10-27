import SwiftUI
import LoopCore

/// Workout van een dag op Vandaag en in de kalender.
struct WorkoutCard: View {
    let workout: PlannedWorkout
    let week: PlanWeek
    let date: Date
    let status: WorkoutStatus
    let run: RunSummary?
    /// Optioneel extra label naast het type, bv. "Vandaag" of "Eerste training".
    var label: String? = nil

    var body: some View {
        let zones = week.zones
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            TypeTag(type: workout.type, extra: workout.isExtra)
                            if let label {
                                Text("· \(label.uppercased())")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Text(workout.title)
                            .font(.system(size: 21, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("\(TimeText.distance(workout.estimatedDistance(zones: zones))) · \(Fmt.minutes(workout.estimatedDuration(zones: zones))) · \(DateText.short(date))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 4)
                }
                Text(WorkoutText.describe(workout, zones: zones))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                statusLine
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toont de details van de workout")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .done:
            if let run {
                Label("Gelopen: \(Fmt.km2(run.distance)) in \(TimeText.clock(run.duration))", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.good)
            }
        case .missed:
            Label("Niet gelopen", systemImage: "minus.circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        case .today, .upcoming:
            EmptyView()
        }
    }
}

/// Details van een geplande workout: alle stappen met tempo's.
struct WorkoutDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: PlanDay
    @State private var notice: String?
    @State private var runRequest: RunRequest?

    var body: some View {
        Group {
            if let week = model.week(day), let workout = week.workout(on: day.day) {
                content(week: week, workout: workout)
            } else {
                Text("Deze workout staat niet meer in je plan.")
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenTitle("Workout")
        .alert("Let op", isPresented: Binding(present: $notice)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
        .fullScreenCover(item: $runRequest) { request in
            RunScreen(request: request).environmentObject(model)
        }
    }

    private func content(week: PlanWeek, workout: PlannedWorkout) -> some View {
        let zones = week.zones
        let status = model.status(of: day)
        let date = model.date(for: day) ?? Date()
        let free = model.moveTargets(for: day)
        let canMove = status == .today || status == .upcoming

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    TypeTag(type: workout.type, extra: workout.isExtra)
                    Text(workout.title)
                        .font(.system(size: 24, weight: .heavy))
                    Text("\(DateText.long(date)) · week \(week.number)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }

                Card {
                    HStack {
                        StatBlock(label: "Afstand", value: TimeText.distance(workout.estimatedDistance(zones: zones)))
                        StatBlock(label: "Duur", value: Fmt.minutes(workout.estimatedDuration(zones: zones)))
                        StatBlock(label: "Status", value: statusText(status), size: 15)
                    }
                }

                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Opbouw").padding(.bottom, 8)
                        ForEach(Array(workout.blocks.enumerated()), id: \.offset) { _, block in
                            if block.repeats > 1 {
                                Text("\(block.repeats)× herhalen")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(workout.type.color)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            }
                            ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                                StepRow(step: step, zones: zones, workColor: workout.type.color,
                                        indented: block.repeats > 1)
                            }
                        }
                    }
                }

                // Lopen kan enkel op de dag zelf, zodat de loop bij de juiste dag in het plan hoort.
                if canMove, status == .today, model.run(for: day) == nil {
                    Button {
                        runRequest = RunRequest(workout: workout, day: day, zones: zones)
                    } label: {
                        Label("Start workout", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 52))
                }

                if !free.isEmpty {
                    Menu {
                        ForEach(free, id: \.self) { d in
                            Button(d.name.capitalized) { move(to: d) }
                        }
                    } label: {
                        Label("Verplaatsen naar andere dag", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.sunken, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 1))
                    }
                }

                if workout.isExtra, model.run(for: day) == nil {
                    Button(role: .destructive) {
                        model.removeExtraRun(on: day)
                        dismiss()
                    } label: {
                        Text("Extra loop verwijderen")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
    }

    private func statusText(_ s: WorkoutStatus) -> String {
        switch s {
        case .done: return "Gelopen"
        case .missed: return "Gemist"
        case .today: return "Vandaag"
        case .upcoming: return "Gepland"
        }
    }

    private func move(to target: Weekday) {
        switch model.move(day, to: target) {
        case .moved(let warning)?:
            notice = warning
            if warning == nil { dismiss() }
        case .dayTaken?:
            notice = "Op die dag staat al een training."
        case .alreadyDone?:
            notice = "Deze training is al gelopen."
        case .dayPassed?:
            notice = "Die dag is al voorbij."
        case .nothingToMove?, nil:
            break
        }
    }
}

/// Eén stap van een workout: soort, lengte en doeltempo.
struct StepRow: View {
    let step: WorkoutStep
    let zones: PaceZones
    let workColor: Color
    var indented = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(dotColor)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindName).font(.system(size: 15, weight: .bold))
                Text(lengthText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(paceText)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.leading, indented ? 12 : 0)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch step.kind {
        case .work: return workColor
        case .recovery: return Theme.outline
        default: return Theme.good
        }
    }

    private var kindName: String {
        switch step.kind {
        case .warmup: return "Inlopen"
        case .cooldown: return "Uitlopen"
        case .recovery: return "Herstel"
        case .work: return "Snel · \(WorkoutText.targetLabel(step.target))"
        case .steady:
            if case .zone(let z) = step.target { return z.name }
            return WorkoutText.targetLabel(step.target).capitalized
        }
    }

    private var lengthText: String {
        switch step.length {
        case .distance(let m): return TimeText.distance(m)
        case .time(let s): return WorkoutText.duration(s)
        }
    }

    private var paceText: String {
        switch step.target {
        case .zone(let z): return TimeText.range(zones.range(for: z))
        case .racePace(let d): return TimeText.pace(zones.racePace(distance: d))
        }
    }
}
