import SwiftUI
import Charts
import LoopCore

struct VoortgangView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false
    @State private var deleting: RunSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let plan = model.plan { volumeCard(plan) }
                    mapCard
                    recordsCard
                    runsCard
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 8)
            }
            .screenTitle("Voortgang")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                    }
                    .accessibilityLabel("Loop toevoegen")
                }
            }
            .sheet(isPresented: $showAdd) { ManualRunSheet() }
            .confirmationDialog("Loop verwijderen?", isPresented: Binding(present: $deleting), titleVisibility: .visible,
                                presenting: deleting) { run in
                Button("Verwijderen", role: .destructive) { model.deleteRun(id: run.id) }
                Button("Annuleren", role: .cancel) {}
            } message: { run in
                Text("\(run.title) van \(DateText.short(run.date)) wordt definitief verwijderd.")
            }
        }
    }

    // MARK: - Routekaart

    private var mapCard: some View {
        let gps = model.runs.filter { $0.source == .gps }.count
        let saved = model.plannedRoutes.count
        return NavigationLink {
            RoutesMapView()
        } label: {
            Card(padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "map")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 42)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Routekaart").font(.system(size: 16, weight: .heavy))
                        Text("\(gps) gelopen \(gps == 1 ? "route" : "routes") · \(saved) bewaard · route plannen")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weekvolume

    private func volumeCard(_ plan: TrainingPlan) -> some View {
        let volumes = Stats.weeklyVolumes(plan: plan, runs: model.runs, calendar: model.calendar)

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Kilometers per week", color: Theme.muted)
                Chart {
                    ForEach(Array(volumes.enumerated()), id: \.offset) { i, v in
                        BarMark(x: .value("Week", i + 1),
                                yStart: .value("Gepland", 0),
                                yEnd: .value("Gepland", v.plannedKm),
                                width: .fixed(14))
                            .foregroundStyle(Theme.track)
                            .cornerRadius(3)
                        BarMark(x: .value("Week", i + 1),
                                yStart: .value("Gelopen", 0),
                                yEnd: .value("Gelopen", v.doneKm),
                                width: .fixed(8))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel().foregroundStyle(Theme.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.cardBorder)
                        AxisValueLabel().foregroundStyle(Theme.secondary)
                    }
                }
                .frame(height: 170)
                .accessibilityLabel("Gepland en gelopen per week")
                HStack(spacing: 16) {
                    legend(Theme.track, "Gepland")
                    legend(Theme.accent, "Gelopen")
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: - Records

    private var recordsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Persoonlijke records", color: Theme.muted).padding(.bottom, 8)
                if model.records.isEmpty {
                    Text("Records verschijnen zodra je loopjes met GPS gelopen hebt.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.records, id: \.label) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(.system(size: 15, weight: .semibold))
                                Text(DateText.withYear(r.date))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text(r.label == "Langste loop" ? Fmt.km2(r.distance) : TimeText.clock(r.time))
                                .font(.system(size: 16, weight: .heavy))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - Loopjes

    private var runsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Alle loopjes", color: Theme.muted).padding(.bottom, 8)
                if model.runs.isEmpty {
                    Text("Nog geen loopjes. Voeg een loop toe met + rechtsboven.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.runs) { run in
                        NavigationLink {
                            RunPager(start: run.id)
                        } label: {
                            runRow(run)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Tik op een loop voor alle details. Lang drukken om te verwijderen.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func runRow(_ run: RunSummary) -> some View {
        let pace = run.distance >= 100 ? run.duration / run.distance * 1000 : nil

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(run.type?.color ?? Theme.outline)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title).font(.system(size: 15, weight: .bold))
                Text("\(DateText.short(run.date))\(run.source == .manual ? " · manueel" : "")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.km2(run.distance)).font(.system(size: 15, weight: .heavy)).monospacedDigit()
                Text("\(TimeText.clock(run.duration))\(pace.map { " · " + TimeText.pace($0) } ?? "")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                deleting = run
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Een loop achteraf toevoegen (gsm vergeten, loopband).
struct ManualRunSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var km: Double = 5
    @State private var hours = 0
    @State private var minutes = 30
    @State private var seconds = 0
    @State private var rpe = 5
    @State private var pain = false
    @State private var note = ""
    @State private var link = true

    private var duration: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }
    private var valid: Bool { km > 0 && duration > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, in: ...Date())
                        .environment(\.locale, Locale(identifier: "nl_BE"))
                    HStack {
                        Text("Afstand")
                        Spacer()
                        TextField("km", value: $km, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("km").foregroundStyle(Theme.secondary)
                    }
                    HStack {
                        Text("Tijd")
                        Spacer()
                        timeField($hours, "u")
                        timeField($minutes, "min")
                        timeField($seconds, "s")
                    }
                }
                .listRowBackground(Theme.card)

                if let planned = model.openWorkout(on: date) {
                    Section {
                        Toggle(isOn: $link) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Telt als geplande workout")
                                Text(planned.workout.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        .toggleStyle(LoopToggleStyle())
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Stepper(value: $rpe, in: 1...10) {
                        HStack {
                            Text("Zwaarte")
                            Spacer()
                            Text("\(rpe)/10").monospacedDigit().foregroundStyle(Theme.secondary)
                        }
                    }
                    Toggle("Pijn of klachten", isOn: $pain)
                        .toggleStyle(LoopToggleStyle())
                    TextField("Notitie (optioneel)", text: $note, axis: .vertical)
                } header: {
                    Text("Hoe ging het")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Loop toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaren") {
                        model.addManualRun(date: date, distanceKm: km, duration: duration, rpe: rpe, pain: pain,
                                           note: note.isEmpty ? nil : note, linkToPlan: link)
                        dismiss()
                    }
                    .bold()
                    .disabled(!valid)
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private func timeField(_ value: Binding<Int>, _ unit: String) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
                .monospacedDigit()
            Text(unit).foregroundStyle(Theme.secondary)
        }
    }
}
