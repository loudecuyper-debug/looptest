import Foundation
import LoopCore

// Plan-preview: drukt een leesbaar overzicht af in Markdown.
// GitHub Actions toont dit op de pagina van de run (Summary), zodat je
// de logica kan nalezen zonder iets op je iPhone te installeren.

struct TestProfile {
    let name: String
    let distance: Double
    let time: TimeInterval
}

let profile = TestProfile(name: "Louis", distance: 5_000, time: 25 * 60)

var out = ""
func line(_ s: String = "") { out += s + "\n" }

line("# LoopCore plan-preview")
line()

guard let zones = PaceZones(distance: profile.distance, time: profile.time) else {
    line("Ongeldig testprofiel.")
    print(out)
    exit(1)
}

line("## Testprofiel: \(profile.name)")
line("Recente prestatie: \(TimeText.distance(profile.distance)) in \(TimeText.clock(profile.time))")
line()
line("**VDOT: \(String(format: "%.1f", zones.vdot).replacingOccurrences(of: ".", with: ","))**")
line()

line("## Tempozones")
line("| Zone | Tempo | Mikpunt | Wat |")
line("|---|---|---|---|")
for zone in PaceZone.allCases {
    let r = zones.range(for: zone)
    line("| \(zone.name) | \(TimeText.range(r)) | \(TimeText.pace(r.target)) | \(zone.explanation) |")
}
line()

line("## Voorspelde wedstrijdtijden")
line("| Afstand | Tijd | Tempo |")
line("|---|---|---|")
for d in [1_500.0, 5_000, 10_000, 15_000, 21_097.5, 42_195] {
    line("| \(TimeText.distance(d)) | \(TimeText.clock(zones.predictedTime(distance: d))) | \(TimeText.pace(zones.racePace(distance: d))) |")
}
line()

line("## Wat levert vooruitgang op voor de 10 km?")
line("| VDOT | 10 km | 10 km-tempo |")
line("|---|---|---|")
for delta in stride(from: 0.0, through: 6.0, by: 1.0) {
    let z = zones.adjusted(byVdot: delta)
    let label = String(format: "%.1f", z.vdot).replacingOccurrences(of: ".", with: ",")
    line("| \(label)\(delta > 0 ? " (+\(Int(delta)))" : "") | \(TimeText.clock(z.predictedTime(distance: 10_000))) | \(TimeText.pace(z.racePace(distance: 10_000))) |")
}
line()

print(out)
