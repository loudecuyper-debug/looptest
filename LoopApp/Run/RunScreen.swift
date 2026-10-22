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
    @State private var page = 0
    @State private var locked = false
    @State private var holding = false
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

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

    // MARK: - Lopen (ontwerp 20 okt: drie pagina's om tussen te swipen, vergrendelknop)

    private var live: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.margin)
                .padding(.top, 14)

            TabView(selection: $page) {
                numbersPage.tag(0)
                mapPage.tag(1)
                kmPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .allowsHitTesting(!locked)

            pageDots.padding(.vertical, 10)

            Group {
                if locked { unlockControl } else { controls }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
        }
        .confirmationDialog("Loop stoppen?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button(tracker.tooShortToSave ? "Stoppen zonder bewaren" : "Stoppen en bewaren", role: .destructive) {
                tracker.stop()
            }
            Button("Verder lopen", role: .cancel) {}
        } message: {
            Text(tracker.tooShortToSave
                 ? "Je liep nog geen 100 m. Deze loop wordt niet bewaard."
                 : "Wat je al liep wordt bewaard.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(tracker.currentLabel)
                .font(.system(size: 13, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(labelColor)
                .lineLimit(1)
            Spacer(minLength: 6)
            if tracker.paused {
                Text(tracker.autoPaused ? "AUTOPAUZE" : "GEPAUZEERD")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.accent)
            } else if locked {
                Text("VERGRENDELD")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.accent)
            } else {
                gpsBadge
            }
            if !locked {
                Button {
                    withAnimation(.snappy) { locked = true }
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Theme.sunken, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scherm vergrendelen")
            }
        }
        .frame(minHeight: 36)
    }

    // Pagina 1: cijfers

    private var numbersPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !tracker.engine.isFreeRun, !tracker.overview.isEmpty {
                OverviewStrip(segments: tracker.overview, title: tracker.workout?.title ?? "")
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(bigLabel)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(bigText)
                        .font(.system(size: 76, weight: .black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let of = ofText {
                        Text(of)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                if let next = tracker.nextText {
                    Text(next)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }

            if let plan = tracker.schedule {
                ScheduleCard(offset: plan.offset, goal: plan.goal, projected: plan.projected)
            } else {
                paceCard
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 14) {
                ForEach(gridStats) { s in
                    StatBlock(label: s.label, value: s.value, size: 24)
                }
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
    }

    private var bigLabel: String {
        if tracker.engine.isFreeRun { return "Tijd" }
        return tracker.schedule != nil ? "Nog te gaan" : "Nog in dit blok"
    }

    private var bigText: String {
        if tracker.engine.isFreeRun { return Format.clock(tracker.elapsed) }
        switch tracker.remaining {
        case .time(let t)?: return Format.clock(t)
        case .distance(let m)?: return m >= 1000 ? Format.km(m) : "\(Int(m.rounded())) m"
        case nil: return Format.clock(tracker.elapsed)
        }
    }

    /// "van 800 m", "van 3:00", leeg bij een tijdrit (de grote afstand zegt genoeg).
    private var ofText: String? {
        guard !tracker.engine.isFreeRun, tracker.schedule == nil, let s = tracker.engine.currentStep else { return nil }
        switch s.step.length {
        case .distance(let m): return "van " + (m >= 1000 ? Fmt.km2(m) : "\(Int(m)) m")
        case .time(let t): return "van " + Format.clock(t)
        }
    }

    private var gridStats: [GridStat] {
        let cadence = tracker.cadence.map { "\(Int($0.rounded())) spm" } ?? "–"
        if tracker.engine.isFreeRun {
            let km = tracker.currentKm
            return [GridStat("Afstand", Format.km(tracker.distance)),
                    GridStat("Gem. tempo", tracker.averagePace.map { TimeText.clock($0) } ?? "–"),
                    GridStat("Km \(km.number)", km.pace.map { TimeText.clock($0) } ?? "–"),
                    GridStat("Kadans", cadence)]
        }
        if tracker.schedule != nil {
            return [GridStat("Gem. tempo", tracker.blockPace.map { TimeText.clock($0) } ?? "–"),
                    GridStat("Gelopen", Format.km(tracker.distance)),
                    GridStat("Tijd", Format.clock(tracker.elapsed)),
                    GridStat("Kadans", cadence)]
        }
        return [GridStat("Gem. dit blok", tracker.blockPace.map { TimeText.clock($0) } ?? "–"),
                GridStat("Afstand", Format.km(tracker.distance)),
                GridStat("Totale tijd", Format.clock(tracker.elapsed)),
                GridStat("Kadans", cadence)]
    }

    private var paceCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Tempo nu")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(tracker.currentPace.map { TimeText.clock($0) } ?? "-:--")
                                .font(.system(size: 34, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(paceColor)
                            Text("/km")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(paceHint)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(paceColor)
                        if let r = tracker.targetRange, !tracker.engine.isFreeRun {
                            Text(tracker.currentStepIsEasy ? "trager dan \(TimeText.clock(r.fast))" : "doel \(TimeText.range(r))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
                if let r = tracker.targetRange, !tracker.engine.isFreeRun {
                    PaceMeter(pace: tracker.currentPace, range: r, easy: tracker.currentStepIsEasy)
                }
            }
        }
    }

    // Pagina 2: kaart

    private var mapPage: some View {
        VStack(spacing: 12) {
            compactNow
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    if tracker.route.count > 1 {
                        MapPolyline(coordinates: tracker.route).stroke(Theme.accent, lineWidth: 5)
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)   // anders botst slepen op de kaart met swipen tussen de pagina's

                HStack(spacing: 8) {
                    mapStat("Afstand", Format.km(tracker.distance))
                    mapStat("Tijd", Format.clock(tracker.elapsed))
                    mapStat("Gem.", tracker.averagePace.map { TimeText.clock($0) } ?? "–")
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
    }

    private func mapStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.secondary)
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Kleine versie van het belangrijkste: resterend (of tijd) en tempo.
    private var compactNow: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bigText)
                    .font(.system(size: 40, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(tracker.currentPace.map { TimeText.clock($0) } ?? "-:--")
                        .font(.system(size: 24, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(paceColor)
                    Text("/km")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
            }
            if !tracker.engine.isFreeRun {
                Bar(fraction: tracker.stepProgress, color: labelColor, height: 6)
            }
        }
    }

    // Pagina 3: kilometers en snelle blokken

    private var kmPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                compactNow
                LiveSplitsCard(splits: tracker.engine.splits, current: tracker.currentKm)
                let work = tracker.engine.blocks.filter { $0.kind == .work }
                if !work.isEmpty || tracker.engine.currentStep?.kind == .work {
                    LiveBlocksCard(blocks: work,
                                   currentPace: tracker.engine.currentStep?.kind == .work ? tracker.blockPace : nil,
                                   currentDistance: tracker.distance - tracker.engine.stepStartDistance,
                                   range: tracker.engine.currentStep?.kind == .work ? tracker.targetRange : nil)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Theme.text : Theme.outline)
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pagina \(page + 1) van 3: \(["cijfers", "kaart", "kilometers"][page])")
    }

    private var labelColor: Color {
        if tracker.engine.isFreeRun { return Theme.accent }
        return Color(hex: tracker.hex(for: tracker.engine.currentStep))
    }

    private var paceColor: Color {
        if tracker.engine.isFreeRun { return Theme.text }
        switch tracker.paceStatus {
        case .onPace: return Theme.good
        case .tooFast: return Theme.accent
        case .tooSlow: return Theme.warn
        case .unknown: return Theme.text
        }
    }

    private var paceHint: String {
        if tracker.engine.isFreeRun { return tracker.currentPace == nil ? "Tempo zoeken…" : "" }
        switch tracker.paceStatus {
        case .onPace: return "Op tempo"
        case .tooFast: return tracker.currentStepIsEasy ? "Rustiger" : "Iets rustiger"
        case .tooSlow: return "Iets sneller"
        case .unknown: return "Tempo zoeken…"
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

    /// Vergrendeld: tikken doet niets, 1 seconde vasthouden ontgrendelt.
    private var unlockControl: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.sunken)
                Circle().strokeBorder(Theme.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: holding ? 1 : 0)
                    .stroke(Theme.text, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                    .animation(holding ? .linear(duration: 1) : .easeOut(duration: 0.2), value: holding)
                Image(systemName: "lock.fill").font(.system(size: 24, weight: .bold))
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 1) {
                withAnimation(.snappy) { locked = false }
                holding = false
            } onPressingChanged: { pressing in
                holding = pressing
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scherm ontgrendelen")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { locked = false }

            Text("Houd 1 seconde vast om te ontgrendelen")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.secondary)
            Text("Pauze en blok overslaan kan ook via het vergrendelscherm.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
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

// MARK: - Onderdelen van het loopscherm

/// Eén cijfer in het raster onder de tempokaart.
struct GridStat: Identifiable {
    let label: String
    let value: String
    var id: String { label }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// Overzicht van de hele workout: één stukje per blok, breedte naar duur.
/// Het huidige blok krijgt minstens 40% van de breedte (anders zijn korte intervallen
/// onleesbaar), vult zich in de typekleur en een wit staafje toont hoe ver je zit (22 okt).
struct OverviewStrip: View {
    let segments: [RunTracker.Segment]
    let title: String

    /// Aandeel van de breedte voor het huidige blok, minstens.
    static let currentShare = 0.4
    private let barHeight: CGFloat = 12
    private let markerHeight: CGFloat = 20

    /// Breedte per blok: naar duur, met het huidige blok opgerekt tot minstens 40%.
    static func shares(_ segments: [RunTracker.Segment]) -> [Double] {
        let total = segments.reduce(0.0) { $0 + $1.weight }
        guard total > 0 else { return segments.map { _ in 0 } }
        var shares = segments.map { $0.weight / total }
        guard segments.count > 1, let i = segments.firstIndex(where: { $0.current }),
              shares[i] < currentShare else { return shares }
        let rest = 1 - shares[i]
        let scale = rest > 0 ? (1 - currentShare) / rest : 0
        for j in shares.indices { shares[j] = j == i ? currentShare : shares[j] * scale }
        return shares
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = max(0, geo.size.width - gap * CGFloat(max(0, segments.count - 1)))
                let shares = OverviewStrip.shares(segments)
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                        segmentView(s, width: max(4, usable * CGFloat(shares[i])))
                    }
                }
                .frame(height: geo.size.height)
                .animation(.easeInOut(duration: 0.35), value: segments.firstIndex(where: { $0.current }))
            }
            .frame(height: markerHeight)
            HStack {
                Text("Start")
                Spacer()
                Text(title)
                Spacer()
                Text("Einde")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func segmentView(_ s: RunTracker.Segment, width: CGFloat) -> some View {
        let color = Color(hex: s.hex)
        if s.current {
            let p = CGFloat(max(0, min(s.progress, 1)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.28))
                    .frame(width: width, height: barHeight)
                RoundedRectangle(cornerRadius: 4).fill(color)
                    .frame(width: width * p, height: barHeight)
                Capsule().fill(Theme.text)
                    .frame(width: 3, height: markerHeight)
                    .offset(x: min(max(0, width * p - 1.5), max(0, width - 3)))
            }
            .frame(width: width, height: markerHeight, alignment: .leading)
            .animation(.linear(duration: 1), value: s.progress)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(s.done ? color : Theme.track)
                .opacity(s.done ? 0.35 : 1)
                .frame(width: width, height: barHeight)
        }
    }

    private var accessibilityText: String {
        guard let i = segments.firstIndex(where: { $0.current }) else { return "Overzicht: workout klaar" }
        let pct = Int((segments[i].progress * 100).rounded())
        return "Overzicht: blok \(i + 1) van \(segments.count), \(pct) procent"
    }
}

/// Tempometer: doelzone als groene band, streepje = je tempo nu. Links trager, rechts sneller.
struct PaceMeter: View {
    let pace: Double?
    let range: PaceRange
    let easy: Bool

    var body: some View {
        let width = max(10, range.slow - range.fast)
        let slowEdge = range.slow + width
        let fastEdge = range.fast - width
        let span = slowEdge - fastEdge
        let pos: (Double) -> Double = { p in min(1, max(0, (slowEdge - p) / span)) }
        let bandStart = pos(range.slow)
        let bandEnd = easy ? 1 : pos(range.fast)
        let marker = pace.map(pos)

        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 6)
                    Capsule().fill(Theme.good.opacity(0.85))
                        .frame(width: max(6, w * (bandEnd - bandStart)), height: 10)
                        .offset(x: w * bandStart)
                    if let marker {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.text)
                            .frame(width: 4, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.card, lineWidth: 2))
                            .offset(x: w * marker - 2)
                            .animation(.easeOut(duration: 0.4), value: marker)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack {
                Text("trager")
                Spacer()
                Text(easy ? "rustig" : "\(TimeText.clock(range.slow)) – \(TimeText.clock(range.fast))")
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text("sneller")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pace == nil ? "Tempo nog onbekend" : "Tempometer")
    }
}

/// Tijdrit: voor of achter op schema.
struct ScheduleCard: View {
    let offset: TimeInterval
    let goal: TimeInterval
    let projected: TimeInterval

    var body: some View {
        let ahead = offset <= 0
        let secs = Int(abs(offset).rounded())
        let color = abs(offset) < 3 ? Theme.good : (ahead ? Theme.good : Theme.warn)
        let fraction = min(1, abs(offset) / 60)

        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Schema")
                        Text((ahead ? "−" : "+") + Format.clock(abs(offset)))
                            .font(.system(size: 34, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(color)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(secs < 3 ? "Op schema" : "\(secs) s \(ahead ? "voor" : "achter")")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(color)
                        Text("doel \(TimeText.clock(goal)) · eindtijd nu \(TimeText.clock(projected))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track).frame(height: 6)
                        Rectangle().fill(color)
                            .frame(width: half * fraction, height: 6)
                            .offset(x: ahead ? half : half - half * fraction)
                        Rectangle().fill(Theme.tertiary).frame(width: 2, height: 14).offset(x: half - 1)
                    }
                    .frame(height: 14)
                }
                .frame(height: 14)
                HStack {
                    Text("achter"); Spacer(); Text("op schema").foregroundStyle(Theme.secondary); Spacer(); Text("voor")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kilometers tot nu toe, met het lopende stuk gestreept.
struct LiveSplitsCard: View {
    let splits: [Split]
    let current: (number: Int, distance: Double, pace: Double?)

    var body: some View {
        let paces = splits.compactMap(\.pace) + (current.pace.map { [$0] } ?? [])
        let lo = paces.min() ?? 0
        let hi = paces.max() ?? 0
        let fastest = splits.compactMap(\.pace).min()

        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Per kilometer")
                if splits.isEmpty && current.distance < 50 {
                    Text("Je eerste kilometer verschijnt hier.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(Array(splits.enumerated()), id: \.offset) { i, s in
                    let isFastest = s.pace != nil && s.pace == fastest && splits.count > 1
                    row("\(i + 1)", s.pace, lo: lo, hi: hi, color: isFastest ? Theme.accent : Theme.muted, live: false)
                }
                if current.distance >= 50 {
                    row("\(current.number)", current.pace, lo: lo, hi: hi, color: Theme.outline, live: true)
                    Text("Km \(current.number) loopt nog: \(Fmt.km2(current.distance)) tot nu toe.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    private func row(_ label: String, _ pace: Double?, lo: Double, hi: Double, color: Color, live: Bool) -> some View {
        let fraction: Double = {
            guard let pace else { return 0 }
            guard hi - lo > 1 else { return 1 }
            return 0.35 + 0.65 * (hi - pace) / (hi - lo)
        }()
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(color == Theme.accent ? Theme.accent : Theme.secondary)
                .frame(width: 30, alignment: .leading)
            Bar(fraction: fraction, color: color, height: 8)
                .opacity(live ? 0.7 : 1)
            Text(pace.map { TimeText.clock($0) } ?? "–")
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(live ? Theme.secondary : (color == Theme.accent ? Theme.accent : Theme.text))
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Snelle blokken tot nu toe tegenover het doel, met het lopende blok onderaan.
struct LiveBlocksCard: View {
    let blocks: [BlockResult]
    let currentPace: Double?
    let currentDistance: Double
    let range: PaceRange?

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Snelle blokken")
                    Spacer()
                    if let r = range ?? blocks.last.map({ PaceRange(fast: $0.targetPace - 5, slow: $0.targetPace + 5) }) {
                        SectionLabel("Doel \(TimeText.range(r))")
                    }
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                    blockRow("\(i + 1)", detail: "\(Fmt.km2(b.distance)) · \(TimeText.clock(b.duration))",
                             pace: b.pace, deviation: b.deviation)
                }
                if let currentPace, let range {
                    blockRow("\(blocks.count + 1)", detail: "bezig · \(Int(currentDistance.rounded())) m",
                             pace: currentPace, deviation: range.deviation(of: currentPace))
                }
            }
        }
    }

    private func blockRow(_ n: String, detail: String, pace: Double?, deviation: Double?) -> some View {
        let dev = deviation ?? 0
        let within = abs(dev) <= 5
        return HStack(spacing: 10) {
            Text(n)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)
            Text(detail)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer()
            Text(pace.map { TimeText.clock($0) } ?? "–")
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
            Text(deviation == nil ? "" : (within ? "binnen" : "\(Int(abs(dev).rounded())) s \(dev < 0 ? "snel" : "traag")"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(within ? Theme.good : Theme.warn)
                .frame(width: 62, alignment: .trailing)
        }
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
                    RunRouteMap(route: run.route)
                }

                RunStatsGrid(run: run)

                let work = run.blocks.filter { $0.kind == .work }
                if !work.isEmpty { WorkBlocksCard(blocks: work) }

                if !run.splits.isEmpty { SplitsCard(splits: run.splits) }

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
