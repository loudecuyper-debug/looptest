import Foundation
import CoreLocation
import CoreMotion
import UIKit
import Combine
import ActivityKit
import LoopCore

/// Het echte lopen: GPS, klok, stem, kadans en Live Activity rond de `WorkoutEngine` uit LoopCore.
/// Gebouwd op de proof of concept (Diagnose, getest op 18 okt, verwijderd op 20 okt).
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase { case countdown, running, finished }

    // Scherm
    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var countdownLeft = 10
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var currentPace: Double?
    @Published private(set) var paused = false
    /// Gepauzeerd door stilstaan (automatisch pauzeren), hervat vanzelf zodra je weer loopt.
    @Published private(set) var autoPaused = false
    @Published private(set) var gpsAccuracy: Double?
    @Published private(set) var authProblem: String?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var cadence: Double?
    /// Klaar om te bewaren na afloop.
    @Published private(set) var result: CompletedRun?

    let workout: PlannedWorkout?
    let planDay: PlanDay?
    private(set) var engine: WorkoutEngine

    var title: String { workout?.title ?? "Vrij lopen" }

    // Intern
    private let manager = CLLocationManager()
    private var bgActivity: CLBackgroundActivitySession?
    private let speaker: Speaker
    private let pedometer = CMPedometer()
    private var startDate: Date?
    private var realStart: Date?
    private var pausedAt: Date?
    private var timer: Timer?
    private var lastLocation: CLLocation?
    private var samples: [(t: TimeInterval, d: Double)] = []
    private var track = RouteTrack()
    private var steps: Int?
    private var activity: Activity<RunActivityAttributes>?
    private var lastActivityUpdate = Date.distantPast

    // Signalen (20 okt)
    private let mode = CueMode.current
    /// Laatst gespeelde aftelseconde, per blok (blokindex × 10 + seconde).
    private var lastCountdownKey: Int?
    /// Wanneer de laatste tempowaarschuwing klonk, om "weer op tempo" te melden.
    private var warnedAt: TimeInterval?
    private var onPaceSince: TimeInterval?

    // Automatisch pauzeren (20 okt, schakelaar in Instellingen)
    private let autoPauseOn = CueSettings.autoPauseEnabled
    private var autoPauseAnchor: CLLocation?
    private var movingFixes = 0
    /// Looptijd bij het laatste hervatten: daarna eerst 15 s niet opnieuw automatisch pauzeren.
    private var lastResumeElapsed: TimeInterval = -100

    init(workout: PlannedWorkout?, planDay: PlanDay?, zones: PaceZones?) {
        self.workout = workout
        self.planDay = planDay
        if let workout, let zones {
            engine = WorkoutEngine(workout: workout, zones: zones, settings: CueSettings.engineSettings)
        } else {
            engine = WorkoutEngine(freeRunWith: CueSettings.engineSettings)
        }
        let voice = Speaker(duck: CueSettings.duckMusic)
        voice.rateFactor = CueSettings.currentRateFactor
        speaker = voice
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Status voor het scherm

    var currentLabel: String {
        if engine.isFreeRun { return "VRIJ LOPEN" }
        return engine.currentStep.map { displayLabel($0) } ?? "KLAAR"
    }

    var nextText: String? {
        guard let next = engine.nextStep else { return nil }
        return "Daarna: \(displayLabel(next).lowercased()) · \(lengthText(next.step.length))"
    }

    /// Label van een blok, met het type in plaats van "SNEL" (bv. "INTERVAL · 3 VAN 5").
    func displayLabel(_ s: EngineStep) -> String {
        let base = engine.label(for: s)
        guard s.kind == .work, base.hasPrefix("SNEL"), let type = workout?.type,
              [.interval, .fartlek, .tempo, .progression].contains(type) else { return base }
        return type.label + String(base.dropFirst(4))
    }

    /// Rustig blok (inlopen, uitlopen, herstel, rustig): andere kleur en andere tempometer.
    func isEasy(_ s: EngineStep) -> Bool {
        s.isEasy || s.kind == .warmup || s.kind == .cooldown || s.kind == .recovery
    }

    /// Kleur van een blok als hex.
    func hex(for s: EngineStep?) -> UInt32 {
        guard let s else { return engine.isFreeRun ? 0xFF7A1A : (workout?.type.hex ?? 0xFF7A1A) }
        return isEasy(s) ? 0x4CC38A : (workout?.type.hex ?? 0xFF7A1A)
    }

    // MARK: - Cijfers voor het loopscherm

    /// Gemiddeld tempo in het huidige blok.
    var blockPace: Double? {
        Format.pace(duration: elapsed - engine.stepStartElapsed, distance: distance - engine.stepStartDistance)
    }

    /// Gemiddeld tempo van de hele loop.
    var averagePace: Double? { Format.pace(duration: elapsed, distance: distance) }

    /// Het lopende (nog niet volle) kilometerstuk.
    var currentKm: (number: Int, distance: Double, pace: Double?) {
        let d = engine.splits.reduce(0.0) { $0 + $1.distance }
        let t = engine.splits.reduce(0.0) { $0 + $1.duration }
        return (engine.splits.count + 1, max(0, distance - d), Format.pace(duration: elapsed - t, distance: distance - d))
    }

    /// Tijdrit over een vaste afstand: voor (negatief) of achter op schema, doeltijd en verwachte eindtijd.
    var schedule: (offset: TimeInterval, goal: TimeInterval, projected: TimeInterval)? {
        guard engine.workoutType == .test, let s = engine.currentStep, s.kind == .work,
              case .distance(let len) = s.step.length else { return nil }
        let d = distance - engine.stepStartDistance
        let t = elapsed - engine.stepStartElapsed
        let goal = s.targetPace * len / 1000
        let projected = d >= 100 ? t / d * len : goal
        return (t - s.targetPace * d / 1000, goal, projected)
    }

    /// Eén stuk van de overzichtsbalk.
    struct Segment: Identifiable {
        let id: Int
        let weight: Double
        let hex: UInt32
        let done: Bool
        let current: Bool
    }

    /// Alle blokken van de workout, breedte naar geschatte duur.
    var overview: [Segment] {
        engine.steps.enumerated().map { i, s in
            let w: Double
            switch s.step.length {
            case .time(let t): w = t
            case .distance(let m): w = m / 1000 * s.targetPace
            }
            return Segment(id: i, weight: max(w, 1), hex: hex(for: s),
                           done: i < engine.currentIndex || engine.isFinished, current: i == engine.currentIndex)
        }
    }

    var remaining: StepRemaining? { engine.remaining(elapsed: elapsed, distance: distance) }
    var stepProgress: Double { engine.progress(elapsed: elapsed, distance: distance) }
    var paceStatus: PaceStatus { engine.paceStatus(currentPace) }
    var targetRange: PaceRange? { engine.currentStep?.range }
    var currentStepIsEasy: Bool { engine.currentStep.map { $0.isEasy || $0.kind == .warmup || $0.kind == .cooldown || $0.kind == .recovery } ?? true }
    var canSkip: Bool { phase == .running && !paused && !engine.isFreeRun && engine.currentStep != nil }

    // MARK: - Bediening

    func begin() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        bgActivity = CLBackgroundActivitySession()
        manager.startUpdatingLocation()

        phase = .countdown
        countdownLeft = 10
        if mode.usesVoice { speaker.speak("Start over 10 seconden.") }
        startTimer()
        RunControlCenter.handler = { [weak self] control in self?.handle(control) }
        startActivity()
    }

    func pause() {
        pause(auto: false)
    }

    private func pause(auto: Bool) {
        guard phase == .running, !paused else { return }
        elapsed = currentElapsed()
        pausedAt = Date()
        paused = true
        autoPaused = auto
        autoPauseAnchor = auto ? lastLocation : nil
        movingFixes = 0
        announce(auto ? "Automatisch gepauzeerd." : "Gepauzeerd.", signal: .pauze)
        updateActivity(force: true)
    }

    func resume() {
        guard phase == .running, paused, let p = pausedAt, let s = startDate else { return }
        startDate = s.addingTimeInterval(Date().timeIntervalSince(p))
        pausedAt = nil
        paused = false
        autoPaused = false
        autoPauseAnchor = nil
        lastResumeElapsed = currentElapsed()
        lastLocation = nil   // stuk tijdens de pauze telt niet mee
        announce("Verder.", signal: .hervat)
        update()
        updateActivity(force: true)
    }

    func skip() {
        guard canSkip else { return }
        let now = currentElapsed()
        elapsed = now
        let out = engine.skipStep(elapsed: now, distance: distance)
        apply(out)
        if !out.finished { updateActivity(force: true) }
    }

    /// Te kort om te bewaren: minder dan 100 m en minder dan 3 minuten
    /// (bv. per ongeluk gestart). Een lange loop zonder GPS blijft wel bewaard.
    var tooShortToSave: Bool {
        phase == .running && distance < 100 && currentElapsed() < 180
    }

    /// Stoppen. Tijdens het aftellen en bij een te korte loop wordt er niets bewaard.
    func stop() {
        switch phase {
        case .countdown:
            cancelCountdown()
        case .running where tooShortToSave:
            cancelCountdown()
        case .running:
            let now = currentElapsed()
            elapsed = now
            let out = engine.stop(elapsed: now, distance: distance)
            apply(out)
        case .finished:
            break
        }
    }

    /// Alles afsluiten zonder te bewaren (aftellen geannuleerd of te korte loop).
    func cancelCountdown() {
        timer?.invalidate()
        timer = nil
        stopSensors()
        speaker.stopAll()
        endActivity(immediately: true)
        RunControlCenter.handler = nil
        result = nil
        phase = .finished
    }

    private func handle(_ control: RunControl) {
        switch control {
        case .pause: pause()
        case .resume: resume()
        case .skip: skip()
        case .stop: stop()
        }
    }

    // MARK: - Klok

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch phase {
        case .countdown:
            countdownLeft -= 1
            if countdownLeft == 3, mode.usesVoice { speaker.speak("3, 2, 1") }
            if (1...3).contains(countdownLeft), mode.usesSignals { speaker.play(.aftel) }
            if countdownLeft <= 0 { beginRunning() }
        case .running:
            if !paused { update() }
        case .finished:
            break
        }
    }

    private func beginRunning() {
        let now = Date()
        startDate = now
        realStart = now
        phase = .running
        samples = [(t: 0, d: 0)]
        if let loc = lastLocation { record(loc, at: 0) }
        engine.start().forEach { handle($0) }
        startPedometer(from: now)
        update()
        updateActivity(force: true)
    }

    private func currentElapsed() -> TimeInterval {
        guard let s = startDate else { return 0 }
        return (pausedAt ?? Date()).timeIntervalSince(s)
    }

    private func update() {
        guard phase == .running, !paused else { return }
        let now = currentElapsed()
        elapsed = now
        currentPace = Format.rollingPace(samples: samples, now: now)
        let out = engine.update(elapsed: now, distance: distance, pace: currentPace)
        apply(out)
        if !out.finished {
            checkCountdownSignal(now)
            checkBackOnPace(now)
            checkAutoPause(now)
            updateActivity(force: !out.finishedBlocks.isEmpty)
        }
    }

    private func apply(_ out: EngineUpdate) {
        out.cues.forEach { handle($0) }
        if out.finished { finish() }
        objectWillChange.send()
    }

    // MARK: - Stem en signalen

    /// Zin en/of signaal, volgens de keuze in Instellingen. Bij "beide" eerst het signaal.
    private func announce(_ text: String?, signal: RunSignal?) {
        var delay: TimeInterval = 0
        if mode.usesSignals, let signal { delay = min(speaker.play(signal), 1.2) }
        if mode.usesVoice, let text { speaker.speak(text, delay: delay) }
    }

    private func handle(_ cue: Cue) {
        var signal: RunSignal?
        switch cue.kind {
        case .start:
            signal = .snel
        case .step:
            // De engine staat al op het nieuwe blok.
            signal = engine.currentStep.map { isEasy($0) ? RunSignal.herstel : RunSignal.snel }
            warnedAt = nil
            onPaceSince = nil
        case .countdown:
            signal = nil   // het aftellen met signalen gebeurt op de laatste 3 seconden
        case .pace:
            signal = cue.text.hasPrefix("Iets sneller") ? .sneller : .rustiger
            warnedAt = elapsed
            onPaceSince = nil
        case .onPace:
            signal = .optempo
        case .split:
            signal = .km
        case .finish:
            signal = .klaar
        }
        announce(cue.text, signal: signal)
    }

    /// Drie aftelsignalen op de laatste 3 seconden voor een snel blok (enkel bij tijdsblokken).
    private func checkCountdownSignal(_ now: TimeInterval) {
        guard mode.usesSignals, engine.settings.countdown, let next = engine.nextStep, !isEasy(next),
              case .time(let left)? = engine.remaining(elapsed: now, distance: distance) else { return }
        let sec = Int(left.rounded(.up))
        guard (1...3).contains(sec) else { return }
        let key = engine.currentIndex * 10 + sec
        guard key != lastCountdownKey else { return }
        lastCountdownKey = key
        speaker.play(.aftel)
    }

    // MARK: - Automatisch pauzeren

    /// Mag in vrij lopen, inlopen, uitlopen en rustige blokken (ook de lange loop).
    /// Niet in snelle blokken of herstel: daar sta je soms bewust stil en moet de klok doorlopen.
    private var autoPauseAllowed: Bool {
        guard autoPauseOn, phase == .running, !paused else { return false }
        if engine.isFreeRun { return true }
        guard let s = engine.currentStep else { return false }
        return s.kind == .warmup || s.kind == .cooldown || (s.kind == .steady && s.isEasy)
    }

    /// Stilstaan: minder dan 8 m in de laatste 10 s, met een verse, nauwkeurige GPS-meting
    /// (zonder GPS pauzeert de app dus niet, bv. in een tunnel).
    private func checkAutoPause(_ now: TimeInterval) {
        guard autoPauseAllowed, now >= 20, now - lastResumeElapsed >= 15,
              let last = lastLocation, abs(last.timestamp.timeIntervalSinceNow) < 5,
              last.horizontalAccuracy >= 0, last.horizontalAccuracy <= 20,
              let ref = samples.last(where: { $0.t <= now - 10 }) else { return }
        let slow = last.speed < 0 || last.speed < 0.8
        if distance - ref.d < 8, slow {
            pause(auto: true)
        }
    }

    /// Weer vertrekken: twee metingen na elkaar sneller dan 1,6 m/s of meer dan 15 m van waar je stilstond.
    private func checkAutoResume(_ loc: CLLocation) {
        let moved = autoPauseAnchor.map { loc.distance(from: $0) > 15 } ?? false
        if loc.speed >= 1.6 || moved {
            movingFixes += 1
        } else {
            movingFixes = 0
        }
        if movingFixes >= 2 { resume() }
    }

    /// Na een tempowaarschuwing: één melding zodra je 8 s aan een stuk weer in je zone loopt.
    private func checkBackOnPace(_ now: TimeInterval) {
        guard let warned = warnedAt else { return }
        if now - warned > 120 {
            warnedAt = nil
            onPaceSince = nil
            return
        }
        guard paceStatus == .onPace else {
            onPaceSince = nil
            return
        }
        let since = onPaceSince ?? now
        onPaceSince = since
        if now - since >= 8 {
            warnedAt = nil
            onPaceSince = nil
            announce("Weer op tempo.", signal: .optempo)
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        let duration = elapsed
        let avgCadence: Double? = {
            guard let steps, duration > 60 else { return nil }
            return Double(steps) / duration * 60
        }()
        stopSensors()
        paused = false
        pausedAt = nil
        result = engine.completedRun(date: realStart ?? Date(), planDay: planDay, workout: workout,
                                     distance: distance, duration: duration, route: track,
                                     cadence: avgCadence)
        phase = .finished
        endActivity(immediately: false)
        RunControlCenter.handler = nil
    }

    private func stopSensors() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        bgActivity?.invalidate()
        bgActivity = nil
        pedometer.stopUpdates()
    }

    // MARK: - Kadans

    private func startPedometer(from date: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                self?.steps = data.numberOfSteps.intValue
                if let c = data.currentCadence?.doubleValue { self?.cadence = c * 60 }
            }
        }
    }

    // MARK: - GPS

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            authProblem = "Locatietoegang staat uit. Zet hem aan via Instellingen › Runner › Locatie."
        default:
            authProblem = nil
        }
        if manager.accuracyAuthorization == .reducedAccuracy {
            authProblem = "Zet 'Exacte locatie' aan via Instellingen › Runner › Locatie."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations { handle(loc) }
        if phase == .running && !paused { update() }
    }

    private func handle(_ loc: CLLocation) {
        guard phase != .finished else { return }
        gpsAccuracy = loc.horizontalAccuracy
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30,
              abs(loc.timestamp.timeIntervalSinceNow) < 10 else { return }
        guard phase == .running else {   // tijdens het aftellen enkel opwarmen
            lastLocation = loc
            return
        }
        if paused {
            if autoPaused { checkAutoResume(loc) }
            return
        }

        if let last = lastLocation {
            let d = loc.distance(from: last)
            let dt = max(loc.timestamp.timeIntervalSince(last.timestamp), 0.5)
            guard d / dt < 12 else { return }   // sprongen sneller dan 43 km/u zijn GPS-ruis
            distance += d
        }
        lastLocation = loc
        let t = currentElapsed()
        record(loc, at: t)
        samples.append((t: t, d: distance))
        if samples.count > 400 { samples.removeFirst(samples.count - 400) }
    }

    private func record(_ loc: CLLocation, at t: TimeInterval) {
        route.append(loc.coordinate)
        track.append(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, time: t)
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: RunActivityAttributes(workoutName: title),
            content: ActivityContent(state: activityState(), staleDate: nil),
            pushType: nil)
    }

    private func updateActivity(force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = now
        let content = ActivityContent(state: activityState(), staleDate: nil)
        Task { await activity.update(content) }
    }

    private func endActivity(immediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(state: activityState(), staleDate: nil)
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(Date().addingTimeInterval(15 * 60))
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    private func activityState() -> RunActivityAttributes.ContentState {
        let now = Date()
        let run = phase == .finished ? elapsed : currentElapsed()
        var title = currentLabel
        var blockEnd: Date? = nil
        var blockStart: Date? = nil
        var runStart = startDate ?? now
        var remainingText: String? = nil
        var progress: Double? = nil
        var color = hex(for: engine.currentStep)

        switch engine.remaining(elapsed: run, distance: distance) {
        case .time(let left)?:
            remainingText = Format.clock(left)
            if !paused, phase == .running, case .time(let dur)? = engine.currentStep?.step.length {
                let end = now.addingTimeInterval(left)
                blockEnd = end
                blockStart = end.addingTimeInterval(-dur)
            }
            progress = engine.progress(elapsed: run, distance: distance)
        case .distance(let left)?:
            remainingText = left >= 1000 ? Format.km(left) : "\(Int(left.rounded())) m"
            progress = engine.progress(elapsed: run, distance: distance)
        case nil:
            break
        }
        var next = nextText
        if phase == .countdown {
            title = "START OVER"
            blockEnd = now.addingTimeInterval(TimeInterval(max(countdownLeft, 0)))
            blockStart = nil
            runStart = blockEnd ?? now
            next = engine.steps.first.map { "Eerst: " + displayLabel($0).lowercased() }
            color = hex(for: engine.steps.first)
            progress = nil
        }

        // Tempo en doel
        let status: Int
        switch paceStatus {
        case .onPace: status = 1
        case .tooFast: status = 2
        case .tooSlow: status = 3
        case .unknown: status = 0
        }
        var target: String? = nil
        if let r = targetRange, !engine.isFreeRun, phase == .running {
            if currentStepIsEasy {
                target = "rustig · trager dan \(TimeText.clock(r.fast))"
            } else {
                let word = ["", "op tempo", "te snel", "te traag"][status]
                target = (word.isEmpty ? "" : word + " · ") + "doel \(TimeText.range(r))"
            }
        }

        // Korte regel rechtsboven
        var info: String? = nil
        if phase == .finished {
            info = workout?.title ?? "Vrije loop"
        } else if paused {
            info = engine.isFreeRun ? "\(Format.km(distance)) gelopen"
                : [currentLabel.lowercased(), remainingText.map { "nog \($0)" }].compactMap { $0 }.joined(separator: " · ")
        } else if engine.isFreeRun, let last = engine.splits.last, let p = last.pace {
            info = "km \(engine.splits.count + 1) · vorige \(TimeText.clock(p))"
        }

        // Samenvatting op het einde
        var summaryLabel = "GEM. TEMPO"
        var summaryValue = averagePace.map { TimeText.clock($0) }
        let work = engine.blocks.filter { $0.kind == .work }
        let workDistance = work.reduce(0.0) { $0 + $1.distance }
        if workDistance >= 100 {
            summaryLabel = "SNELLE BLOKKEN"
            summaryValue = TimeText.clock(work.reduce(0.0) { $0 + $1.duration } / workDistance * 1000)
        }

        return RunActivityAttributes.ContentState(
            blockTitle: title,
            nextTitle: next,
            blockEnd: blockEnd,
            blockRemainingText: remainingText,
            runStart: runStart,
            elapsedText: Format.clock(run),
            distanceText: Format.km(distance),
            paceText: Format.paceShort(currentPace),
            paused: paused,
            finished: phase == .finished,
            canSkip: canSkip,
            isFreeRun: engine.isFreeRun,
            isCountdown: phase == .countdown,
            blockColor: color,
            blockStart: blockStart,
            progress: progress,
            paceValue: currentPace.map { TimeText.clock($0) },
            paceStatus: engine.isFreeRun ? 0 : status,
            targetText: target,
            infoText: info,
            summaryLabel: summaryLabel,
            summaryValue: summaryValue)
    }

    private func lengthText(_ length: StepLength) -> String {
        switch length {
        case .distance(let m): return TimeText.distance(m)
        case .time(let s): return Format.clock(s)
        }
    }
}
