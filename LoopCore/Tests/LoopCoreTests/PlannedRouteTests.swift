import XCTest
@testable import LoopCore

/// Geplande routes en het rekenwerk op routes. Verwachte waarden berekend met dezelfde formules in Python.
final class PlannedRouteTests: XCTestCase {

    private var tempDirs: [URL] = []

    override func tearDown() {
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        tempDirs = []
        super.tearDown()
    }

    private func makeStore() throws -> RunStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LoopCoreRoutes-\(UUID().uuidString)")
        tempDirs.append(dir)
        return try RunStore(directory: dir)
    }

    private func route(_ name: String, created: TimeInterval) -> PlannedRoute {
        PlannedRoute(name: name, created: Date(timeIntervalSince1970: created),
                     latitudes: [51.2, 51.201, 51.201], longitudes: [4.4, 4.4, 4.401])
    }

    // MARK: - Rekenwerk

    func testDistanceBetweenPoints() {
        XCTAssertEqual(RouteGeometry.distance(51.2, 4.4, 51.201, 4.4), 111.195, accuracy: 0.01)
        XCTAssertEqual(RouteGeometry.distance(51.2, 4.4, 51.2, 4.401), 69.675, accuracy: 0.01)
        XCTAssertEqual(RouteGeometry.distance(51.2, 4.4, 51.2, 4.4), 0, accuracy: 0.0001)
    }

    func testLengthAndRouteDistance() {
        let r = route("Rondje", created: 0)
        XCTAssertEqual(RouteGeometry.length(latitudes: r.latitudes, longitudes: r.longitudes), 180.869, accuracy: 0.01)
        XCTAssertEqual(r.distance, 180.869, accuracy: 0.01)
        XCTAssertEqual(RouteGeometry.length(latitudes: [51.2], longitudes: [4.4]), 0)
    }

    func testThinKeepsSpacingAndEnds() {
        // 11 punten om de ±11 m naar het noorden.
        let lats = (0...10).map { 51.2 + Double($0) * 0.0001 }
        let lons = Array(repeating: 4.4, count: 11)
        let thin = RouteGeometry.thin(latitudes: lats, longitudes: lons, minSpacing: 30)
        XCTAssertEqual(thin.latitudes, [lats[0], lats[3], lats[6], lats[9], lats[10]])
        XCTAssertEqual(thin.longitudes.count, 5)
        // Korte lijnen blijven ongemoeid.
        XCTAssertEqual(RouteGeometry.thin(latitudes: [1, 2], longitudes: [3, 4], minSpacing: 1000).latitudes, [1, 2])
    }

    func testDistanceToLine() {
        let lats = [51.2, 51.201], lons = [4.4, 4.4]
        // Naast het midden van de lijn: 0,001 graad oost.
        XCTAssertEqual(RouteGeometry.distanceToLine(lat: 51.2005, lon: 4.401, latitudes: lats, longitudes: lons),
                       69.67, accuracy: 0.5)
        // Voorbij het einde: afstand tot het eindpunt.
        XCTAssertEqual(RouteGeometry.distanceToLine(lat: 51.202, lon: 4.4, latitudes: lats, longitudes: lons),
                       111.2, accuracy: 0.5)
        // Op de lijn.
        XCTAssertEqual(RouteGeometry.distanceToLine(lat: 51.2005, lon: 4.4, latitudes: lats, longitudes: lons),
                       0, accuracy: 0.01)
        XCTAssertEqual(RouteGeometry.distanceToLine(lat: 0, lon: 0, latitudes: [], longitudes: []), .infinity)
    }

    // MARK: - Opslag en backup

    func testSaveOverwriteAndDelete() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.plannedRoutes(), [])
        var a = route("Kaai", created: 100)
        let b = route("Park", created: 200)
        try store.save(a)
        try store.save(b)
        XCTAssertEqual(try store.plannedRoutes().map(\.name), ["Park", "Kaai"])   // nieuwste eerst

        a.name = "Kaai lang"
        try store.save(a)
        XCTAssertEqual(try store.plannedRoutes().count, 2)
        XCTAssertEqual(try store.plannedRoutes().last?.name, "Kaai lang")

        try store.deletePlannedRoute(id: b.id)
        XCTAssertEqual(try store.plannedRoutes().map(\.name), ["Kaai lang"])
    }

    func testBackupIncludesPlannedRoutes() throws {
        let a = try makeStore()
        try a.save(route("Kaai", created: 100))
        try a.save(CompletedRun(date: Date(timeIntervalSince1970: 300), distance: 5000, duration: 1500))
        let data = try a.makeBackup()

        let b = try makeStore()
        try b.save(route("Wordt vervangen", created: 50))
        let restored = try b.restore(from: data)
        XCTAssertEqual(restored.plannedRoutes?.count, 1)
        XCTAssertEqual(try b.plannedRoutes(), try a.plannedRoutes())
    }

    func testOldBackupWithoutRoutesKeepsCurrentRoutes() throws {
        let old = Backup(createdAt: Date(timeIntervalSince1970: 0), coach: nil, runs: [])
        let data = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("plannedRoutes"))

        let store = try makeStore()
        try store.save(route("Blijft", created: 100))
        try store.restore(from: data)
        XCTAssertEqual(try store.plannedRoutes().map(\.name), ["Blijft"])
    }

    func testRouteCodableRoundTrip() throws {
        let r = route("Kaai", created: 100)
        let back = try JSONDecoder().decode(PlannedRoute.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}
