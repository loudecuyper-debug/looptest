import Foundation
import WidgetKit
import LoopCore

extension AppModel {
    /// Zoveel dagen vooruit krijgt de widget. De app vult dit telkens opnieuw aan.
    static let widgetDays = 15

    /// Schrijft wat de widget "training van vandaag" toont en laat hem opnieuw tekenen (27 okt).
    /// Na elke planwijziging, na het bewaren of verwijderen van een loop en bij elke terugkeer naar de app.
    func updateWidget(now: Date = Date()) {
        guard WidgetShare.isAvailable else { return }
        guard let plan else {
            WidgetShare.write(nil)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.kind)
            return
        }
        let cal = calendar
        let today = cal.startOfDay(for: now)
        var days: [WidgetSnapshot.Day] = []
        var weeks: [WidgetSnapshot.Week] = []

        for offset in 0..<Self.widgetDays {
            guard let date = cal.date(byAdding: .day, value: offset, to: today),
                  let day = planDay(for: date), let planWeek = week(day) else { continue }
            if !weeks.contains(where: { $0.start == planWeek.startDate }) {
                let p = progress(of: planWeek)
                weeks.append(.init(start: planWeek.startDate, plannedKm: p.plannedKm, doneKm: p.doneKm))
            }
            guard let w = workout(at: day) else { continue }
            let zones = planWeek.zones
            days.append(.init(date: date, title: w.title, label: w.type.label, color: w.type.hex,
                              km: w.estimatedDistance(zones: zones) / 1000,
                              minutes: Int((w.estimatedDuration(zones: zones) / 60).rounded()),
                              done: run(for: day) != nil, extra: w.isExtra))
        }

        let firstWeek = plan.weeks.first(where: { !$0.workouts.isEmpty })
        let start = firstWeek.flatMap { w in w.workouts.first.map { w.date(for: $0.day, calendar: cal) } }
        let end = plan.weeks.last.flatMap { cal.date(byAdding: .day, value: 6, to: $0.startDate) }
        let snapshot = WidgetSnapshot(created: now, days: days, weeks: weeks, sick: isSick,
                                      planStart: start, planEnd: end)
        WidgetShare.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.kind)
    }
}
