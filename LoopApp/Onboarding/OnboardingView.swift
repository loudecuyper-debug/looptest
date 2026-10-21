import SwiftUI
import LoopCore

// Vragenreeks bij eerste gebruik (en bij "Nieuw plan maken"): één vraag per scherm,
// daarna een preview van het plan.

enum LevelMode: Hashable { case recent, cooper }
enum DurationMode: Hashable { case weeks, raceDate }

struct OnboardingAnswers {
    var goal: PlanGoal = .faster
    var goalDistance: Double = 10_000
    var levelMode: LevelMode = .recent
    var recentDistance: Double = 5_000
    var minutes = 25
    var seconds = 0
    var cooperMeters = 2_400
    var weeklyKm = 15
    var longestKm = 8
    var runDays: Set<Weekday> = [.tuesday, .thursday, .sunday]
    var longRunDay: Weekday = .sunday
    var durationMode: DurationMode = .weeks
    var weeks = 12
    var raceDate: Date = PlanCalendar.default.date(byAdding: .day, value: 7 * 11 + 6,
                                                    to: PlanCalendar.monday(of: Date())) ?? Date()

    var performanceDistance: Double {
        levelMode == .recent ? recentDistance : Double(cooperMeters)
    }

    var performanceTime: TimeInterval {
        levelMode == .recent ? TimeInterval(minutes * 60 + seconds) : 12 * 60
    }

    var vdot: Double? { Vdot.from(distance: performanceDistance, time: performanceTime) }

    /// Maandag van week 1: deze week, of volgende week als er deze week geen loopdag meer over is.
    var startMonday: Date { PlanCalendar.planStart(for: Date(), runDays: runDays.sorted()) }

    /// Datum van de eerste training.
    var firstTraining: Date {
        let from = PlanCalendar.firstPlanDay(for: Date(), runDays: runDays.sorted())
        let day = runDays.sorted().first(where: { $0 >= from }) ?? from
        return PlanCalendar.default.date(byAdding: .day, value: day.rawValue, to: startMonday) ?? startMonday
    }

    var planWeeks: Int {
        switch durationMode {
        case .weeks:
            return weeks
        case .raceDate:
            let cal = PlanCalendar.default
            let days = cal.dateComponents([.day], from: startMonday, to: cal.startOfDay(for: raceDate)).day ?? 0
            return min(max(days / 7 + 1, 6), 24)
        }
    }

    var input: PlanInput {
        PlanInput(goal: goal, goalDistance: goalDistance, weeks: planWeeks, startDate: Date(),
                  recentDistance: performanceDistance, recentTime: performanceTime,
                  weeklyVolumeKm: Double(weeklyKm), longestRunKm: Double(longestKm),
                  runDays: runDays.sorted(), longRunDay: longRunDay)
    }
}

enum OnboardingStep: Int, CaseIterable {
    case goal, level, volume, longest, days, longDay, duration, preview

    static let questionCount = 7
}

struct OnboardingView: View {
    var onCancel: (() -> Void)?
    let onFinish: (PlanInput) -> Void

    @State private var answers = OnboardingAnswers()
    @State private var step: OnboardingStep = .goal

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Kop en voet

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                if step != .goal {
                    roundButton("chevron.left", label: "Terug") { go(-1) }
                } else if let onCancel {
                    roundButton("xmark", label: "Annuleren", action: onCancel)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                SectionLabel(step == .preview ? "Je plan" : "Vraag \(step.rawValue + 1) van \(OnboardingStep.questionCount)")
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            Bar(fraction: Double(step.rawValue + 1) / Double(OnboardingStep.questionCount))
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if step == .preview {
                Button("Antwoorden aanpassen") { withAnimation { step = .goal } }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
            }
            Button(step == .preview ? "Plan starten" : "Verder") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Theme.panel, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Navigatie

    private var canContinue: Bool {
        switch step {
        case .level: return answers.vdot != nil
        case .days: return answers.runDays.count >= 2
        case .preview: return previewPlan != nil
        default: return true
        }
    }

    private func next() {
        if step == .days, !answers.runDays.contains(answers.longRunDay) {
            answers.longRunDay = answers.runDays.contains(.sunday) ? .sunday : (answers.runDays.max() ?? .sunday)
        }
        if step == .preview {
            onFinish(answers.input)
            return
        }
        go(1)
    }

    private func go(_ delta: Int) {
        guard let s = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = s }
    }

    // MARK: - Inhoud

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal: goalStep
        case .level: levelStep
        case .volume: volumeStep
        case .longest: longestStep
        case .days: daysStep
        case .longDay: longDayStep
        case .duration: durationStep
        case .preview: previewStep
        }
    }

    private func question(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 1. Doel

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            question("Wat wil je bereiken?", "Hierop stemmen we je sessies en je lange loop af.")
            VStack(spacing: 10) {
                ChoiceCard(icon: "stopwatch", title: "Sneller lopen", subtitle: "Een betere tijd op een vaste afstand",
                           selected: answers.goal == .faster) { answers.goal = .faster }
                ChoiceCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Verder lopen",
                           subtitle: "Langere afstanden aankunnen",
                           selected: answers.goal == .further) { answers.goal = .further }
                ChoiceCard(icon: "chart.line.uptrend.xyaxis", title: "Allebei", subtitle: "Verder en sneller, rustiger opgebouwd",
                           selected: answers.goal == .both) { answers.goal = .both }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Doelafstand")
                HStack(spacing: 8) {
                    distanceChip("5 km", 5_000)
                    distanceChip("10 km", 10_000)
                    distanceChip("Halve", 21_097.5)
                    distanceChip("Marathon", 42_195)
                }
            }
        }
    }

    private func distanceChip(_ title: String, _ meters: Double) -> some View {
        Chip(title: title, selected: answers.goalDistance == meters) { answers.goalDistance = meters }
    }

    // 2. Niveau

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("Hoe snel loop je nu?", "Hieruit berekenen we al je tempo's.")
            Segmented(options: [(LevelMode.recent, "Recente tijd"), (LevelMode.cooper, "Testloop")],
                      selection: $answers.levelMode)

            if answers.levelMode == .recent {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Afstand")
                    HStack(spacing: 8) {
                        recentChip("3 km", 3_000)
                        recentChip("5 km", 5_000)
                        recentChip("10 km", 10_000)
                        recentChip("Halve", 21_097.5)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Tijd")
                    HStack(spacing: 10) {
                        NumberBox(value: $answers.minutes, unit: "min", range: 0...400, label: "Minuten")
                        Text(":").font(.system(size: 30, weight: .black)).foregroundStyle(Theme.outline)
                        NumberBox(value: $answers.seconds, unit: "s", range: 0...59, label: "Seconden")
                    }
                }
                levelResult
                hint("Een tijd van de laatste 6 weken, voluit gelopen: een wedstrijd, parkrun of training.")
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        TypeTag(type: .test)
                        Text("12 minuten zo ver mogelijk")
                            .font(.system(size: 20, weight: .heavy))
                        Text("1,5 km inlopen, 12 minuten voluit en gelijkmatig, 1 km uitlopen. Noteer de afstand na 12 minuten.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Afstand na 12 minuten")
                    NumberBox(value: $answers.cooperMeters, unit: "meter", range: 0...5_000, label: "Meter")
                }
                levelResult
                hint("Nog geen testloop gedaan? Loop hem eerst met een sporthorloge of een andere app en vul daarna de afstand in.")
            }
        }
    }

    private func recentChip(_ title: String, _ meters: Double) -> some View {
        Chip(title: title, selected: answers.recentDistance == meters) { answers.recentDistance = meters }
    }

    @ViewBuilder
    private var levelResult: some View {
        if let v = answers.vdot {
            HStack {
                StatBlock(label: "Jouw niveau", value: Fmt.decimal(v), size: 24)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Voorspelde 10 km")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    Text(TimeText.clock(Vdot.predictedTime(distance: 10_000, vdot: v)))
                        .font(.system(size: 19, weight: .heavy))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        } else {
            Text("Deze combinatie van afstand en tijd lijkt niet te kloppen. Controleer je invoer.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 3. Weekvolume

    private var volumeStep: some View {
        let start = max(answers.weeklyKm, 5)
        let peak = Int(min(Double(start) * 1.6, Double(start) + 15).rounded())
        return VStack(alignment: .leading, spacing: 24) {
            question("Hoeveel loop je nu per week?", "Gemiddeld over de laatste 4 weken. Een schatting volstaat.")
            BigStepper(value: $answers.weeklyKm, range: 0...150, unit: "km per week")
            hint("Je plan start rond \(start) km per week en bouwt op tot ongeveer \(peak) km. Elke 4e week is een rustweek.")
        }
    }

    // 4. Langste loop

    private var longestStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            question("Wat was je langste loop?", "De langste loop van de laatste maand.")
            BigStepper(value: $answers.longestKm, range: 0...50, unit: "km")
            hint("Je eerste lange loop wordt hierop afgestemd en groeit daarna met ongeveer 1 km per week.")
        }
    }

    // 5. Loopdagen

    private var daysStep: some View {
        let n = answers.runDays.count
        let tip: String
        if n < 2 {
            tip = "Kies minstens 2 dagen om een plan te kunnen maken."
        } else if n >= 4 {
            tip = "Met 4 of meer dagen krijg je in de zwaardere weken een tweede kwaliteitssessie."
        } else {
            tip = "Kies 3 of 4 dagen, bij voorkeur met een rustdag ertussen."
        }
        return VStack(alignment: .leading, spacing: 20) {
            question("Op welke dagen kan je lopen?", tip)
            VStack(spacing: 6) {
                ForEach(Weekday.allCases, id: \.self) { d in
                    let on = answers.runDays.contains(d)
                    dayRow(d.name.capitalized, on: on) { toggleDay(d) }
                }
            }
            Text("\(n) dagen gekozen")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func toggleDay(_ d: Weekday) {
        if answers.runDays.contains(d) {
            answers.runDays.remove(d)
        } else {
            answers.runDays.insert(d)
        }
    }

    private func dayRow(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 15, weight: .bold))
                Spacer()
                CheckCircle(on: on)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(on ? Theme.card : Theme.sunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? Theme.text : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // 6. Dag lange loop

    private var longDayStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("Op welke dag loop je lang?", "Kies een dag waarop je meer tijd hebt, vaak in het weekend.")
            VStack(spacing: 6) {
                ForEach(answers.runDays.sorted(), id: \.self) { d in
                    dayRow(d.name.capitalized, on: answers.longRunDay == d) { answers.longRunDay = d }
                }
            }
            hint("De kwaliteitssessies komen zo ver mogelijk van deze dag te liggen.")
        }
    }

    // 7. Duur

    private var durationStep: some View {
        let cal = PlanCalendar.default
        let first = cal.date(byAdding: .day, value: 7 * 5 + 6, to: answers.startMonday) ?? answers.startMonday
        let last = cal.date(byAdding: .day, value: 7 * 23 + 6, to: answers.startMonday) ?? answers.startMonday
        let end = cal.date(byAdding: .day, value: 7 * (answers.planWeeks - 1) + answers.longRunDay.rawValue,
                           to: answers.startMonday) ?? answers.startMonday
        return VStack(alignment: .leading, spacing: 20) {
            question("Hoe lang trainen we?", "Een vaste duur of tot een wedstrijd. Tussen 6 en 24 weken.")
            Segmented(options: [(DurationMode.weeks, "Aantal weken"), (DurationMode.raceDate, "Racedatum")],
                      selection: $answers.durationMode)
            if answers.durationMode == .weeks {
                BigStepper(value: $answers.weeks, range: 6...24, unit: "weken")
            } else {
                DatePicker("Racedatum", selection: $answers.raceDate, in: first...last, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "nl_BE"))
                    .tint(Theme.accent)
                    .padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            hint("\(answers.planWeeks) weken: eerste training \(DateText.short(answers.firstTraining)), tijdrit \(DateText.withYear(end)).")
        }
    }

    // Preview

    private var previewPlan: TrainingPlan? {
        PlanGenerator.generate(answers.input)
    }

    @ViewBuilder
    private var previewStep: some View {
        if let plan = previewPlan {
            PlanPreview(plan: plan)
        } else {
            question("Er ging iets mis", "Met deze antwoorden kon geen plan gemaakt worden. Pas je antwoorden aan.")
        }
    }
}

/// Getal invullen in een groot vak, met eenheid erachter.
struct NumberBox: View {
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("0", value: $value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .font(.system(size: 34, weight: .black))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
            Text(unit)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .onChange(of: value) { _, new in
            let clamped = min(max(new, range.lowerBound), range.upperBound)
            if clamped != new { value = clamped }
        }
    }
}

/// "Je plan staat klaar": samenvatting van het gegenereerde plan.
struct PlanPreview: View {
    let plan: TrainingPlan

    var body: some View {
        let weeks = plan.weeks
        let volumes = weeks.map { $0.estimatedDistance(zones: $0.zones) / 1000 }
        let longs = weeks.compactMap { w in
            w.workouts.first { $0.type == .long || $0.type == .progression }
                .map { $0.estimatedDistance(zones: w.zones) / 1000 }
        }
        let start = weeks.first?.startDate ?? Date()
        let end = weeks.last?.date(for: plan.input.longRunDay) ?? start
        let zones = plan.zones

        return VStack(alignment: .leading, spacing: 14) {
            Text("Je plan staat klaar")
                .font(.system(size: 24, weight: .heavy))
                .accessibilityAddTraits(.isHeader)

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PlanTexts.goalTitle(plan.input))
                            .font(.system(size: 20, weight: .heavy))
                        Text("\(weeks.count) weken · \(DateText.short(start)) tot \(DateText.withYear(end))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    PhaseStrip(weeks: weeks, current: nil)
                    Divider().overlay(Theme.cardBorder)
                    HStack(alignment: .top) {
                        StatBlock(label: "Per week",
                                  value: "\(Int(volumes.first?.rounded() ?? 0)) → \(Int(volumes.max()?.rounded() ?? 0)) km", size: 19)
                        StatBlock(label: "Lange loop",
                                  value: "\(Fmt.decimal(longs.first ?? 0)) → \(Fmt.decimal(longs.max() ?? 0)) km", size: 19)
                        StatBlock(label: "10 km nu",
                                  value: TimeText.clock(zones.predictedTime(distance: 10_000)), size: 19)
                    }
                }
            }

            if let first = weeks.first {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Week 1").padding(.bottom, 8)
                        ForEach(first.workouts, id: \.day) { w in
                            HStack(spacing: 12) {
                                Text(w.day.short.uppercased())
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(width: 30, alignment: .leading)
                                RoundedRectangle(cornerRadius: 3).fill(w.type.color).frame(width: 10, height: 10)
                                Text(w.title).font(.system(size: 15, weight: .bold))
                                Spacer()
                                Text(TimeText.distance(w.estimatedDistance(zones: first.zones)))
                                    .font(.system(size: 15, weight: .bold))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }
}

/// Eén blokje per week, gekleurd per fase. De huidige week en eerdere weken in accent.
struct PhaseStrip: View {
    let weeks: [PlanWeek]
    let current: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(weeks, id: \.number) { w in
                    Capsule()
                        .fill(color(for: w))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 12) {
                ForEach(Phase.allCases, id: \.self) { p in
                    let n = weeks.filter { $0.phase == p }.count
                    if n > 0 {
                        Text("\(p.name) \(n)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func color(for week: PlanWeek) -> Color {
        if let current, week.number <= current { return Theme.accent }
        switch week.phase {
        case .base: return Theme.track
        case .build: return Theme.outline
        case .peak: return Color(hex: 0x6B7383)
        case .taper: return Theme.secondary
        }
    }

    private var accessibilityText: String {
        Phase.allCases.compactMap { p in
            let n = weeks.filter { $0.phase == p }.count
            return n > 0 ? "\(p.name) \(n) weken" : nil
        }.joined(separator: ", ")
    }
}

enum PlanTexts {
    /// Bv. "10 km sneller".
    static func goalTitle(_ input: PlanInput) -> String {
        let word: String
        switch input.goal {
        case .faster: word = "sneller"
        case .further: word = "verder"
        case .both: word = "verder en sneller"
        }
        return "\(TimeText.distance(input.goalDistance)) \(word)"
    }
}
