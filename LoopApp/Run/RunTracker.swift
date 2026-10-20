import Foundation
import CoreLocation
import CoreMotion
import UIKit
import Combine
import ActivityKit
import LoopCore

/// Het echte lopen: GPS, klok, stem, kadans en Live Activity rond de `WorkoutEngine` uit LoopCore.
/// Gebouwd op de proof of concept uit Diagnose (`RunSession`), die buiten getest werd op 18 okt.
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase { case countdown, running, finished }

    // Scherm
    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var countdownLeft = 10
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var currentPace: Double?
    @Published private(set) var paused = false
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
        return engine.currentStep.map { engine.label(for: $0) } ?? "KLAAR"
    }

    var nextText: String? {
        guard let next = engine.nextStep else { return nil }
        return "Daarna: \(engine.label(for: next).lowercased()) · \(lengthText(next.step.length))"
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
        speaker.speak("Start over 10 seconden.")
        startTimer()
        RunControlCenter.handler = { [weak self] control in self?.handle(control) }
        startActivity()
    }

    func pause() {
        guard phase == .running, !paused else { return }
        elapsed = currentElapsed()
        pausedAt = Date()
        paused = true
        speaker.speak("Gepauzeerd.")
        updateActivity(force: true)
    }

    func resume() {
        guard phase == .running, paused, let p = pausedAt, let s = startDate else { return }
        startDate = s.addingTimeInterval(Date().timeIntervalSince(p))
        pausedAt = nil
        paused = false
        lastLocation = nil   // stuk tijdens de pauze telt niet mee
        speaker.speak("Verder.")
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

    /// Stoppen. Tijdens het aftellen wordt er niets bewaard.
    func stop() {
        switch phase {
        case .countdown:
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

    /// Alles afsluiten zonder te bewaren (bv. scherm weggeveegd tijdens het aftellen).
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
            if countdownLeft == 3 { speaker.speak("3, 2, 1") }
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
        engine.start().forEach { speaker.speak($0.text) }
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
        if !out.finished { updateActivity(force: !out.finishedBlocks.isEmpty) }
    }

    private func apply(_ out: EngineUpdate) {
        out.cues.forEach { speaker.speak($0.text) }
        if out.finished { finish() }
        objectWillChange.send()
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
        guard !paused else { return }

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
        var runStart = startDate ?? now
        var remainingText: String? = nil

        switch engine.remaining(elapsed: run, distance: distance) {
        case .time(let left)?:
            remainingText = Format.clock(left)
            if !paused { blockEnd = now.addingTimeInterval(left) }
        case .distance(let left)?:
            remainingText = "\(Int(left.rounded())) m"
        case nil:
            break
        }
        var next = nextText
        if phase == .countdown {
            title = "START OVER"
            blockEnd = now.addingTimeInterval(TimeInterval(max(countdownLeft, 0)))
            runStart = blockEnd ?? now
            next = engine.steps.first.map { "Eerst: " + engine.label(for: $0).lowercased() }
        }
        // Afstandsblok: de grote klok toont de meters, dus geen aftellende tijd.
        if case .distance? = engine.remaining(elapsed: run, distance: distance), phase == .running {
            blockEnd = nil
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
            canSkip: canSkip)
    }

    private func lengthText(_ length: StepLength) -> String {
        switch length {
        case .distance(let m): return TimeText.distance(m)
        case .time(let s): return Format.clock(s)
        }
    }
}
