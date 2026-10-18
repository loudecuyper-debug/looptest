import SwiftUI
import LoopCore

enum CalendarMode: String {
    case list, month
}

struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var notice: String?
    @AppStorage("calendarMode") private var modeRaw = CalendarMode.list.rawValue

    private var mode: Binding<CalendarMode> {
        Binding(get: { CalendarMode(rawValue: modeRaw) ?? .list }, set: { modeRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Segmented(options: [(CalendarMode.list, "Lijst"), (CalendarMode.month, "Maand")],
                          selection: mode, height: 32)
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                if mode.wrappedValue == .month {
                    MonthCalendar(onMove: move)
                } else {
                    listView
                }
            }
            .screenTitle("Kalender")
            .navigationDestination(for: PlanDay.self) { WorkoutDetailView(day: $0) }
            .alert("Let op", isPresented: Binding(present: $notice)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
        }
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let plan = model.plan {
                    LazyVStack(spacing: 14) {
                        ForEach(plan.weeks, id: \.number) { week in
                            weekSection(week, isCurrent: currentWeek == week.number - 1)
                                .id(week.number)
                        }
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.margin)
                    .padding(.vertical, 8)
                }
            }
            .onAppear {
                if let w = currentWeek { proxy.scrollTo(w + 1, anchor: .top) }
            }
        }
    }

    private var currentWeek: Int? {
        if case .running(let d) = model.moment() { return d.week }
        return nil
    }

    private func weekSection(_ week: PlanWeek, isCurrent: Bool) -> some View {
        let km = week.estimatedDistance(zones: week.zones) / 1000
        let index = week.number - 1

        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Week \(week.number)")
                        .font(.system(size: 16, weight: .heavy))
                    Text(week.isRecoveryWeek ? "Rustweek" : week.phase.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    if isCurrent {
                        Text("Nu")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                    Spacer()
                    Text("\(Fmt.decimal(km)) km")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                }
                .padding(.bottom, 2)
                Text("\(DateText.short(week.startDate)) tot \(DateText.short(week.date(for: .sunday)))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.bottom, 8)

                ForEach(week.workouts, id: \.day) { w in
                    row(PlanDay(week: index, day: w.day), workout: w, week: week)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(isCurrent ? Theme.outline : Color.clear, lineWidth: 1))
    }

    private func row(_ day: PlanDay, workout: PlannedWorkout, week: PlanWeek) -> some View {
        let status = model.status(of: day)
        let date = week.date(for: day.day)
        let free = ExtraRun.freeDays(in: week)
        let canMove = (status == .today || status == .upcoming) && !free.isEmpty

        return NavigationLink(value: day) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(day.day.short.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.secondary)
                    Text(DateText.dayNumber(date))
                        .font(.system(size: 15, weight: .heavy))
                }
                .frame(width: 34)
                RoundedRectangle(cornerRadius: 3).fill(workout.type.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.isExtra ? "\(workout.title) (extra)" : workout.title)
                        .font(.system(size: 15, weight: .bold))
                    Text(TimeText.distance(workout.estimatedDistance(zones: week.zones)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                statusView(status)
            }
            .foregroundStyle(Theme.text)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canMove {
                Menu("Verplaatsen naar") {
                    ForEach(free, id: \.self) { d in
                        Button(d.name.capitalized) { move(day, to: d) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusView(_ status: WorkoutStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.good)
                .accessibilityLabel("Gelopen")
        case .missed:
            Text("Gemist")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        case .today:
            Text("Vandaag")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.text, in: Capsule())
        case .upcoming:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func move(_ day: PlanDay, to target: Weekday) {
        switch model.move(day, to: target) {
        case .moved(let warning)?:
            notice = warning
        case .dayTaken?:
            notice = "Op die dag staat al een training."
        case .alreadyDone?:
            notice = "Deze training is al gelopen."
        case .nothingToMove?, nil:
            break
        }
    }
}
