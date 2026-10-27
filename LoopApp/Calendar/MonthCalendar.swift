import SwiftUI
import LoopCore

/// Kalender als maandoverzicht: één tegel per dag, trainingsdagen met een streepje in de typekleur.
/// Tik op een dag met een training om ze onder het rooster te zien; lang drukken om te verplaatsen.
struct MonthCalendar: View {
    @EnvironmentObject var model: AppModel
    let onMove: (PlanDay, Weekday) -> Void

    @State private var month: Date?
    @State private var selected: PlanDay?

    private var calendar: Calendar { model.calendar }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        ScrollView {
            if let plan = model.plan {
                let shown = month ?? initialMonth(plan)
                VStack(alignment: .leading, spacing: 12) {
                    header(shown, plan: plan)
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(["M", "D", "W", "D", "V", "Z", "Z"].indices, id: \.self) { i in
                            Text(["M", "D", "W", "D", "V", "Z", "Z"][i])
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.tertiary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                        ForEach(0..<leadingBlanks(shown), id: \.self) { _ in
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                        ForEach(days(in: shown), id: \.self) { date in
                            tile(date)
                        }
                    }
                    legend(plan)
                    selectedCard(in: shown)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Kop

    private func header(_ shown: Date, plan: TrainingPlan) -> some View {
        let range = monthRange(plan)
        let canBack = shown > range.lowerBound
        let canForward = shown < range.upperBound

        return HStack(spacing: 8) {
            navButton("chevron.left", label: "Vorige maand", enabled: canBack) { step(-1, plan: plan) }
            Spacer()
            Text(DateText.monthYear(shown))
                .font(.system(size: 17, weight: .heavy))
            Spacer()
            Text("\(Fmt.decimal(plannedKm(in: shown))) km")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.sunken, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .accessibilityLabel("\(Fmt.decimal(plannedKm(in: shown))) kilometer gepland deze maand")
            navButton("chevron.right", label: "Volgende maand", enabled: canForward) { step(1, plan: plan) }
        }
    }

    private func navButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Theme.text : Theme.tertiary)
                .frame(width: 34, height: 34)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int, plan: TrainingPlan) {
        let current = month ?? initialMonth(plan)
        guard let next = calendar.date(byAdding: .month, value: delta, to: current) else { return }
        let range = monthRange(plan)
        guard next >= range.lowerBound, next <= range.upperBound else { return }
        month = next
        selected = nil
    }

    // MARK: - Tegels

    private func tile(_ date: Date) -> some View {
        let day = model.planDay(for: date)
        let workout = day.flatMap { model.workout(at: $0) }
        let status = day.map { model.status(of: $0) }
        let isToday = calendar.isDateInToday(date)
        let isSelected = day != nil && day == currentSelection(in: startOfMonth(date))

        let background: Color = {
            if isSelected { return Theme.text }
            if workout != nil { return Color(hex: 0x2A303A) }
            if day != nil { return Theme.panel }
            return Theme.sunken
        }()
        let numberColor: Color = {
            if isSelected { return Theme.background }
            if workout != nil || isToday { return Theme.text }
            if day != nil { return Theme.secondary }
            return Theme.tertiary
        }()

        return Button {
            if let day, workout != nil { selected = day }
        } label: {
            VStack(spacing: 4) {
                Text(DateText.dayNumber(date))
                    .font(.system(size: 13, weight: workout != nil || isToday ? .heavy : .bold))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                ZStack {
                    if let workout {
                        if status == .done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(isSelected ? Theme.background : workout.type.color)
                        } else {
                            Capsule()
                                .fill(workout.type.color.opacity(status == .missed ? 0.4 : 1))
                                .frame(width: 16, height: 4)
                        }
                    }
                }
                .frame(height: 9)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(background, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isToday && !isSelected ? Theme.text : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let day, workout != nil {
                let free = model.moveTargets(for: day)
                if !free.isEmpty {
                    Menu("Verplaatsen naar") {
                        ForEach(free, id: \.self) { d in
                            Button(d.name.capitalized) { onMove(day, d) }
                        }
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityText(date: date, workout: workout, status: status, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityText(date: Date, workout: PlannedWorkout?, status: WorkoutStatus?, isToday: Bool) -> String {
        var parts = [DateText.long(date)]
        if isToday { parts.append("vandaag") }
        if let workout {
            parts.append(workout.title)
            if status == .done { parts.append("gelopen") }
            if status == .missed { parts.append("gemist") }
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Legende en gekozen dag

    private func legend(_ plan: TrainingPlan) -> some View {
        let used = Set(plan.weeks.flatMap { $0.workouts.map(\.type) })
        let order: [WorkoutType] = [.easy, .long, .tempo, .interval, .fartlek, .progression, .test]
        let names: [WorkoutType: String] = [.easy: "Rustig", .long: "Lang", .tempo: "Tempo", .interval: "Interval",
                                            .fartlek: "Fartlek", .progression: "Progressie", .test: "Tijdrit"]
        return FlowRow(spacing: 12) {
            ForEach(order.filter(used.contains), id: \.self) { t in
                HStack(spacing: 5) {
                    Capsule().fill(t.color).frame(width: 12, height: 4)
                    Text(names[t] ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func selectedCard(in shown: Date) -> some View {
        if let day = currentSelection(in: shown), let week = model.week(day),
           let workout = week.workout(on: day.day), let date = model.date(for: day) {
            NavigationLink(value: day) {
                WorkoutCard(workout: workout, week: week, date: date, status: model.status(of: day),
                            run: model.run(for: day))
            }
            .buttonStyle(.plain)
        } else {
            Text("Geen trainingen in deze maand.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        }
    }

    /// De gekozen dag, of anders de eerstvolgende training in deze maand (of de eerste als alles voorbij is).
    private func currentSelection(in shown: Date) -> PlanDay? {
        if let selected, let date = model.date(for: selected), startOfMonth(date) == shown { return selected }
        let workoutDays = days(in: shown).compactMap { date -> (Date, PlanDay)? in
            guard let d = model.planDay(for: date), model.workout(at: d) != nil else { return nil }
            return (date, d)
        }
        let today = calendar.startOfDay(for: Date())
        return (workoutDays.first { $0.0 >= today } ?? workoutDays.first)?.1
    }

    // MARK: - Datums

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func days(in month: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// Lege vakjes voor de eerste dag: maandag = 0.
    private func leadingBlanks(_ month: Date) -> Int {
        let weekday = calendar.component(.weekday, from: month)   // zondag = 1
        return (weekday + 5) % 7
    }

    private func initialMonth(_ plan: TrainingPlan) -> Date {
        guard let moment = model.moment() else { return startOfMonth(Date()) }
        switch moment {
        case .running:
            return startOfMonth(Date())
        case .notStarted(let start):
            return startOfMonth(start)
        case .finished:
            return startOfMonth(plan.weeks.last?.startDate ?? Date())
        }
    }

    private func monthRange(_ plan: TrainingPlan) -> ClosedRange<Date> {
        let first = startOfMonth(plan.weeks.first?.startDate ?? Date())
        let last = startOfMonth(plan.weeks.last.map { $0.date(for: .sunday, calendar: calendar) } ?? Date())
        let now = startOfMonth(Date())
        return min(first, now)...max(last, first)
    }

    private func plannedKm(in month: Date) -> Double {
        days(in: month).reduce(0.0) { sum, date in
            guard let d = model.planDay(for: date), let week = model.week(d),
                  let w = week.workout(on: d.day) else { return sum }
            return sum + w.estimatedDistance(zones: week.zones) / 1000
        }
    }
}

/// Eenvoudige rij die naar een volgende regel springt als het niet past (voor de legende).
struct FlowRow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
