import Foundation
import LoopCore

// Plan-preview: drukt een leesbaar overzicht af in Markdown.
// GitHub Actions toont dit op de pagina van de run (Summary), zodat je
// de logica kan nalezen zonder iets op je iPhone te installeren.

var out = ""
func line(_ s: String = "") { out += s + "\n" }
func km(_ meters: Double) -> String {
    String(format: "%.1f", meters / 1000).replacingOccurrences(of: ".", with: ",")
}

var calendar = Calendar(identifier: .iso8601)
calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
let dateFormatter = DateFormatter()
dateFormatter.calendar = calendar
dateFormatter.timeZone = calendar.timeZone
dateFormatter.dateFormat = "dd/MM"

// Testprofiel Louis. Wordt in de app zelf ingevuld bij het maken van een plan.
let startDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)) ?? Date()
let input = PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12, startDate: startDate,
                      recentDistance: 5_000, recentTime: 25 * 60,
                      weeklyVolumeKm: 15, longestRunKm: 8,
                      runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday)

guard let plan = PlanGenerator.generate(input, calendar: calendar) else {
    print("Ongeldig testprofiel.")
    exit(1)
}
let zones = plan.zones

line("# LoopCore plan-preview")
line()
line("**Testprofiel:** 5 km in 25:00, ~15 km per week, langste loop 8 km, loopt op "
     + input.runDays.map(\.name).joined(separator: ", ") + ". Doel: snellere 10 km in \(input.weeks) weken.")
line()
line("**VDOT: \(String(format: "%.1f", zones.vdot).replacingOccurrences(of: ".", with: ","))** · voorspelde 10 km nu: \(TimeText.clock(zones.predictedTime(distance: 10_000)))")
line()

line("## Tempozones")
line("| Zone | Tempo | Mikpunt | Wat |")
line("|---|---|---|---|")
for zone in PaceZone.allCases {
    let r = zones.range(for: zone)
    line("| \(zone.name) | \(TimeText.range(r)) | \(TimeText.pace(r.target)) | \(zone.explanation) |")
}
line()

line("## Plan")
for week in plan.weeks {
    let total = week.estimatedDistance(zones: zones)
    let label = week.isRecoveryWeek ? "\(week.phase.name) · rustweek" : week.phase.name
    line("### Week \(week.number) (\(dateFormatter.string(from: week.startDate))) · \(label) · \(km(total)) km")
    line("| Dag | Workout | Inhoud | Km | Duur |")
    line("|---|---|---|---|---|")
    for w in week.workouts {
        line("| \(w.day.short) \(dateFormatter.string(from: week.date(for: w.day, calendar: calendar))) | \(w.title) | \(WorkoutText.describe(w, zones: zones)) | \(km(w.estimatedDistance(zones: zones))) | \(TimeText.clock(w.estimatedDuration(zones: zones))) |")
    }
    line()
}

line("## Voorbeeld: extra loop in week 6")
let week6 = plan.weeks[5]
let extraDay = Weekday.monday
let withExtra = ExtraRun.adding(to: week6, on: extraDay)
line("Vrije dagen: " + ExtraRun.freeDays(in: week6).map(\.short).joined(separator: ", ")
     + ". Extra loop op \(extraDay.name): \(km(ExtraRun.suggestedKm(in: week6) * 1000)) km rustig.")
line()
line("Week 6 wordt \(km(withExtra.estimatedDistance(zones: zones))) km, maar voor de opbouw telt nog steeds \(km(withExtra.estimatedDistance(zones: zones, includeExtra: false))) km.")
line()
if let warning = ExtraRun.warning(for: .saturday, in: week6) {
    line("Kies je zaterdag, dan zegt de app: *\(warning)*")
    line()
}

line("## Ter vergelijking: 4 loopdagen (di, do, vr, zo)")
var four = input
four.runDays = [.tuesday, .thursday, .friday, .sunday]
if let plan4 = PlanGenerator.generate(four, calendar: calendar) {
    line("| Week | Fase | Km | Workouts |")
    line("|---|---|---|---|")
    for week in plan4.weeks {
        let titles = week.workouts.map { "\($0.day.short): \($0.title)" }.joined(separator: ", ")
        line("| \(week.number) | \(week.phase.name)\(week.isRecoveryWeek ? " (rust)" : "") | \(km(week.estimatedDistance(zones: plan4.zones))) | \(titles) |")
    }
}
line()

print(out)
