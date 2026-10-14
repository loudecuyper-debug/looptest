import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: RunSession

    var body: some View {
        switch session.phase {
        case .idle: StartView()
        case .countdown, .running: LiveView()
        case .finished: ResultView()
        }
    }
}

// MARK: - Start

struct StartView: View {
    @EnvironmentObject var session: RunSession

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("LoopTest")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
            Text("Proof of concept: GPS met scherm uit en Nederlandse cues over je muziek.")
                .foregroundStyle(.secondary)

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

struct LiveView: View {
    @EnvironmentObject var session: RunSession
    @State private var confirmStop = false

    var body: some View {
        VStack(spacing: 28) {
            if session.phase == .countdown {
                Spacer()
                Text("Start over").foregroundStyle(.secondary)
                Text("\(max(session.countdownLeft, 0))")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                gpsBadge
                Spacer()
            } else {
                Text(session.segmentTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)

                Text(session.segmentRemaining.map { Format.clock($0) } ?? Format.clock(session.elapsed))
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
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
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
