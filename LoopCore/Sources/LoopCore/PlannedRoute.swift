import Foundation

/// Een zelf geplande route op de kaart. Punten als twee parallelle lijsten, zoals `RouteTrack`.
public struct PlannedRoute: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var created: Date
    public var latitudes: [Double]
    public var longitudes: [Double]
    /// Lengte in meter.
    public var distance: Double
    /// True als de route terugkeert naar het startpunt.
    public var isLoop: Bool

    public init(id: UUID = UUID(), name: String, created: Date = Date(),
                latitudes: [Double], longitudes: [Double], isLoop: Bool = false) {
        self.id = id
        self.name = name
        self.created = created
        self.latitudes = latitudes
        self.longitudes = longitudes
        self.distance = RouteGeometry.length(latitudes: latitudes, longitudes: longitudes)
        self.isLoop = isLoop
    }

    public var count: Int { min(latitudes.count, longitudes.count) }
}

/// Rekenwerk op routes: afstanden, uitdunnen en hoe ver een punt van een route ligt.
/// Pure wiskunde zonder CoreLocation, zodat het in Actions getest kan worden.
public enum RouteGeometry {
    static let earthRadius = 6_371_008.8

    /// Afstand in meter tussen twee punten (haversine).
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// Totale lengte van een lijn in meter.
    public static func length(latitudes: [Double], longitudes: [Double]) -> Double {
        let n = min(latitudes.count, longitudes.count)
        guard n > 1 else { return 0 }
        return (1..<n).reduce(0.0) { sum, i in
            sum + distance(latitudes[i - 1], longitudes[i - 1], latitudes[i], longitudes[i])
        }
    }

    /// Houdt enkel punten die minstens `minSpacing` meter uit elkaar liggen (eerste en laatste blijven altijd).
    /// Maakt lange routes lichter om te tekenen zonder dat de vorm verandert.
    public static func thin(latitudes: [Double], longitudes: [Double],
                            minSpacing: Double) -> (latitudes: [Double], longitudes: [Double]) {
        let n = min(latitudes.count, longitudes.count)
        guard n > 2 else { return (Array(latitudes.prefix(n)), Array(longitudes.prefix(n))) }
        var lats = [latitudes[0]], lons = [longitudes[0]]
        for i in 1..<(n - 1) where distance(lats[lats.count - 1], lons[lons.count - 1], latitudes[i], longitudes[i]) >= minSpacing {
            lats.append(latitudes[i])
            lons.append(longitudes[i])
        }
        lats.append(latitudes[n - 1])
        lons.append(longitudes[n - 1])
        return (lats, lons)
    }

    /// Kortste afstand in meter van een punt tot een lijn.
    /// Rekent in een vlakke projectie rond het punt: ruim nauwkeurig genoeg voor een tik op de kaart.
    public static func distanceToLine(lat: Double, lon: Double,
                                      latitudes: [Double], longitudes: [Double]) -> Double {
        let n = min(latitudes.count, longitudes.count)
        guard n > 0 else { return .infinity }
        let mPerLat = earthRadius * .pi / 180
        let mPerLon = mPerLat * cos(lat * .pi / 180)
        func xy(_ i: Int) -> (Double, Double) {
            ((longitudes[i] - lon) * mPerLon, (latitudes[i] - lat) * mPerLat)
        }
        if n == 1 {
            let (x, y) = xy(0)
            return (x * x + y * y).squareRoot()
        }
        var best = Double.infinity
        for i in 1..<n {
            let (ax, ay) = xy(i - 1), (bx, by) = xy(i)
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let px = ax + t * dx, py = ay + t * dy
            best = min(best, (px * px + py * py).squareRoot())
        }
        return best
    }
}
