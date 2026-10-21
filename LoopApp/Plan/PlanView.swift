import SwiftUI
import LoopCore

struct PlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var showManage = false
    @State private var showOnboarding = false
    @State private var showLevel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = model.plan {
                    VStack(spacing: 14) {
                        planCard(plan)
                        zonesCard(plan)
                        predictionsCard(plan)
                        levelHistory(plan)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.margin)
                    .padding(.vertical, 8)
                }
            }
            .screenTitle("Jouw plan")
            .confirmationDialog("Plan beheren", isPresented: $showManage, titleVisibility: .visible) {
                Button("Nieuw plan maken", role: .destructive) { showOnboarding = true }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Loopdagen, de dag van je lange loop of je doel wijzigen doe je met een nieuw plan. Dat vervangt je huidige plan en de aanpassingen van de coach. Je gelopen loopjes blijven bewaard.")
            }
            .sheet(isPresented: $showLevel) {
                LevelSheet(test: nil)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(onCancel: { showOnboarding = false }) { input in
                    model.createPlan(input)
                    showOnboarding = false
                }
            }
        }
    }

    private var currentWeekNumber: Int? {
        switch model.moment() {
        case .running(let d): return d.week + 1
        case .finished: return model.plan?.weeks.count
        default: return nil
        }
    }

    // MARK: - Kaarten

    private func planCard(_ plan: TrainingPlan) -> some View {
        let last = plan.weeks.last
        let raceDate = last?.date(for: plan.input.longRunDay)
        let total = plan.weeks.reduce(0.0) { $0 + $1.estimatedDistance(zones: $1.zones) }

        return Card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PlanTexts.goalTitle(plan.input))
                        .font(.system(size: 21, weight: .heavy))
                    if let raceDate {
                        Text("Tijdrit: \(DateText.withYear(raceDate))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                PhaseStrip(weeks: plan.weeks, current: currentWeekNumber)
                HStack(alignment: .top) {
                    StatBlock(label: "Weken", value: "\(currentWeekNumber ?? 0)/\(plan.weeks.count)", size: 24)
                    StatBlock(label: "Totale afstand", value: "\(Fmt.decimal(total / 1000)) km", size: 24)
                }
                Button("Plan beheren") { showManage = true }
                    .buttonStyle(PrimaryButtonStyle(height: 52))
            }
        }
    }

    private func zonesCard(_ plan: TrainingPlan) -> some View {
        let vdot = model.currentVdot ?? plan.zones.vdot
        let zones = PaceZones(vdot: vdot)
        let shown: [PaceZone] = [.easy, .marathon, .threshold, .interval, .repetition]

        return Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Tempozones", color: Theme.muted)
                    Spacer()
                    Text("Niveau \(Fmt.decimal(vdot))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.bottom, 8)
                ForEach(shown, id: \.self) { z in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(z.color).frame(width: 10, height: 10).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(z.name).font(.system(size: 15, weight: .semibold))
                            Text(z.explanation)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(TimeText.range(zones.range(for: z)))
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    showLevel = true
                } label: {
                    Label("Niveau aanpassen", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                .padding(.top, 10)
            }
        }
    }

    private func predictionsCard(_ plan: TrainingPlan) -> some View {
        let zones = PaceZones(vdot: model.currentVdot ?? plan.zones.vdot)
        let distances: [(String, Double)] = [("5 km", 5_000), ("10 km", 10_000), ("Halve marathon", 21_097.5), ("Marathon", 42_195)]

        return Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Voorspelde tijden nu", color: Theme.muted).padding(.bottom, 8)
                ForEach(distances.indices, id: \.self) { i in
                    let item = distances[i]
                    HStack {
                        Text(item.0).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(TimeText.clock(zones.predictedTime(distance: item.1)))
                            .font(.system(size: 16, weight: .heavy))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                }
            }
        }
    }

    @ViewBuilder
    private func levelHistory(_ plan: TrainingPlan) -> some View {
        let changes = model.coach?.state.levelChanges ?? []
        if !changes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Niveau-aanpassingen", color: Theme.muted).padding(.bottom, 8)
                    HStack {
                        Text("Start").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(Fmt.decimal(plan.zones.vdot)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                        HStack {
                            Text("Vanaf week \(change.fromWeek + 1)").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(Fmt.decimal(change.vdot)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                    }
                }
            }
        }
    }
}
