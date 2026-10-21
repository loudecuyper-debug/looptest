import SwiftUI
import LoopCore

/// Een gelopen loop die als niveautest gebruikt wordt.
struct LevelTestSource: Identifiable {
    let id = UUID()
    let distance: Double
    let duration: TimeInterval
    let date: Date
}

/// Niveau aanpassen: zelf (vanuit Plan) of op basis van een gelopen loop (`LevelTest`).
/// Geldt vanaf de huidige week; eerdere weken blijven zoals ze waren.
struct LevelSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let test: LevelTestSource?

    @State private var value: Double = 0
    @State private var ready = false

    private var current: Double { model.currentVdot ?? model.plan?.zones.vdot ?? 38 }
    private var measured: Double? { test.flatMap { LevelTest.measured(distance: $0.distance, time: $0.duration) } }
    private var suggestion: Double? {
        test.flatMap { LevelTest.suggested(distance: $0.distance, time: $0.duration, current: current) }
    }
    private var changed: Bool { abs(value - current) >= 0.05 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let test { testCard(test) }
                    stepperCard
                    compareCard
                    Text("Geldt vanaf deze week, ook voor je tempozones en de tempo's tijdens het lopen. Eerdere weken blijven zoals ze waren. De coach doet de 2 weken erna geen nieuw tempovoorstel.")
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
                Button(changed ? "Niveau \(Fmt.decimal(value)) toepassen" : "Niveau blijft \(Fmt.decimal(current))") {
                    model.setLevel(value)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .disabled(!changed)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 10)
                .background(Theme.background)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(test == nil ? "Niveau aanpassen" : "Niveautest")
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
        .onAppear {
            guard !ready else { return }
            value = suggestion ?? current
            ready = true
        }
    }

    // MARK: - Kaarten

    private func testCard(_ test: LevelTestSource) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Uit je loop van \(DateText.short(test.date))")
                Text("\(Fmt.km2(test.distance)) in \(TimeText.clock(test.duration))")
                    .font(.system(size: 19, weight: .heavy))
                    .monospacedDigit()
                if let measured, let suggestion {
                    Text("Volgens de formule hoort dit bij niveau \(Fmt.decimal(measured)).")
                        .font(.system(size: 14, weight: .semibold))
                    Text(LevelTest.countsHalf(distance: test.distance)
                         ? "Korter dan 5 km: de helft van het verschil met je huidige niveau telt mee. Een korte loop test vooral snelheid, niet uithouding. Voorstel: \(Fmt.decimal(suggestion))."
                         : "Vanaf 5 km telt de test volledig mee. Voorstel: \(Fmt.decimal(suggestion)).")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Enkel bruikbaar als je deze loop zo snel mogelijk liep.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Text("Deze loop is te kort (minder dan 1,5 km) of het tempo is onrealistisch.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private var stepperCard: some View {
        Card(padding: 16) {
            VStack(spacing: 6) {
                SectionLabel("Nieuw niveau")
                HStack(spacing: 18) {
                    stepButton("minus") { value = Self.stepDown(value) }
                        .disabled(value <= LevelTest.allowedRange.lowerBound)
                    Text(Fmt.decimal(value))
                        .font(.system(size: 34, weight: .heavy))
                        .monospacedDigit()
                        .frame(minWidth: 110)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: value)
                    stepButton("plus") { value = Self.stepUp(value) }
                        .disabled(value >= LevelTest.allowedRange.upperBound)
                }
                Text("Nu: \(Fmt.decimal(current))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 48, height: 48)
                .background(Theme.sunken, in: Circle())
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "Een halve stap hoger" : "Een halve stap lager")
    }

    private var compareCard: some View {
        let old = PaceZones(vdot: current)
        let new = PaceZones(vdot: value)
        let zones: [PaceZone] = [.easy, .threshold, .interval]

        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel("Wat er verandert")
                    Spacer()
                    Text("NU → NIEUW")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.bottom, 6)
                compareRow("5 km", TimeText.clock(old.predictedTime(distance: 5_000)),
                           TimeText.clock(new.predictedTime(distance: 5_000)))
                compareRow("10 km", TimeText.clock(old.predictedTime(distance: 10_000)),
                           TimeText.clock(new.predictedTime(distance: 10_000)))
                ForEach(zones, id: \.self) { z in
                    compareRow(z.name, TimeText.range(old.range(for: z)), TimeText.range(new.range(for: z)))
                }
            }
        }
    }

    private func compareRow(_ label: String, _ old: String, _ new: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(old)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.tertiary)
            Text(new)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): nu \(old), nieuw \(new)")
    }

    // MARK: - Stappen van 0,5

    /// Naar de volgende halve stap omhoog (38,3 → 38,5, 40 → 40,5).
    static func stepUp(_ x: Double) -> Double {
        min(((x * 2 + 1e-6).rounded(.down) + 1) / 2, LevelTest.allowedRange.upperBound)
    }

    /// Naar de volgende halve stap omlaag (38,3 → 38, 40 → 39,5).
    static func stepDown(_ x: Double) -> Double {
        max(((x * 2 - 1e-6).rounded(.up) - 1) / 2, LevelTest.allowedRange.lowerBound)
    }
}
