import SwiftUI
import MapKit
import LoopCore

/// Wat er gelopen moet worden: een geplande workout of vrij lopen.
struct RunRequest: Identifiable {
    let id = UUID()
    let workout: PlannedWorkout?
    let day: PlanDay?
    let zones: PaceZones?

    static let free = RunRequest(workout: nil, day: nil, zones: nil)
}

/// Volledig scherm tijdens het lopen, daarna "Na de loop".
struct RunScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker: RunTracker
    @State private var started = false
    @State private var confirmStop = false

    init(request: RunRequest) {
        _tracker = StateObject(wrappedValue: RunTracker(workout: request.workout, planDay: request.day,
                                                        zones: request.zones))
    }

    var body: some View {
        Group {
            switch tracker.phase {
            case .countdown:
                countdown
            case .running:
                live
            case .finished:
                if let run = tracker.result {
                    AfterRunView(run: run) { dismiss() }
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .onAppear {
            guard !started else { return }
            started = true
            tracker.begin()
        }
    }

    // MARK: - Aftellen

    private var countdown: some View {
        VStack(spacing: 18) {
            Spacer()
            SectionLabel(tracker.title)
            Text("\(max(tracker.countdownLeft, 0))")
                .font(.system(size: 110, weight: .black))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: tracker.countdownLeft)
            Text("Vergrendel je scherm gerust. Blok, tijd en knoppen staan op je vergrendelscherm.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            gpsBadge
            if let problem = tracker.authProblem {
                Text(problem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Button("Annuleren") { tracker.cancelCountdown() }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Lopen

    private var live: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Text(tracker.currentLabel)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(labelColor)
                    Spacer()
                    if tracker.paused {
                        Text("GEPAUZEERD")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.accent)
                    } else {
                        gpsBadge
                    }
                }
                Text(bigText)
                    .font(.system(size: 84, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !tracker.engine.isFreeRun {
                    Bar(fraction: tracker.stepProgress, color: labelColor, height: 6)
                }
                if let next = tracker.nextText {
                    Text(next)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 18)

            paceCard
                .padding(.horizontal, Theme.margin)
                .padding(.top, 20)

            HStack {
                StatBlock(label: "Afstand", value: Format.km(tracker.distance), size: 24)
                StatBlock(label: tracker.engine.isFreeRun ? "Kadans" : "Totaal", value: secondStat, size: 24)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 18)

            Spacer()

            controls
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
        }
        .confirmationDialog("Loop stoppen?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stoppen en bewaren", role: .destructive) { tracker.stop() }
            Button("Verder lopen", role: .cancel) {}
        } message: {
            Text("Wat je al liep wordt bewaard.")
        }
    }

    private var bigText: String {
        if tracker.engine.isFreeRun { return Format.clock(tracker.elapsed) }
        switch tracker.remaining {
        case .time(let t)?: return Format.clock(t)
        case .distance(let m)?: return m >= 1000 ? Format.km(m) : "\(Int(m.rounded())) m"
        case nil: return Format.clock(tracker.elapsed)
        }
    }

    private var secondStat: String {
        if tracker.engine.isFreeRun {
            return tracker.cadence.map { "\(Int($0.rounded())) spm" } ?? "–"
        }
        return Format.clock(tracker.elapsed)
    }

    private var labelColor: Color {
        tracker.currentStepIsEasy ? Theme.good : (tracker.workout?.type.color ?? Theme.accent)
    }

    private var paceColor: Color {
        switch tracker.paceStatus {
        case .onPace: return Theme.good
        case .tooFast: return Theme.accent
        case .tooSlow: return Theme.warn
        case .unknown: return Theme.text
        }
    }

    private var paceHint: String {
        switch tracker.paceStatus {
        case .onPace: return "Op tempo"
        case .tooFast: return tracker.currentStepIsEasy ? "Rustiger" : "Iets rustiger"
        case .tooSlow: return "Iets sneller"
        case .unknown: return "Tempo zoeken…"
        }
    }

    private var paceCard: some View {
        Card(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEMPO")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.secondary)
                    Text(Format.paceShort(tracker.currentPace))
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(paceColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(paceHint)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(paceColor)
                    if let r = tracker.targetRange, !tracker.engine.isFreeRun {
                        Text(tracker.currentStepIsEasy ? "rustig, trager dan \(TimeText.clock(r.fast))" : "doel \(TimeText.range(r))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                tracker.paused ? tracker.resume() : tracker.pause()
            } label: {
                Label(tracker.paused ? "Hervat" : "Pauze", systemImage: tracker.paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))

            HStack(spacing: 10) {
                if !tracker.engine.isFreeRun {
                    Button {
                        tracker.skip()
                    } label: {
                        Label("Blok overslaan", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 46))
                    .disabled(!tracker.canSkip)
                }
                Button {
                    confirmStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(height: 46))
            }
        }
    }

    private var gpsBadge: some View {
        let acc = tracker.gpsAccuracy
        let good = acc.map { $0 >= 0 && $0 <= 20 } ?? false
        return Label(acc.map { "GPS ±\(Int($0)) m" } ?? "GPS zoeken…",
                     systemImage: good ? "location.fill" : "location.slash")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(good ? Theme.good : Theme.warn)
    }
}

// MARK: - Na de loop

/// Twee stappen zoals getekend: eerst hoe zwaar het voelde, dan de samenvatting met de reactie van de coach.
struct AfterRunView: View {
    @EnvironmentObject var model: AppModel
    let run: CompletedRun
    let onDone: () -> Void

    @State private var rpe: Int?
    @State private var pain: Bool?
    @State private var note = ""
    @State private var saved: CompletedRun?
    @State private var coachMessages: [UUID] = []

    var body: some View {
        if let saved {
            RunSummaryView(run: saved, messageIDs: coachMessages, onDone: onDone)
        } else {
            feelingStep
        }
    }

    private var feelingStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Loop afgerond")
                    Text("Hoe zwaar voelde het?")
                        .font(.system(size: 24, weight: .heavy))
                }
                HStack {
                    StatBlock(label: "Afstand", value: Fmt.km2(run.distance), size: 19)
                    StatBlock(label: "Tijd", value: TimeText.clock(run.duration), size: 19)
                    StatBlock(label: "Gem. tempo", value: run.averagePace.map { TimeText.clock($0) } ?? "–", size: 19)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...10, id: \.self) { n in
                        Button {
                            rpe = n
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 19, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(rpe == n ? Theme.background : Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(rpe == n ? Theme.text : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(rpe == n ? Theme.text : Theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zwaarte \(n), \(RPEText.label(n))")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let rpe {
                        Text("\(rpe) · \(RPEText.label(rpe))").font(.system(size: 16, weight: .heavy))
                        Text(RPEText.explanation(rpe))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text("1 is heel licht, 10 is alles gegeven.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    if let type = run.workout?.type {
                        Text("Verwacht voor een \(RPEText.typeName(type)): \(Fmt.decimal(Coach.expectedRPE(type), digits: Coach.expectedRPE(type) == Coach.expectedRPE(type).rounded() ? 0 : 1))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pijn of klachten?").font(.system(size: 16, weight: .heavy))
                    HStack(spacing: 8) {
                        Chip(title: "Nee", selected: pain == false, height: 44) { pain = false }
                        Chip(title: "Ja", selected: pain == true, height: 44) { pain = true }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notitie").font(.system(size: 16, weight: .heavy))
                    TextField("Optioneel", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
                }

                Button("Opslaan") { save() }
                    .buttonStyle(PrimaryButtonStyle(height: 52))
                    .disabled(rpe == nil || pain == nil)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 20)
        }
    }

    private func save() {
        var r = run
        r.rpe = rpe
        r.pain = pain ?? false
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        r.note = trimmed.isEmpty ? nil : trimmed
        coachMessages = model.saveRun(r)
        saved = r
    }
}

/// Samenvatting na het opslaan.
struct RunSummaryView: View {
    @EnvironmentObject var model: AppModel
    let run: CompletedRun
    let messageIDs: [UUID]
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(DateText.short(run.date))
                    Text(run.workout?.title ?? "Vrije loop")
                        .font(.system(size: 24, weight: .heavy))
                }
                .padding(.top, 8)

                let messages = model.messages.filter { messageIDs.contains($0.id) }
                if messages.isEmpty, run.workout != nil {
                    Card(padding: 16) {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.good).frame(width: 8, height: 8)
                            Text(run.status == .stoppedEarly ? "Loop vroeger gestopt. Bewaard." : "Bewaard. Geen aanpassingen aan je plan nodig.")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
                ForEach(messages) { CoachMessageCard(message: $0) }

                if run.route.count > 1 {
                    Map(initialPosition: .automatic) {
                        MapPolyline(coordinates: zip(run.route.latitudes, run.route.longitudes)
                            .map { CLLocationCoordinate2D(latitude: $0, longitude: $1) })
                            .stroke(Theme.accent, lineWidth: 4)
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .allowsHitTesting(false)
                }

                Card(padding: 16) {
                    VStack(spacing: 14) {
                        HStack {
                            StatBlock(label: "Afstand", value: Fmt.km2(run.distance), size: 19)
                            StatBlock(label: "Tijd", value: TimeText.clock(run.duration), size: 19)
                            StatBlock(label: "Gem. tempo", value: run.averagePace.map { TimeText.clock($0) } ?? "–", size: 19)
                        }
                        HStack {
                            StatBlock(label: "Kadans", value: run.cadence.map { "\(Int($0.rounded())) spm" } ?? "–", size: 19)
                            StatBlock(label: "Zwaarte", value: run.rpe.map { "\($0)/10" } ?? "–", size: 19)
                            StatBlock(label: "Pijn", value: run.pain ? "Ja" : "Nee", size: 19)
                        }
                    }
                }

                let work = run.blocks.filter { $0.kind == .work }
                if !work.isEmpty {
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Snelle blokken tegenover doel")
                            ForEach(Array(work.enumerated()), id: \.offset) { i, b in
                                BlockDeviationRow(index: i + 1, block: b)
                            }
                            Text("Links = sneller, rechts = trager. Groen = binnen 5 s van je doel.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }

                if !run.splits.isEmpty {
                    Card(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Tempo per kilometer")
                            ForEach(Array(run.splits.enumerated()), id: \.offset) { i, s in
                                HStack {
                                    Text(s.isFullKm ? "Km \(i + 1)" : "Laatste \(Int(s.distance.rounded())) m")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.secondary)
                                    Spacer()
                                    Text(s.pace.map { TimeText.pace($0) } ?? "–")
                                        .font(.system(size: 14, weight: .heavy))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Button("Klaar", action: onDone)
                    .buttonStyle(PrimaryButtonStyle(height: 52))
                    .padding(.top, 4)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 16)
        }
    }
}

/// Eén snel blok als staafje links (sneller) of rechts (trager) van het doel.
struct BlockDeviationRow: View {
    let index: Int
    let block: BlockResult

    var body: some View {
        let dev = block.deviation ?? 0
        let within = abs(dev) <= 5
        let color = within ? Theme.good : Theme.warn
        let fraction = min(abs(dev) / 30, 1)

        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.secondary)
                .frame(width: 18)
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 6)
                    Rectangle().fill(Theme.outline).frame(width: 2, height: 14).offset(x: half - 1)
                    Capsule().fill(color)
                        .frame(width: max(4, half * fraction), height: 6)
                        .offset(x: dev < 0 ? half - max(4, half * fraction) : half)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text(block.pace.map { TimeText.clock($0) } ?? "–")
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(dev == 0 ? "±0" : (dev < 0 ? "−\(Int((-dev).rounded()))" : "+\(Int(dev.rounded()))"))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blok \(index): \(block.pace.map { TimeText.clock($0) } ?? "geen tempo") per kilometer, \(Int(abs(dev).rounded())) seconden \(dev < 0 ? "sneller" : "trager") dan je doel")
    }
}

enum RPEText {
    static func label(_ n: Int) -> String {
        ["Heel licht", "Licht", "Rustig", "Comfortabel", "Matig", "Stevig", "Zwaar", "Erg zwaar", "Bijna maximaal", "Maximaal"][max(1, min(n, 10)) - 1]
    }

    static func explanation(_ n: Int) -> String {
        switch n {
        case 1...2: return "Nauwelijks inspanning, zoals wandelen."
        case 3...4: return "Je kan makkelijk volzinnen praten."
        case 5...6: return "Praten lukt, maar in kortere zinnen."
        case 7: return "Enkele woorden per keer."
        case 8: return "Praten lukt nauwelijks, je moet je concentreren."
        case 9: return "Niet lang meer vol te houden."
        default: return "Alles gegeven."
        }
    }

    static func typeName(_ t: WorkoutType) -> String {
        switch t {
        case .easy: return "rustige loop"
        case .long: return "lange loop"
        case .tempo: return "tempoloop"
        case .interval: return "intervaltraining"
        case .fartlek: return "fartlek"
        case .progression: return "progressieloop"
        case .recovery: return "herstelloop"
        case .test: return "tijdrit"
        }
    }
}
