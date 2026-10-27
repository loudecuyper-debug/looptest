import SwiftUI
import LoopCore

/// Loopdagen wijzigen zonder nieuw plan (Plan › Plan beheren › Loopdagen wijzigen, 27 okt 2026).
/// Kies je loopdagen, de dag voor de lange loop en eventueel zelf de kwaliteitsdag(en).
/// Weeknummer, fase, niveau en opbouw blijven; enkel de verdeling over de dagen verandert.
struct DaysSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var days: Set<Weekday> = []
    @State private var longDay: Weekday = .sunday
    /// nil = automatisch.
    @State private var quality: Weekday?
    @State private var quality2: Weekday?
    @State private var ready = false

    private var sortedDays: [Weekday] { days.sorted() }
    private var qualityList: [Weekday] { [quality, quality2].compactMap { $0 } }
    private var valid: Bool { days.count >= 2 && days.contains(longDay) }

    private var changed: Bool {
        guard let current = model.currentDays else { return true }
        return current.runDays.sorted() != sortedDays || current.longRunDay != longDay
            || current.qualityDays != qualityList
    }

    private var preview: AppModel.DaysPreview? {
        valid ? model.previewDays(sortedDays, longRunDay: longDay, qualityDays: qualityList) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    daysCard
                    longCard
                    qualityCard
                    previewCard
                    Text("Je weeknummer, fase, niveau en opbouw blijven. Het weekvolume wordt over de nieuwe dagen verdeeld. Verplaatste trainingen vanaf die week vervallen.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button(changed ? "Loopdagen opslaan" : "Geen wijzigingen") {
                    model.changeDays(sortedDays, longRunDay: longDay, qualityDays: qualityList)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .disabled(!changed || preview == nil)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 10)
                .background(Theme.background)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Loopdagen")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.text)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleren") { dismiss() }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .onChange(of: days) { _, _ in sanitize() }
        .onChange(of: longDay) { _, _ in sanitize() }
        .onChange(of: quality) { _, _ in sanitize() }
    }

    private func load() {
        guard !ready, let current = model.currentDays else { return }
        days = Set(current.runDays)
        longDay = current.longRunDay
        quality = current.qualityDays.first
        quality2 = current.qualityDays.count > 1 ? current.qualityDays[1] : nil
        ready = true
    }

    /// Houdt de keuzes geldig als je dagen aan- of uitzet.
    private func sanitize() {
        let fallback: Weekday? = days.contains(.sunday) ? Weekday.sunday : days.max()
        if !days.contains(longDay), let fallback {
            longDay = fallback
        }
        if let q = quality, !days.contains(q) || q == longDay { quality = nil }
        if let q = quality2, !days.contains(q) || q == longDay || q == quality || quality == nil || days.count < 4 {
            quality2 = nil
        }
    }

    // MARK: - Kaarten

    private var daysCard: some View {
        let n = days.count
        let tip: String
        if n < 2 {
            tip = "Kies minstens 2 dagen."
        } else if n >= 4 {
            tip = "Met 4 of meer dagen krijg je in Zwaarder en Piek een tweede kwaliteitssessie."
        } else {
            tip = "3 of 4 dagen werkt het best, bij voorkeur met een rustdag ertussen."
        }
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Loopdagen")
                    Spacer()
                    Text("\(n) gekozen")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                VStack(spacing: 6) {
                    ForEach(Weekday.allCases, id: \.self) { d in
                        DayToggleRow(title: d.name.capitalized, on: days.contains(d)) {
                            if days.contains(d) { days.remove(d) } else { days.insert(d) }
                        }
                    }
                }
                Text(tip)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var longCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Lange loop")
                DayChips(days: sortedDays, selection: Binding<Weekday?>(
                    get: { longDay }, set: { if let d = $0 { longDay = d } }))
                Text("Kies een dag waarop je tijd hebt, de lange loop is je langste training van de week.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var qualityCard: some View {
        let options = sortedDays.filter { $0 != longDay }
        if !options.isEmpty {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Kwaliteitssessie")
                    DayChips(options: DayChips.withAuto(options), selection: $quality)
                    if days.count >= 4, quality != nil {
                        SectionLabel("Tweede sessie (Zwaarder en Piek)").padding(.top, 6)
                        DayChips(options: DayChips.withAuto(options.filter { $0 != quality }),
                                 selection: $quality2)
                    }
                    Text(quality == nil
                         ? "Auto: zo ver mogelijk van de lange loop en van elkaar. De overige dagen worden rustige loopjes."
                         : "De overige dagen worden rustige loopjes. Hou bij voorkeur een dag tussen twee zware trainingen.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        if let preview {
            let weeks = previewWeeks(preview)
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Zo ziet het eruit")
                    Text(startText(preview))
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(weeks, id: \.number) { week in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Week \(week.number) · \(week.phase.name)\(week.isRecoveryWeek ? " · rustweek" : "")")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.secondary)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                            if week.workouts.isEmpty {
                                Text("Geen trainingen meer deze week.")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.tertiary)
                                    .padding(.vertical, 6)
                            }
                            ForEach(week.workouts, id: \.day) { w in
                                HStack(spacing: 10) {
                                    Text(w.day.short.uppercased())
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(Theme.secondary)
                                        .frame(width: 26, alignment: .leading)
                                    RoundedRectangle(cornerRadius: 3).fill(w.type.color).frame(width: 10, height: 10)
                                    Text(w.isExtra ? "\(w.title) (extra)" : w.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(TimeText.distance(w.estimatedDistance(zones: week.zones)))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.secondary)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 7)
                                .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                            }
                        }
                    }
                }
            }
        } else if !model.canChangeDays {
            Card(padding: 16) {
                Text("Je plan is afgerond. Loopdagen kies je in een nieuw plan.")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    /// De eerste week met de nieuwe dagen, en bij 4+ dagen ook de eerste week met twee kwaliteitssessies.
    private func previewWeeks(_ p: AppModel.DaysPreview) -> [PlanWeek] {
        let weeks = p.plan.weeks
        guard p.fromWeek < weeks.count else { return [] }
        var shown = [weeks[p.fromWeek]]
        // In de eerste week vallen soms dagen weg: toon dan ook de volgende, volledige week.
        if p.startsToday, p.fromWeek + 1 < weeks.count {
            shown.append(weeks[p.fromWeek + 1])
        }
        if days.count >= 4,
           let busy = weeks[p.fromWeek...].first(where: { w in w.workouts.filter { $0.type.isQuality }.count >= 2 }),
           !shown.contains(where: { $0.number == busy.number }) {
            shown.append(busy)
        }
        return shown
    }

    private func startText(_ p: AppModel.DaysPreview) -> String {
        guard let today = model.today else { return "Geldt vanaf de start van je plan." }
        if p.startsToday { return "Geldt vanaf vandaag. Dagen van deze week die al voorbij zijn, vallen weg." }
        let monday = p.plan.weeks.indices.contains(p.fromWeek) ? p.plan.weeks[p.fromWeek].startDate : Date()
        let reason = p.fromWeek > today.week ? "Je liep deze week al of er staat een training als gemist, daarom " : ""
        return reason + "gelden de nieuwe dagen vanaf \(DateText.long(monday)) (week \(p.fromWeek + 1))."
    }
}

/// Rij met een dag en een vinkje, zoals in de vragenreeks.
struct DayToggleRow: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 15, weight: .bold))
                Spacer()
                CheckCircle(on: on)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(on ? Theme.card : Theme.sunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(on ? Theme.text : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Een rij chips om één dag te kiezen (of "Auto" = nil).
struct DayChips: View {
    let options: [(Weekday?, String)]
    @Binding var selection: Weekday?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                Chip(title: option.1, selected: selection == option.0, height: 40) {
                    selection = option.0
                }
            }
        }
    }
}

extension DayChips {
    /// Variant zonder "Auto": er moet altijd een dag gekozen zijn.
    init(days: [Weekday], selection: Binding<Weekday?>) {
        self.options = days.map { d -> (Weekday?, String) in (d, d.short) }
        self._selection = selection
    }

    /// "Auto" gevolgd door de dagen.
    static func withAuto(_ days: [Weekday]) -> [(Weekday?, String)] {
        let auto: (Weekday?, String) = (nil, "Auto")
        return [auto] + days.map { d -> (Weekday?, String) in (d, d.short) }
    }
}

extension PlanTexts {
    /// Bv. "Loopdagen: di, do, za, zo · lange loop do · kwaliteit di".
    static func days(_ s: DaySchedule) -> String {
        let list = { (days: [Weekday]) in days.map { $0.short.lowercased() } }
        var parts = ["Loopdagen: " + list(s.runDays.sorted()).joined(separator: ", "),
                     "lange loop " + s.longRunDay.short.lowercased()]
        if !s.qualityDays.isEmpty {
            parts.append("kwaliteit " + list(s.qualityDays).joined(separator: " en "))
        }
        return parts.joined(separator: " · ")
    }
}
