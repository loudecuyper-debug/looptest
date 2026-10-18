import SwiftUI
import LoopCore

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    var openTab: (AppTab) -> Void = { _ in }

    @State private var selected: PlanDay?
    @State private var showExtra = false
    @State private var showNotFeeling = false
    @State private var showStartInfo = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.plan, let moment = model.moment() {
                    switch moment {
                    case .running(let today):
                        dayScreen(plan: plan, today: today, startDate: nil)
                    case .notStarted(let start):
                        dayScreen(plan: plan, today: nil, startDate: start)
                    case .finished:
                        finished
                    }
                } else {
                    Text("Geen plan gevonden.").foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PlanDay.self) { WorkoutDetailView(day: $0) }
        }
        .alert("Lopen volgt in de volgende stap", isPresented: $showStartInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Lopen met GPS en stem bouwen we hierna. Tot dan kan je een loop achteraf toevoegen via Voortgang.")
        }
    }

    // MARK: - Plan loopt of start binnenkort

    /// `today` is nil zolang het plan nog niet begonnen is; dan toont Vandaag week 1.
    private func dayScreen(plan: TrainingPlan, today: PlanDay?, startDate: Date?) -> some View {
        let first = plan.weeks[0].workouts.first.map { PlanDay(week: 0, day: $0.day) } ?? PlanDay(week: 0, day: .monday)
        let anchor = today ?? first
        let day = (selected?.week == anchor.week) ? (selected ?? anchor) : anchor
        let week = plan.weeks[day.week]
        let workout = week.workout(on: day.day)
        let status = model.status(of: day)
        let startable = today != nil && workout != nil && day == today && status == .today && !model.isSick

        return ScrollView {
            VStack(spacing: 0) {
                WeekHeader(plan: plan, week: week, today: today, selected: day) { selected = $0 }
                VStack(spacing: 12) {
                    if let startDate { startBanner(startDate, plan: plan) }
                    if model.isSick { sickCard }
                    ForEach(model.messages) { CoachMessageCard(message: $0) }

                    if let workout, let date = model.date(for: day) {
                        NavigationLink(value: day) {
                            WorkoutCard(workout: workout, week: week, date: date, status: status,
                                        run: model.run(for: day), label: cardLabel(day: day, today: today, first: first))
                        }
                        .buttonStyle(.plain)
                    } else {
                        restCard(after: day)
                    }

                    weekCard(week)

                    if today != nil {
                        HStack(spacing: 10) {
                            Button("+ Extra loop") { showExtra = true }
                                .buttonStyle(SecondaryButtonStyle(height: 44))
                            Button("Niet 100%") { showNotFeeling = true }
                                .buttonStyle(SecondaryButtonStyle(height: 44))
                        }
                        .disabled(model.isSick)
                    }

                    if model.backupReminder { backupCard }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.isSick {
                Button {
                    showStartInfo = true
                } label: {
                    Label(startable ? "Start \(workout?.title.lowercased() ?? "workout")" : "Vrij lopen",
                          systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showExtra) {
            if let today { ExtraRunSheet(week: plan.weeks[today.week], today: today) }
        }
        .sheet(isPresented: $showNotFeeling) {
            NotFeelingSheet()
        }
    }

    /// Klein label boven de workoutkaart: wanneer het is, of dat het de eerste training is.
    private func cardLabel(day: PlanDay, today: PlanDay?, first: PlanDay) -> String? {
        if let today {
            if day == today { return "Vandaag" }
            if day.index == today.index + 1 { return "Morgen" }
            return nil
        }
        return day == first ? "Eerste training" : nil
    }

    private func startBanner(_ start: Date, plan: TrainingPlan) -> some View {
        let days = model.calendar.dateComponents([.day], from: model.calendar.startOfDay(for: Date()), to: start).day ?? 0
        let when: String
        switch days {
        case ...1: when = "morgen"
        case 2...6: when = "over \(days) dagen"
        default: when = DateText.long(start)
        }
        return Card(padding: 16) {
            HStack(spacing: 12) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Je plan start \(when)")
                        .font(.system(size: 15, weight: .heavy))
                    Text("\(DateText.longCapitalized(start)) · \(PlanTexts.goalTitle(plan.input)) · \(plan.weeks.count) weken")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.text)
        }
    }

    private var sickCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Niet 100%")
                Text("Je trainingen staan op pauze")
                    .font(.system(size: 19, weight: .heavy))
                Text("Geef aan wanneer je hersteld bent. Daarna volgen eerst 3 rustige dagen.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ik ben hersteld") { model.recovered() }
                    .buttonStyle(PrimaryButtonStyle(height: 48))
            }
        }
    }

    private func restCard(after day: PlanDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Rustdag")
                Text("Geen training gepland")
                    .font(.system(size: 20, weight: .heavy))
                if let next = model.nextWorkout(after: day), let date = model.date(for: next.day),
                   let week = model.week(next.day) {
                    Text("Volgende: \(DateText.short(date)) · \(next.workout.title) · \(TimeText.distance(next.workout.estimatedDistance(zones: week.zones)))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func weekCard(_ week: PlanWeek) -> some View {
        let progress = model.progress(of: week)
        let planned = week.workouts.filter { !$0.isExtra }
        let done = planned.filter { model.run(for: PlanDay(week: week.number - 1, day: $0.day)) != nil }.count
        let runFraction = planned.isEmpty ? 0 : Double(done) / Double(planned.count)

        return Button {
            openTab(.calendar)
        } label: {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Week \(week.number) overzicht").font(.system(size: 16, weight: .bold))
                        if week.isRecoveryWeek {
                            Text("Rustweek")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.sunken, in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    HStack(spacing: 8) {
                        Bar(fraction: runFraction)
                        Bar(fraction: progress.fraction)
                    }
                    HStack {
                        Text("Trainingen: ").foregroundColor(Theme.secondary) + Text("\(done)/\(planned.count)")
                        Spacer()
                        Text("Afstand: ").foregroundColor(Theme.secondary) + Text(progress.text)
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
    }

    private var backupCard: some View {
        Button {
            openTab(.settings)
        } label: {
            Card(padding: 16) {
                HStack(spacing: 12) {
                    Circle().fill(Theme.accent).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tijd voor een backup").font(.system(size: 15, weight: .heavy))
                        Text("Je laatste backup is meer dan 3 weken oud.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Na het plan

    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Plan afgerond")
            Text("Je plan zit erop")
                .font(.system(size: 24, weight: .heavy))
            Text("Bekijk je resultaten in Voortgang of maak een nieuw plan via Plan › Plan beheren.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Button("Naar Plan") { openTab(.plan) }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
        .foregroundStyle(Theme.text)
        .padding(Theme.margin)
    }
}

// MARK: - Weekstrook bovenaan

struct WeekHeader: View {
    @EnvironmentObject var model: AppModel
    let plan: TrainingPlan
    let week: PlanWeek
    /// Nil zolang het plan nog niet begonnen is.
    let today: PlanDay?
    let selected: PlanDay
    let onSelect: (PlanDay) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressRing(fraction: Double(week.number) / Double(plan.weeks.count))
                    .frame(width: 20, height: 20)
                Text("Week \(week.number)/\(plan.weeks.count)")
                    .font(.system(size: 17, weight: .heavy))
                Text(week.isRecoveryWeek ? "rustweek" : week.phase.name.lowercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                ForEach(Weekday.allCases, id: \.self) { d in
                    dayCell(PlanDay(week: week.number - 1, day: d))
                }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24), style: .continuous)
                .fill(Theme.panel)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func dayCell(_ day: PlanDay) -> some View {
        let isToday = day == today
        let isPast = today.map { day < $0 } ?? false
        let isSelected = day == selected
        let workout = week.workout(on: day.day)
        let done = model.run(for: day) != nil
        let date = week.date(for: day.day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 6) {
                Text(day.day.short.uppercased())
                    .font(.system(size: 11, weight: isToday ? .heavy : .bold))
                    .foregroundStyle(isToday ? Theme.text : Theme.secondary)
                Text(DateText.dayNumber(date))
                    .font(.system(size: 16, weight: isToday ? .heavy : .bold))
                    .foregroundStyle(isToday ? Theme.background : (isPast ? Theme.secondary : Theme.text))
                    .frame(width: 32, height: 32)
                    .background(isToday ? Theme.text : Color.clear, in: Circle())
                    .overlay(Circle().strokeBorder(isSelected && !isToday ? Theme.outline : Color.clear, lineWidth: 2))
                Group {
                    if let workout {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(workout.type.color)
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(workout.type.color)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 7, height: 7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(day: day, date: date, workout: workout, done: done))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityText(day: PlanDay, date: Date, workout: PlannedWorkout?, done: Bool) -> String {
        var parts = [DateText.long(date)]
        if let workout { parts.append(workout.title + (done ? ", gelopen" : "")) } else { parts.append("rustdag") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Melding van de coach

struct CoachMessageCard: View {
    @EnvironmentObject var model: AppModel
    let message: CoachMessage

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                    SectionLabel("Je coach", color: Theme.muted)
                    Spacer()
                    if message.suggestion == nil {
                        Button {
                            model.dismiss(message.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Melding sluiten")
                    }
                }
                Text(message.event.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = message.suggestion {
                    HStack(spacing: 8) {
                        Button("Ja, aanpassen") { model.accept(s, message: message.id) }
                            .buttonStyle(PrimaryButtonStyle(height: 46))
                        Button("Nee") { model.dismiss(message.id) }
                            .buttonStyle(SecondaryButtonStyle(height: 46))
                            .frame(width: 110)
                    }
                }
            }
        }
    }
}
