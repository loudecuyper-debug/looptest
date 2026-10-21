import SwiftUI
import MapKit
import LoopCore

// Detail van een gelopen loop: alle info, route en tempo per km.
// Swipe links of rechts om door je loopjes te bladeren (nieuwste eerst).

struct RunPager: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID

    init(start: UUID) {
        _selection = State(initialValue: start)
    }

    var body: some View {
        let runs = model.runs
        let index = runs.firstIndex { $0.id == selection }

        TabView(selection: $selection) {
            ForEach(runs) { summary in
                RunDetailPage(summary: summary) { delete(summary.id) }
                    .tag(summary.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Activiteit").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    if let index, runs.count > 1 {
                        Text("\(index + 1) van \(runs.count) · swipe voor meer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Verwijdert een loop en springt naar de volgende (oudere), anders de vorige.
    private func delete(_ id: UUID) {
        let runs = model.runs
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return }
        let neighbor = i + 1 < runs.count ? runs[i + 1] : (i > 0 ? runs[i - 1] : nil)
        if let neighbor { selection = neighbor.id }
        model.deleteRun(id: id)
        if neighbor == nil { dismiss() }
    }
}

/// Eén loop, volledig.
struct RunDetailPage: View {
    @EnvironmentObject var model: AppModel
    let summary: RunSummary
    let onDelete: () -> Void

    @State private var run: CompletedRun?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var showMap = false
    @State private var levelTest: LevelTestSource?
    @State private var linkedMessages: [UUID] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let run {
                    if run.route.count > 1 {
                        RunRouteMap(route: run.route, height: 240)
                            .overlay(alignment: .bottomTrailing) {
                                Label("Groter", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.background.opacity(0.75), in: Capsule())
                                    .padding(10)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showMap = true }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Route op volledig scherm")
                    }

                    if let candidate = model.linkCandidate(for: summary) {
                        linkCard(candidate.workout)
                    }

                    RunStatsGrid(run: run, detailed: true)

                    ForEach(model.messages.filter { linkedMessages.contains($0.id) }) { CoachMessageCard(message: $0) }

                    if let workout = run.workout {
                        plannedCard(workout)
                    }

                    let work = run.blocks.filter { $0.kind == .work }
                    if !work.isEmpty { WorkBlocksCard(blocks: work) }

                    if !run.splits.isEmpty { SplitsCard(splits: run.splits) }

                    if let note = run.note {
                        Card(padding: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel("Notitie")
                                Text(note).font(.system(size: 15, weight: .semibold))
                            }
                        }
                    }

                    actions(run)
                } else if loaded {
                    Card(padding: 16) {
                        Text("De details van deze loop konden niet gelezen worden.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    deleteButton
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .task(id: summary.id) {
            run = model.loadRun(id: summary.id)
            loaded = true
        }
        .confirmationDialog("Loop verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive, action: onDelete)
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("\(summary.title) van \(DateText.short(summary.date)) wordt definitief verwijderd.")
        }
        .sheet(isPresented: $showMap) {
            if let run { FullRouteMap(run: run) }
        }
        .sheet(item: $levelTest) { test in
            LevelSheet(test: test)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let type = summary.type {
                TypeTag(type: type)
            } else {
                SectionLabel(summary.source == .manual ? "Manueel toegevoegd" : "Vrij lopen")
            }
            Text(summary.title)
                .font(.system(size: 24, weight: .heavy))
            Text("\(DateText.longCapitalized(summary.date)) · \(DateText.time(summary.date))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 4)
    }

    /// Vrije loop op een trainingsdag: achteraf laten meetellen als die training.
    private func linkCard(_ workout: PlannedWorkout) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Gepland die dag")
                HStack(spacing: 8) {
                    TypeTag(type: workout.type)
                    Text(workout.title).font(.system(size: 16, weight: .heavy))
                }
                Text("Liep je deze vrije loop in plaats van je training? Dan telt hij mee voor je plan en voor de coach.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    linkedMessages = model.linkRun(id: summary.id)
                    run = model.loadRun(id: summary.id)
                } label: {
                    Label("Meetellen als \(workout.title.lowercased())", systemImage: "link")
                }
                .buttonStyle(PrimaryButtonStyle(height: 46))
            }
        }
    }

    private func plannedCard(_ workout: PlannedWorkout) -> some View {
        let zones = model.plan?.weeks[safe: summary.planDay?.week ?? -1]?.zones ?? model.plan?.zones
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Gepland")
                Text(workout.title).font(.system(size: 16, weight: .heavy))
                if let zones {
                    Text(WorkoutText.describe(workout, zones: zones))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if run?.status == .stoppedEarly {
                    Text("Vroeger gestopt.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func actions(_ run: CompletedRun) -> some View {
        VStack(spacing: 10) {
            if LevelTest.measured(distance: run.distance, time: run.duration) != nil, model.plan != nil {
                Button {
                    levelTest = LevelTestSource(distance: run.distance, duration: run.duration, date: run.date)
                } label: {
                    Label("Gebruik als niveautest", systemImage: "speedometer")
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
            }
            deleteButton
        }
        .padding(.top, 6)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Loop verwijderen", systemImage: "trash")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WorkoutType.test.color)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gedeelde onderdelen (ook gebruikt na de loop)

/// Route als oranje lijn op een gedempte kaart, niet interactief.
struct RunRouteMap: View {
    let route: RouteTrack
    var height: CGFloat = 220

    var body: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: route.coordinates)
                .stroke(Theme.accent, lineWidth: 4)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Route op volledig scherm, met in- en uitzoomen, start en einde.
struct FullRouteMap: View {
    let run: CompletedRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let coords = run.route.coordinates
        NavigationStack {
            Map(initialPosition: .automatic) {
                MapPolyline(coordinates: coords).stroke(Theme.accent, lineWidth: 5)
                if let first = coords.first {
                    Annotation("Start", coordinate: first) {
                        Circle().fill(Theme.good).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
                if let last = coords.last, coords.count > 1 {
                    Annotation("Einde", coordinate: last) {
                        Circle().fill(Theme.text).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(Fmt.km2(run.distance)) · \(DateText.short(run.date))")
                        .font(.system(size: 16, weight: .heavy))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") { dismiss() }.fontWeight(.bold)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

/// De belangrijkste cijfers van een loop.
struct RunStatsGrid: View {
    let run: CompletedRun
    /// Uitgebreid: ook beste km, starttijd en bron.
    var detailed = false

    var body: some View {
        Card(padding: 16) {
            VStack(spacing: 14) {
                HStack {
                    StatBlock(label: "Afstand", value: Fmt.km2(run.distance), size: 19)
                    StatBlock(label: "Tijd", value: TimeText.clock(run.duration), size: 19)
                    StatBlock(label: "Gem. tempo", value: run.averagePace.map { TimeText.clock($0) } ?? "–", size: 19)
                }
                HStack {
                    if detailed {
                        StatBlock(label: "Beste km", value: bestKm.map { TimeText.clock($0) } ?? "–", size: 19)
                    }
                    StatBlock(label: "Kadans", value: run.cadence.map { "\(Int($0.rounded())) spm" } ?? "–", size: 19)
                    StatBlock(label: "Zwaarte", value: run.rpe.map { "\($0)/10" } ?? "–", size: 19)
                    if !detailed {
                        StatBlock(label: "Pijn", value: run.pain ? "Ja" : "Nee", size: 19)
                    }
                }
                if detailed {
                    HStack {
                        StatBlock(label: "Pijn", value: run.pain ? "Ja" : "Nee", size: 19)
                        StatBlock(label: "Start", value: DateText.time(run.date), size: 19)
                        StatBlock(label: "Bron", value: sourceText, size: 19)
                    }
                }
            }
        }
    }

    private var bestKm: Double? {
        run.splits.filter(\.isFullKm).compactMap(\.pace).min()
    }

    private var sourceText: String {
        switch run.source {
        case .gps: return "GPS"
        case .manual: return "Manueel"
        default: return "Loopband"
        }
    }
}

/// Tempo per kilometer als staafjes: hoe sneller, hoe langer. Snelste km in oranje.
struct SplitsCard: View {
    let splits: [Split]

    var body: some View {
        let paces = splits.compactMap(\.pace)
        let fastest = splits.filter(\.isFullKm).compactMap(\.pace).min()
        let lo = paces.min() ?? 0
        let hi = paces.max() ?? 0

        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Tempo per kilometer")
                ForEach(Array(splits.enumerated()), id: \.offset) { i, s in
                    let isFastest = s.isFullKm && s.pace != nil && s.pace == fastest && splits.count > 1
                    HStack(spacing: 10) {
                        Text(s.isFullKm ? "\(i + 1)" : "\(Int(s.distance.rounded())) m")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 50, alignment: .leading)
                        Bar(fraction: barFraction(s.pace, lo: lo, hi: hi),
                            color: isFastest ? Theme.accent : (s.isFullKm ? Theme.muted : Theme.outline),
                            height: 8)
                        Text(s.pace.map { TimeText.clock($0) } ?? "–")
                            .font(.system(size: 14, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(isFastest ? Theme.accent : Theme.text)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(s.isFullKm
                        ? "Kilometer \(i + 1): \(s.pace.map { TimeText.clock($0) } ?? "geen tempo") per kilometer\(isFastest ? ", snelste" : "")"
                        : "Laatste \(Int(s.distance.rounded())) meter: \(s.pace.map { TimeText.clock($0) } ?? "geen tempo") per kilometer")
                }
                if let fastest, splits.filter(\.isFullKm).count > 1 {
                    Text("Snelste kilometer: \(TimeText.clock(fastest)) per km.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    /// Snelste = volle balk, traagste = 35%.
    private func barFraction(_ pace: Double?, lo: Double, hi: Double) -> Double {
        guard let pace else { return 0 }
        guard hi - lo > 1 else { return 1 }
        return 0.35 + 0.65 * (hi - pace) / (hi - lo)
    }
}

/// Snelle blokken tegenover het doel.
struct WorkBlocksCard: View {
    let blocks: [BlockResult]

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Snelle blokken tegenover doel")
                ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                    BlockDeviationRow(index: i + 1, block: b)
                }
                Text("Links = sneller, rechts = trager. Groen = binnen 5 s van je doel.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

extension RouteTrack {
    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
