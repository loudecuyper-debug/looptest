import SwiftUI
import MapKit

// Proof of concept: GPS met scherm uit en Nederlandse cues over muziek testen.
// Bereikbaar via Instellingen › Diagnose.

struct DebugRunScreen: View {
    @StateObject private var session = RunSession()

    var body: some View {
        Group {
            switch session.phase {
            case .idle: DebugStartView()
            case .countdown, .running: DebugLiveView()
            case .finished: DebugResultView()
            }
        }
        .environmentObject(session)
        .tint(.orange)
        .toolbar(session.phase == .idle ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Start

struct DebugStartView: View {
    @EnvironmentObject var session: RunSession

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("GPS en stem testen")
                .font(.system(size: 34, weight: .heavy))
            Text("Test of GPS doorloopt met je scherm uit en of de cues goed klinken over je muziek.")
                .foregroundStyle(Theme.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Zet eerst Spotify of Apple Music aan", systemImage: "music.note")
                Label("Start, vergrendel je scherm, steek je gsm weg", systemImage: "lock.fill")
                Label("Bekijk na afloop de diagnose", systemImage: "checkmark.seal")
            }
            .font(.callout)

            if let problem = session.authProblem {
                Text(problem)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                session.start(.intervalTest)
            } label: {
                VStack(spacing: 2) {
                    Text("Start intervaltest").font(.title3.bold())
                    Text("3 × (1 min snel + 1 min wandelen)").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Button {
                session.start(.freeRun)
            } label: {
                VStack(spacing: 2) {
                    Text("Vrij lopen").font(.title3.bold())
                    Text("Cue elke kilometer, stop wanneer je wil").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }
}

// MARK: - Live

struct DebugLiveView: View {
    @EnvironmentObject var session: RunSession
    @State private var confirmStop = false

    var body: some View {
        VStack(spacing: 28) {
            if session.phase == .countdown {
                Spacer()
                Text("Start over").foregroundStyle(Theme.secondary)
                Text("\(max(session.countdownLeft, 0))")
                    .font(.system(size: 120, weight: .heavy))
                    .monospacedDigit()
                gpsBadge
                Spacer()
            } else {
                Text(session.segmentTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)

                Text(session.segmentRemaining.map { Format.clock($0) } ?? Format.clock(session.elapsed))
                    .font(.system(size: 96, weight: .heavy))
                    .monospacedDigit()

                HStack {
                    stat("Afstand", Format.km(session.distance))
                    stat("Tempo", Format.paceShort(session.currentPace))
                    stat("Totaal", Format.clock(session.elapsed))
                }
                gpsBadge
                Spacer()
            }

            Button(role: .destructive) {
                confirmStop = true
            } label: {
                Text("Stop").font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Test stoppen?", isPresented: $confirmStop) {
                Button("Stoppen", role: .destructive) { session.stopEarly() }
            }
        }
        .padding(24)
    }

    private var gpsBadge: some View {
        let acc = session.gpsAccuracy
        let good = acc.map { $0 >= 0 && $0 <= 20 } ?? false
        return Label(acc.map { "GPS ±\(Int($0)) m" } ?? "GPS zoeken…",
                     systemImage: good ? "location.fill" : "location.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(good ? Color.green : Color.yellow)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Resultaat

struct DebugResultView: View {
    @EnvironmentObject var session: RunSession

    var body: some View {
        List {
            if session.route.count > 1 {
                Section {
                    Map(initialPosition: .automatic) {
                        MapPolyline(coordinates: session.route)
                            .stroke(.orange, lineWidth: 5)
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Samenvatting") {
                row("Afstand", Format.km(session.distance))
                row("Tijd", Format.clock(session.elapsed))
                row("Gem. tempo", Format.paceShort(Format.pace(duration: session.elapsed, distance: session.distance)))
            }

            if !session.results.isEmpty {
                Section("Per blok") {
                    ForEach(session.results) { r in
                        HStack {
                            Text(r.title)
                            Spacer()
                            Text("\(Int(r.distance)) m · \(Format.paceShort(r.pace))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Diagnose") {
                verdictRow
                row("GPS-punten totaal", "\(session.pointsTotal)")
                row("Punten met scherm uit", "\(session.pointsBackground)")
                row("Tijd op achtergrond", "\(Int(session.backgroundSeconds)) s")
                row("Grootste GPS-gat", String(format: "%.1f s", session.maxGap))
                row("Stem", session.voiceDescription)
            }

            Section("Logboek") {
                ForEach(Array(session.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }

            Section {
                Button("Nieuwe test") { session.reset() }
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var verdictRow: some View {
        let bg = session.backgroundSeconds
        let text: String
        let ok: Bool?
        if bg < 20 {
            text = "Scherm was (bijna) niet uit, achtergrond niet getest"
            ok = nil
        } else if session.pointsBackground > 0 && session.maxGap < 10 {
            text = "GPS liep door met scherm uit"
            ok = true
        } else {
            text = "GPS haperde met scherm uit"
            ok = false
        }
        let icon = ok == nil ? "questionmark.circle" : (ok == true ? "checkmark.circle.fill" : "xmark.octagon.fill")
        let color: Color = ok == nil ? .yellow : (ok == true ? .green : .red)
        return Label(text, systemImage: icon)
            .foregroundStyle(color)
            .font(.body.weight(.semibold))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
