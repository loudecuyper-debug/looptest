import SwiftUI
import MapKit

struct ResultView: View {
    @EnvironmentObject var session: RunSession

    var body: some View {
        NavigationStack {
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

                Section("Diagnose proof of concept") {
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
            .navigationTitle(session.planName)
        }
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
        return Label(text, systemImage: ok == nil ? "questionmark.circle" : (ok! ? "checkmark.circle.fill" : "xmark.octagon.fill"))
            .foregroundStyle(ok == nil ? Color.yellow : (ok! ? Color.green : Color.red))
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
