import SwiftUI
import MapKit
import LoopCore

/// Routekaart: al je gelopen routes, of zelf een route plannen.
struct RoutesMapView: View {
    enum Mode: Hashable { case done, plan }

    @EnvironmentObject var model: AppModel
    @State private var mode: Mode = .done
    @State private var camera: MapCameraPosition = .automatic

    // Gelopen
    @State private var runs: [RunLine] = []
    @State private var filter: RunFilter = .all
    @State private var selectedRun: UUID?

    // Plannen
    @StateObject private var planner = RoutePlanner()
    @State private var naming = false
    @State private var newName = ""
    @State private var deleting: PlannedRoute?

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if mode == .done {
                    ForEach(visibleRuns) { run in
                        MapPolyline(coordinates: run.coordinates)
                            .stroke(Theme.accent.opacity(selectedRun == nil ? 0.55 : 0.25),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    if let run = visibleRuns.first(where: { $0.id == selectedRun }) {
                        MapPolyline(coordinates: run.coordinates)
                            .stroke(Theme.text, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                } else {
                    if planner.coordinates.count > 1 {
                        MapPolyline(coordinates: planner.coordinates)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(planner.waypoints.enumerated()), id: \.offset) { i, p in
                        Annotation("", coordinate: p, anchor: .center) {
                            Circle()
                                .fill(i == 0 ? Theme.text : Theme.accent)
                                .frame(width: i == 0 ? 16 : 10, height: i == 0 ? 16 : 10)
                                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 3))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                if mode == .plan {
                    planner.add(coordinate)
                } else {
                    selectRun(near: coordinate, tapPoint: point, proxy: proxy)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Segmented(options: [(Mode.done, "Gelopen"), (Mode.plan, "Plannen")], selection: $mode, height: 32)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 8)
                .background(Theme.background.opacity(0.92))
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if mode == .done { donePanel } else { planPanel }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 10)
        }
        .screenTitle("Routekaart")
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if runs.isEmpty { runs = model.gpsRuns().map(RunLine.init) }
            if visibleRuns.isEmpty { camera = .userLocation(fallback: .automatic) }
        }
        .onChange(of: mode) { _, _ in
            selectedRun = nil
            camera = (mode == .done && !visibleRuns.isEmpty) ? .automatic : .userLocation(fallback: .automatic)
        }
        .onChange(of: filter) { _, _ in
            selectedRun = nil
            camera = .automatic
        }
        .alert("Route bewaren", isPresented: $naming) {
            TextField("Naam", text: $newName)
            Button("Bewaren") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let route = planner.makeRoute(name: name.isEmpty ? defaultName : name) {
                    model.savePlannedRoute(route)
                    planner.loadedID = route.id
                }
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("\(Fmt.decimal(planner.distance / 1000, digits: 2)) km")
        }
        .confirmationDialog("Route verwijderen?", isPresented: Binding(present: $deleting), titleVisibility: .visible,
                            presenting: deleting) { route in
            Button("Verwijderen", role: .destructive) {
                model.deletePlannedRoute(id: route.id)
                if planner.loadedID == route.id { planner.clear() }
            }
            Button("Annuleren", role: .cancel) {}
        } message: { route in
            Text("\(route.name) wordt verwijderd.")
        }
    }

    // MARK: - Gelopen

    private var visibleRuns: [RunLine] {
        let cal = model.calendar
        let now = Date()
        return runs.filter { run in
            switch filter {
            case .all: return true
            case .year: return cal.isDate(run.date, equalTo: now, toGranularity: .year)
            case .month: return cal.isDate(run.date, equalTo: now, toGranularity: .month)
            }
        }
    }

    private var donePanel: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if let run = visibleRuns.first(where: { $0.id == selectedRun }) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.title).font(.system(size: 16, weight: .heavy))
                            Text(DateText.withYear(run.date))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button {
                            selectedRun = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sluiten")
                    }
                    HStack {
                        StatBlock(label: "Afstand", value: Fmt.km2(run.distance), size: 17)
                        StatBlock(label: "Tijd", value: TimeText.clock(run.duration), size: 17)
                        StatBlock(label: "Tempo", value: run.distance > 100 ? TimeText.clock(run.duration / run.distance * 1000) : "-:--", size: 17)
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(RunFilter.allCases, id: \.self) { f in
                            Chip(title: f.title, selected: filter == f, height: 34) { filter = f }
                        }
                    }
                    Text(summaryText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Theme.text)
        }
    }

    private var summaryText: String {
        let list = visibleRuns
        guard !list.isEmpty else {
            return runs.isEmpty
                ? "Je gelopen routes verschijnen hier na je eerste loop met GPS."
                : "Geen routes in deze periode."
        }
        let km = list.reduce(0.0) { $0 + $1.distance } / 1000
        return "\(list.count) \(list.count == 1 ? "route" : "routes") · \(Fmt.decimal(km)) km · tik op een route voor details"
    }

    /// Kiest de route die het dichtst bij de tik ligt, binnen ongeveer 24 punten op het scherm.
    private func selectRun(near c: CLLocationCoordinate2D, tapPoint: CGPoint, proxy: MapProxy) {
        var tolerance = 60.0
        if let edge = proxy.convert(CGPoint(x: tapPoint.x + 24, y: tapPoint.y), from: .local) {
            tolerance = RouteGeometry.distance(c.latitude, c.longitude, edge.latitude, edge.longitude)
        }
        let best = visibleRuns
            .map { ($0.id, RouteGeometry.distanceToLine(lat: c.latitude, lon: c.longitude,
                                                       latitudes: $0.latitudes, longitudes: $0.longitudes)) }
            .min { $0.1 < $1.1 }
        if let best, best.1 <= tolerance {
            selectedRun = best.0
        } else {
            selectedRun = nil
        }
    }

    // MARK: - Plannen

    private var defaultName: String {
        "Route \(Fmt.decimal(planner.distance / 1000)) km"
    }

    private var planPanel: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                if planner.waypoints.isEmpty {
                    Text("Tik op de kaart om je startpunt te kiezen, en daarna op de plekken waar je langs wil.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        StatBlock(label: "Afstand", value: "\(Fmt.decimal(planner.distance / 1000, digits: 2)) km", size: 24)
                        if let pace = model.easyPace, planner.distance > 0 {
                            StatBlock(label: "Rustig", value: Fmt.minutes(planner.distance / 1000 * pace), size: 17)
                        }
                        if planner.busy {
                            ProgressView().tint(Theme.secondary)
                        }
                    }
                    if let note = planner.note {
                        Text(note)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                    }
                    HStack(spacing: 8) {
                        Button { planner.undo() } label: { Label("Terug", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(SecondaryButtonStyle(height: 40))
                        Button { planner.closeLoop() } label: { Label("Naar start", systemImage: "arrow.triangle.turn.up.right.circle") }
                            .buttonStyle(SecondaryButtonStyle(height: 40))
                            .disabled(planner.waypoints.count < 2 || planner.isLoop)
                        Button { planner.clear() } label: { Image(systemName: "trash") }
                            .buttonStyle(SecondaryButtonStyle(height: 40))
                            .frame(width: 52)
                            .accessibilityLabel("Wissen")
                    }
                    Button("Route bewaren") {
                        newName = ""
                        naming = true
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                    .disabled(planner.coordinates.count < 2 || planner.busy)
                }

                if !model.plannedRoutes.isEmpty {
                    SectionLabel("Bewaarde routes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.plannedRoutes) { route in
                                Button {
                                    planner.load(route)
                                    camera = .automatic
                                } label: {
                                    Text("\(route.name) · \(Fmt.decimal(route.distance / 1000)) km")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(planner.loadedID == route.id ? Theme.background : Theme.text)
                                        .padding(.horizontal, 12)
                                        .frame(height: 32)
                                        .background(planner.loadedID == route.id ? Theme.text : Theme.sunken, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Verwijderen", role: .destructive) { deleting = route }
                                }
                            }
                        }
                    }
                }
            }
            .foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Gelopen route

enum RunFilter: CaseIterable {
    case all, year, month

    var title: String {
        switch self {
        case .all: return "Alles"
        case .year: return "Dit jaar"
        case .month: return "Deze maand"
        }
    }
}

/// Een gelopen route, uitgedund om vlot te tekenen.
struct RunLine: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let distance: Double
    let duration: TimeInterval
    let latitudes: [Double]
    let longitudes: [Double]
    let coordinates: [CLLocationCoordinate2D]

    init(_ run: CompletedRun) {
        id = run.id
        date = run.date
        title = run.workout?.title ?? "Vrije loop"
        distance = run.distance
        duration = run.duration
        let thin = RouteGeometry.thin(latitudes: run.route.latitudes, longitudes: run.route.longitudes, minSpacing: 8)
        latitudes = thin.latitudes
        longitudes = thin.longitudes
        coordinates = zip(thin.latitudes, thin.longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
}

// MARK: - Planner

/// Houdt de aangetikte punten bij en vraagt per stuk een wandelroute langs straten en paden aan Apple Kaarten.
/// Lukt dat niet (geen netwerk), dan wordt dat stuk een rechte lijn.
@MainActor
final class RoutePlanner: ObservableObject {
    @Published private(set) var waypoints: [CLLocationCoordinate2D] = []
    /// Stuk i loopt van punt i naar punt i + 1.
    @Published private(set) var legs: [[CLLocationCoordinate2D]] = []
    @Published private(set) var busy = false
    @Published private(set) var note: String?
    @Published var loadedID: UUID?

    private var generation = 0

    var coordinates: [CLLocationCoordinate2D] {
        guard let first = waypoints.first else { return [] }
        var all = [first]
        for leg in legs { all.append(contentsOf: leg.dropFirst()) }
        return all
    }

    var distance: Double {
        let c = coordinates
        return RouteGeometry.length(latitudes: c.map(\.latitude), longitudes: c.map(\.longitude))
    }

    var isLoop: Bool {
        guard waypoints.count > 2, let a = waypoints.first, let b = waypoints.last else { return false }
        return RouteGeometry.distance(a.latitude, a.longitude, b.latitude, b.longitude) < 1
    }

    func add(_ point: CLLocationCoordinate2D) {
        loadedID = nil
        guard let last = waypoints.last else {
            waypoints = [point]
            return
        }
        waypoints.append(point)
        let index = legs.count
        legs.append([last, point])   // rechte lijn tot de echte route binnen is
        route(index, from: last, to: point)
    }

    func closeLoop() {
        guard waypoints.count >= 2, !isLoop, let start = waypoints.first else { return }
        add(start)
    }

    func undo() {
        loadedID = nil
        generation += 1   // lopende aanvragen negeren
        busy = false
        if !legs.isEmpty { legs.removeLast() }
        if !waypoints.isEmpty { waypoints.removeLast() }
        if waypoints.count <= 1 { legs = [] }
    }

    func clear() {
        generation += 1
        waypoints = []
        legs = []
        busy = false
        note = nil
        loadedID = nil
    }

    /// Een bewaarde route tonen. Verder bewerken begint van het laatste punt.
    func load(_ route: PlannedRoute) {
        clear()
        let pts = zip(route.latitudes, route.longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        guard let first = pts.first, let last = pts.last else { return }
        waypoints = [first, last]
        legs = [pts]
        loadedID = route.id
    }

    func makeRoute(name: String) -> PlannedRoute? {
        let c = coordinates
        guard c.count > 1 else { return nil }
        let thin = RouteGeometry.thin(latitudes: c.map(\.latitude), longitudes: c.map(\.longitude), minSpacing: 5)
        return PlannedRoute(id: loadedID ?? UUID(), name: name, latitudes: thin.latitudes,
                            longitudes: thin.longitudes, isLoop: isLoop)
    }

    private func route(_ index: Int, from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) {
        let token = generation
        busy = true
        Task { @MainActor in
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            request.transportType = .walking
            do {
                let response = try await MKDirections(request: request).calculate()
                guard token == generation, index < legs.count else { return }
                if let polyline = response.routes.first?.polyline {
                    var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                          count: polyline.pointCount)
                    polyline.getCoordinates(&points, range: NSRange(location: 0, length: polyline.pointCount))
                    // Begin en einde exact op de aangetikte punten, zodat de stukken aansluiten.
                    legs[index] = [a] + points + [b]
                    note = nil
                }
            } catch {
                guard token == generation else { return }
                note = "Geen route gevonden langs straten; dat stuk is een rechte lijn."
            }
            if token == generation { busy = false }
        }
    }
}
