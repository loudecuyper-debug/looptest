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
                        running(plan: plan, today: today)
                    case .notStarted(let start):
                        notStarted(plan: plan, start: start)
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

    // MARK: - Plan loopt

    private func running(plan: TrainingPlan, today: PlanDay) -> some View {
        let day = (selected?.week == today.week) ? (selected ?? today) : today
        let week = plan.weeks[day.week]
        let workout = week.workout(on: day.day)
        let status = model.status(of: day)

        return ScrollView {
            VStack(spacing: 0) {
                WeekHeader(plan: plan, week: week, today: today, selected: day) { selected = $0 }
                VStack(spacing: 14) {
                    if model.isSick { sickCard }
                    ForEach(model.messages) { CoachMessageCard(message: $0) }

                    if let workout, let date = model.date(for: day) {
                        NavigationLink(value: day) {
                            WorkoutCard(workout: workout, week: week, date: date, status: status, run: model.run(for: day))
                        }
                        .buttonStyle(.plain)
                    } else {
                        restCard(after: day)
                    }

                    weekCard(week)

                    HStack(spacing: 10) {
                        Button("+ Extra loop") { showExtra = true }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Niet 100%") { showNotFeeling = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .disabled(model.isSick)

                    if model.backupReminder { backupCard }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if workout != nil, day == today, status == .today, !model.isSick {
                Button {
                    showStartInfo = true
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showExtra) {
            ExtraRunSheet(week: plan.weeks[today.week], today: today)
        }
        .sheet(isPresented: $showNotFeeling) {
            NotFeelingSheet()
        }
    }

    private var sickCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Niet 100%")
                Text("Je trainingen staan op pauze")
                    .font(.system(size: 22, weight: .heavy))
                Text("Geef aan wanneer je hersteld bent. Daarna volgen eerst 3 rustige dagen.")
                    .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 26, weight: .heavy))
                if let next = model.nextWorkout(after: day), let date = model.date(for: next.day),
                   let week = model.week(next.day) {
                    Text("Volgende: \(DateText.short(date)) · \(next.workout.title) · \(TimeText.distance(next.workout.estimatedDistance(zones: week.zones)))")
                        .font(.system(size: 15, weight: .semibold))
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
                        Text("Week \(week.number) overzicht").font(.system(size: 18, weight: .bold))
                        if week.isRecoveryWeek {
                            Text("Rustweek")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.sunken, in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    }
                    HStack(spacing: 8) {
                        Bar(fraction: runFraction)
                        Bar(fraction: progress.fraction)
                    }
                    HStack {
                        Text("Loopjes: ").foregroundColor(Theme.secondary) + Text("\(done)/\(planned.count)")
                        Spacer()
                        Text("Afstand: ").foregroundColor(Theme.secondary) + Text(progress.text)
                    }
                    .font(.system(size: 14, weight: .semibold))
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
                        Text("Tijd voor een backup").font(.system(size: 16, weight: .heavy))
                        Text("Je laatste backup is meer dan 3 weken oud.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voor de start en na het plan

    private func notStarted(plan: TrainingPlan, start: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(PlanTexts.goalTitle(plan.input))
                    Text("Je plan start \(DateText.long(start))")
                        .font(.system(size: 30, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)
                if let first = plan.weeks.first {
                    ForEach(first.workouts, id: \.day) { w in
                        let day = PlanDay(week: 0, day: w.day)
                        NavigationLink(value: day) {
                            WorkoutCard(workout: w, week: first, date: first.date(for: w.day),
                                        status: .upcoming, run: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Plan afgerond")
            Text("Je plan zit erop")
                .font(.system(size: 30, weight: .heavy))
            Text("Bekijk je resultaten in Voortgang of maak een nieuw plan via Plan › Plan beheren.")
                .font(.system(size: 16, weight: .semibold))
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
    let today: PlanDay
    let selected: PlanDay
    let onSelect: (PlanDay) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ProgressRing(fraction: Double(week.number) / Double(plan.weeks.count))
                    .frame(width: 26, height: 26)
                Text("Week \(week.number)/\(plan.weeks.count)")
                    .font(.system(size: 20, weight: .heavy))
                Text(week.isRecoveryWeek ? "rustweek" : week.phase.name.lowercased())
                    .font(.system(size: 15, weight: .semibold))
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
        let isSelected = day == selected
        let workout = week.workout(on: day.day)
        let done = model.run(for: day) != nil
        let date = week.date(for: day.day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 6) {
                Text(day.day.short.uppercased())
                    .font(.system(size: 12, weight: isToday ? .heavy : .bold))
                    .foregroundStyle(isToday ? Theme.text : Theme.secondary)
                Text(DateText.dayNumber(date))
                    .font(.system(size: 18, weight: isToday ? .heavy : .bold))
                    .foregroundStyle(isToday ? Theme.background : (day < today ? Theme.secondary : Theme.text))
                    .frame(width: 36, height: 36)
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
                .frame(width: 8, height: 8)
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
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Melding sluiten")
                    }
                }
                Text(message.event.message)
                    .font(.system(size: 15, weight: .semibold))
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
