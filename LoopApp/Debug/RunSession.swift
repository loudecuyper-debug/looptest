import Foundation
import CoreLocation
import UIKit
import Combine
import ActivityKit

/// Proof of concept: koppelt GPS, klok en audio aan de CueEngine en houdt diagnose bij.
/// Bereikbaar via Instellingen › Diagnose. Wordt in de volgende stap de basis van het echte lopen.
final class RunSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase { case idle, countdown, running, finished }

    // UI-status
    @Published var phase: Phase = .idle
    @Published var planName = ""
    @Published var elapsed: TimeInterval = 0
    @Published var distance: Double = 0
    @Published var currentPace: Double?
    @Published var segmentTitle = ""
    @Published var segmentRemaining: TimeInterval?
    @Published var countdownLeft = 0
    @Published var paused = false
    @Published var canSkip = false
    @Published var gpsAccuracy: Double?
    @Published var authProblem: String?
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var results: [SegmentResult] = []
    @Published var log: [String] = []

    // Diagnose
    @Published var pointsTotal = 0
    @Published var pointsBackground = 0
    @Published var maxGap: TimeInterval = 0
    @Published var backgroundSeconds: TimeInterval = 0

    private let manager = CLLocationManager()
    private var bgActivity: CLBackgroundActivitySession?
    private let speaker = Speaker()
    private var engine: CueEngine?
    private var startDate: Date?
    private var timer: Timer?
    private var lastLocation: CLLocation?
    private var lastPointTime: Date?
    private var samples: [(t: TimeInterval, d: Double)] = []
    private var bgEnteredAt: Date?
    private var pausedAt: Date?
    private var activity: Activity<RunActivityAttributes>?
    private var lastActivityUpdate = Date.distantPast

    var voiceDescription: String { speaker.voiceDescription }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        speaker.onLog = { [weak self] in self?.addLog($0) }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Bediening

    func start(_ plan: WorkoutPlan) {
        resetState()
        planName = plan.name
        engine = CueEngine(plan: plan)
        addLog("Stem: \(speaker.voiceDescription)")

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        bgActivity = CLBackgroundActivitySession()
        manager.startUpdatingLocation()

        // 10 seconden aftellen: tijd om GPS op te warmen en je scherm te vergrendelen.
        phase = .countdown
        countdownLeft = 10
        speaker.speak("Start over 10 seconden. Je mag je scherm nu vergrendelen.")
        startTimer()

        // Knoppen op het vergrendelscherm komen hier binnen.
        RunControlCenter.handler = { [weak self] control in self?.handle(control) }
        startActivity()
    }

    // MARK: - Pauze en overslaan

    func pause() {
        guard phase == .running, !paused else { return }
        elapsed = currentElapsed()
        pausedAt = Date()
        paused = true
        speaker.speak("Gepauzeerd.")
        addLog("Gepauzeerd")
        updateActivity(force: true)
    }

    func resume() {
        guard phase == .running, paused, let p = pausedAt, let s = startDate else { return }
        startDate = s.addingTimeInterval(Date().timeIntervalSince(p))
        pausedAt = nil
        paused = false
        lastLocation = nil   // stuk tijdens de pauze telt niet mee
        speaker.speak("Verder.")
        addLog("Hervat")
        update()
        updateActivity(force: true)
    }

    func skipBlock() {
        guard phase == .running, !paused, var e = engine else { return }
        let now = currentElapsed()
        let out = e.skip(elapsed: now, distance: distance)
        engine = e
        if let r = out.result { results.append(r) }
        addLog("Blok overgeslagen")
        if out.finished {
            elapsed = now
            finish(spoken: "Test klaar. Je liep \(Format.spokenDistance(distance)) in \(Format.spokenDuration(now)).")
            return
        }
        if let cue = out.cue { speaker.speak(cue) }
        update()
        updateActivity(force: true)
    }

    private func handle(_ control: RunControl) {
        addLog("Knop vergrendelscherm: \(control.rawValue)")
        switch control {
        case .pause: pause()
        case .resume: resume()
        case .skip: skipBlock()
        case .stop: stopEarly()
        }
    }

    func stopEarly() {
        guard phase == .running || phase == .countdown else { return }
        if phase == .running, var e = engine {
            let now = currentElapsed()
            if let r = e.stop(elapsed: now, distance: distance) { results.append(r) }
            engine = e
            elapsed = now
        }
        finish(spoken: "Test gestopt. Je liep \(Format.spokenDistance(distance)).")
    }

    func reset() {
        speaker.stopAll()
        endActivity(immediately: true)
        resetState()
        phase = .idle
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
        default:
            break
        }
    }

    private func beginRunning() {
        guard var e = engine else { return }
        startDate = Date()
        phase = .running
        if let loc = lastLocation { route.append(loc.coordinate) }
        samples = [(t: 0, d: 0)]
        speaker.speak(e.start())
        engine = e
        update()
        updateActivity(force: true)
    }

    /// Looptijd zonder pauzes.
    private func currentElapsed() -> TimeInterval {
        guard let s = startDate else { return 0 }
        return (pausedAt ?? Date()).timeIntervalSince(s)
    }

    private func update() {
        guard phase == .running, !paused, var e = engine else { return }
        let now = currentElapsed()
        elapsed = now
        currentPace = Format.rollingPace(samples: samples, now: now)

        let out = e.update(elapsed: now, distance: distance, pace: currentPace)
        engine = e
        results.append(contentsOf: out.finishedSegments)

        if out.workoutFinished {
            finish(spoken: "Test klaar. Je liep \(Format.spokenDistance(distance)) in \(Format.spokenDuration(now)).")
            return
        }
        out.cues.forEach { speaker.speak($0) }
        segmentTitle = e.title(for: e.index)
        segmentRemaining = e.remaining(elapsed: now)
        canSkip = e.canSkip
        // Bij een nieuw blok meteen bijwerken, anders hooguit om de 5 seconden.
        updateActivity(force: !out.finishedSegments.isEmpty)
    }

    private func finish(spoken: String) {
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        bgActivity?.invalidate()
        bgActivity = nil
        if let since = bgEnteredAt {
            backgroundSeconds += Date().timeIntervalSince(since)
            bgEnteredAt = Date()
        }
        speaker.speak(spoken)
        paused = false
        pausedAt = nil
        phase = .finished
        endActivity(immediately: false)
        RunControlCenter.handler = nil
    }

    private func resetState() {
        timer?.invalidate()
        timer = nil
        engine = nil
        startDate = nil
        pausedAt = nil
        paused = false
        canSkip = false
        elapsed = 0
        distance = 0
        currentPace = nil
        segmentTitle = ""
        segmentRemaining = nil
        route = []
        results = []
        log = []
        samples = []
        lastLocation = nil
        lastPointTime = nil
        pointsTotal = 0
        pointsBackground = 0
        maxGap = 0
        backgroundSeconds = 0
        bgEnteredAt = UIApplication.shared.applicationState == .background ? Date() : nil
    }

    // MARK: - Achtergrond meten

    @objc private func didEnterBackground() {
        bgEnteredAt = Date()
        if phase == .running || phase == .countdown { addLog("App naar achtergrond (scherm uit / andere app)") }
    }

    @objc private func willEnterForeground() {
        if let since = bgEnteredAt, phase == .running || phase == .countdown {
            let secs = Date().timeIntervalSince(since)
            backgroundSeconds += secs
            addLog("Terug op voorgrond na \(Int(secs)) s")
        }
        bgEnteredAt = nil
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

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        addLog("GPS-fout: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations { handle(loc) }
        if phase == .running && !paused { update() }
    }

    private func handle(_ loc: CLLocation) {
        guard phase == .running || phase == .countdown else { return }
        gpsAccuracy = loc.horizontalAccuracy
        // Slechte of verouderde punten negeren.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30,
              abs(loc.timestamp.timeIntervalSinceNow) < 10 else { return }

        guard phase == .running else {   // tijdens aftellen enkel opwarmen
            lastLocation = loc
            return
        }
        guard !paused else { return }   // tijdens een pauze niets meten

        pointsTotal += 1
        if UIApplication.shared.applicationState == .background { pointsBackground += 1 }
        if let lp = lastPointTime {
            maxGap = max(maxGap, loc.timestamp.timeIntervalSince(lp))
        }
        lastPointTime = loc.timestamp

        if let last = lastLocation {
            let d = loc.distance(from: last)
            let dt = max(loc.timestamp.timeIntervalSince(last.timestamp), 0.5)
            guard d / dt < 12 else {  // sprongen sneller dan 43 km/u zijn GPS-ruis
                addLog("GPS-sprong genegeerd (\(Int(d)) m)")
                return
            }
            distance += d
        }
        lastLocation = loc
        route.append(loc.coordinate)
        samples.append((t: currentElapsed(), d: distance))
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            addLog("Live Activities staan uit (Instellingen › Runner › Live Activities)")
            return
        }
        do {
            activity = try Activity.request(
                attributes: RunActivityAttributes(workoutName: planName),
                content: ActivityContent(state: activityState(), staleDate: nil),
                pushType: nil)
            addLog("Live Activity gestart")
        } catch {
            addLog("Live Activity mislukt: \(error.localizedDescription)")
        }
    }

    private func updateActivity(force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = now
        let content = ActivityContent(state: activityState(), staleDate: nil)
        Task { await activity.update(content) }
    }

    /// Op het einde blijft de samenvatting nog 15 minuten op het vergrendelscherm staan.
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
        let e = engine
        let remaining = e?.remaining(elapsed: run)

        var title = e.map { $0.label(for: $0.index) } ?? planName.uppercased()
        var blockEnd: Date? = nil
        var runStart = startDate ?? now
        if phase == .countdown {
            // Tijdens het aftellen telt de klok af naar de start.
            title = "START OVER"
            blockEnd = now.addingTimeInterval(TimeInterval(max(countdownLeft, 0)))
            runStart = blockEnd ?? now
        } else if !paused, let remaining {
            blockEnd = now.addingTimeInterval(remaining)
        }

        return RunActivityAttributes.ContentState(
            blockTitle: title,
            nextTitle: phase == .countdown ? e.map { "Eerst: " + $0.label(for: 0).lowercased() } : e?.nextText,
            blockEnd: blockEnd,
            blockRemainingText: remaining.map { Format.clock($0) },
            runStart: runStart,
            elapsedText: Format.clock(run),
            distanceText: Format.km(distance),
            paceText: Format.paceShort(currentPace),
            paused: paused,
            finished: phase == .finished,
            canSkip: phase == .running && !paused && (e?.canSkip ?? false))
    }

    // MARK: - Log

    private func addLog(_ s: String) {
        let t = Format.clock(currentElapsed())
        log.append("[\(t)] \(s)")
    }
}
