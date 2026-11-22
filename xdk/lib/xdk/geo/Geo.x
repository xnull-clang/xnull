// xdk.geo — WGS84 points, bounds, paths, polygons, and Web Mercator projection.
// Tier: L6；依赖：xdk.math、xdk.errors、xdk.collections；稳定性：preview。
package xdk.geo
import xdk.math
import xdk.errors
import xdk.collections

Error geoError(ErrorKind kind, String message) { return new BasicError(kind, message) }

enum GeoProjection {
    Wgs84,
    WebMercator,
    Utm,
}

String geoProjectionName(GeoProjection projection) {
    if projection == null { return "unknown" }
    if projection == GeoProjection.Wgs84 { return "wgs84" }
    if projection == GeoProjection.WebMercator { return "web_mercator" }
    if projection == GeoProjection.Utm { return "utm" }
    return "other"
}

GeoProjection? geoProjectionFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "wgs84" { return GeoProjection.Wgs84 }
    if normalized == "web_mercator" || normalized == "webmercator" { return GeoProjection.WebMercator }
    if normalized == "utm" { return GeoProjection.Utm }
    return null
}

class GeoPoint {
    final Double _latitude
    final Double _longitude

    GeoPoint(Double latitude, Double longitude) {
        if !isFinite(latitude) || !isFinite(longitude) { throw "GeoPoint: non-finite coordinate" }
        if latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0 {
            throw "GeoPoint: coordinate out of range"
        }
        self._latitude = latitude
        self._longitude = longitude
    }

    Double latitude() { return self._latitude }
    Double longitude() { return self._longitude }
    Bool equals(GeoPoint other) {
        if other == null { return false }
        return self._latitude == other.latitude() && self._longitude == other.longitude()
    }
    String describe() { return "(" + str(self._latitude) + ", " + str(self._longitude) + ")" }
}

class GeoBounds {
    final Double _south
    final Double _west
    final Double _north
    final Double _east

    GeoBounds(Double south, Double west, Double north, Double east) {
        if !isFinite(south) || !isFinite(west) || !isFinite(north) || !isFinite(east) {
            throw "GeoBounds: non-finite bound"
        }
        if south < -90.0 || north > 90.0 || west < -180.0 || east > 180.0 {
            throw "GeoBounds: bound out of range"
        }
        if south > north || west > east { throw "GeoBounds: south>north or west>east" }
        self._south = south
        self._west = west
        self._north = north
        self._east = east
    }

    Double south() { return self._south }
    Double west() { return self._west }
    Double north() { return self._north }
    Double east() { return self._east }
    Bool containsPoint(GeoPoint point) {
        if point == null { throw "GeoBounds.containsPoint: null point" }
        return point.latitude() >= self._south && point.latitude() <= self._north &&
            point.longitude() >= self._west && point.longitude() <= self._east
    }
    Bool containsBounds(GeoBounds other) {
        if other == null { throw "GeoBounds.containsBounds: null bounds" }
        return other.south() >= self._south && other.north() <= self._north &&
            other.west() >= self._west && other.east() <= self._east
    }
    GeoPoint center() {
        return new GeoPoint((self._south + self._north) / 2.0, (self._west + self._east) / 2.0)
    }
    Double widthDegrees() { return self._east - self._west }
    Double heightDegrees() { return self._north - self._south }
    Bool equals(GeoBounds other) {
        if other == null { return false }
        return self._south == other.south() && self._west == other.west() &&
            self._north == other.north() && self._east == other.east()
    }
    String describe() { return "[" + str(self._south) + "," + str(self._west) + "," + str(self._north) + "," + str(self._east) + "]" }
}

class GeoPath {
    final List<GeoPoint> _points

    GeoPath(List<GeoPoint> points) {
        if points == null || points.length() < 2 { throw "GeoPath: need at least 2 points" }
        List<GeoPoint> copy = []
        Int index = 0
        while index < points.length() {
            GeoPoint point = points.get(index)
            if point == null { throw "GeoPath: null point" }
            copy.push(point)
            index = index + 1
        }
        self._points = copy
    }

    List<GeoPoint> points() { return self._points.copy() }
    Int pointCount() { return self._points.length() }
    GeoPoint pointAt(Int pointIndex) {
        if pointIndex < 0 || pointIndex >= self._points.length() { throw "GeoPath.pointAt: index out of range" }
        return self._points.get(pointIndex)
    }
    Double length() {
        Double total = 0.0
        Int index = 1
        while index < self._points.length() {
            total = total + Geo.distanceMeters(self._points.get(index - 1), self._points.get(index))
            index = index + 1
        }
        return total
    }
    Bool isClosed() { return self._points.get(0).equals(self._points.get(self._points.length() - 1)) }
    Bool equals(GeoPath other) {
        if other == null || other.pointCount() != self.pointCount() { return false }
        Int index = 0
        while index < self._points.length() {
            if !self._points.get(index).equals(other.pointAt(index)) { return false }
            index = index + 1
        }
        return true
    }
    String describe() { return "GeoPath(" + str(self.pointCount()) + ")" }
}

class GeoPolygon {
    final GeoPath _outerRing
    final List<GeoPoint> _vertices

    GeoPolygon(GeoPath outerRing) {
        if outerRing == null || outerRing.pointCount() < 3 { throw "GeoPolygon: need at least 3 points" }
        List<GeoPoint> vertices = []
        Int count = outerRing.pointCount()
        Int index = 0
        while index < count {
            if outerRing.pointAt(0).equals(outerRing.pointAt(index)) && index == count - 1 && index > 0 {
                index = index + 1
                continue
            }
            vertices.push(outerRing.pointAt(index))
            index = index + 1
        }
        if vertices.length() < 3 { throw "GeoPolygon: fewer than 3 distinct vertices" }
        index = 0
        while index < vertices.length() {
            Int next = (index + 1) % vertices.length()
            if vertices.get(index).equals(vertices.get(next)) {
                throw "GeoPolygon: adjacent duplicate vertex"
            }
            index = index + 1
        }
        self._outerRing = outerRing
        self._vertices = vertices
    }

    GeoPath outerRing() { return self._outerRing }
    Int vertexCount() { return self._vertices.length() }

    Bool contains(GeoPoint point) {
        if point == null { throw "GeoPolygon.contains: null point" }
        Bool inside = false
        Int index = 0
        Int previous = self._vertices.length() - 1
        while index < self._vertices.length() {
            GeoPoint a = self._vertices.get(previous)
            GeoPoint b = self._vertices.get(index)
            if self.onSegment(point, a, b) { return true }
            Bool crosses = (a.latitude() > point.latitude()) != (b.latitude() > point.latitude())
            if crosses {
                Double x = (b.longitude() - a.longitude()) * (point.latitude() - a.latitude()) /
                    (b.latitude() - a.latitude()) + a.longitude()
                if point.longitude() < x { inside = !inside }
            }
            previous = index
            index = index + 1
        }
        return inside
    }

    Bool onSegment(GeoPoint point, GeoPoint a, GeoPoint b) {
        Double cross = (point.latitude() - a.latitude()) * (b.longitude() - a.longitude()) -
            (point.longitude() - a.longitude()) * (b.latitude() - a.latitude())
        if abs(cross) > 0.000000001 { return false }
        Double minLat = min(a.latitude(), b.latitude())
        Double maxLat = max(a.latitude(), b.latitude())
        Double minLon = min(a.longitude(), b.longitude())
        Double maxLon = max(a.longitude(), b.longitude())
        return point.latitude() >= minLat && point.latitude() <= maxLat &&
            point.longitude() >= minLon && point.longitude() <= maxLon
    }

    Bool equals(GeoPolygon other) {
        if other == null || other.vertexCount() != self.vertexCount() { return false }
        Int index = 0
        while index < self._vertices.length() {
            if !self._vertices.get(index).equals(other.outerRing().pointAt(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() { return "GeoPolygon(" + str(self.vertexCount()) + ")" }
}

class Geo {
    static Double distanceMeters(GeoPoint first, GeoPoint second) {
        if first == null || second == null { throw "Geo.distanceMeters: null point" }
        Double lat1 = first.latitude() * PI() / 180.0
        Double lat2 = second.latitude() * PI() / 180.0
        Double deltaLat = (second.latitude() - first.latitude()) * PI() / 180.0
        Double deltaLon = Geo.normalizeLongitude(second.longitude() - first.longitude()) * PI() / 180.0
        Double a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
            cos(lat1) * cos(lat2) * sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
        return 6371008.8 * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    }

    static Double bearingDegrees(GeoPoint first, GeoPoint second) {
        if first == null || second == null { throw "Geo.bearingDegrees: null point" }
        Double lat1 = first.latitude() * PI() / 180.0
        Double lat2 = second.latitude() * PI() / 180.0
        Double deltaLon = Geo.normalizeLongitude(second.longitude() - first.longitude()) * PI() / 180.0
        Double y = sin(deltaLon) * cos(lat2)
        Double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        Double angle = atan2(y, x) * 180.0 / PI()
        if angle < 0.0 { angle = angle + 360.0 }
        return angle
    }

    static GeoPoint destination(GeoPoint origin, Double initialBearingDegrees, Double travelDistanceMeters) {
        if origin == null || !isFinite(initialBearingDegrees) || !isFinite(travelDistanceMeters) || travelDistanceMeters < 0.0 {
            throw "Geo.destination: invalid argument"
        }
        Double angular = travelDistanceMeters / 6371008.8
        Double bearing = initialBearingDegrees * PI() / 180.0
        Double lat1 = origin.latitude() * PI() / 180.0
        Double lon1 = origin.longitude() * PI() / 180.0
        Double lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        Double lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2))
        Double latitude = lat2 * 180.0 / PI()
        Double longitude = Geo.normalizeLongitude(lon2 * 180.0 / PI())
        if latitude > 90.0 { latitude = 90.0 }
        if latitude < -90.0 { latitude = -90.0 }
        return new GeoPoint(latitude, longitude)
    }

    static Result<GeoPoint, Error> midpoint(GeoPoint first, GeoPoint second) {
        if first == null || second == null { throw "Geo.midpoint: null point" }
        Double lat1 = first.latitude() * PI() / 180.0
        Double lat2 = second.latitude() * PI() / 180.0
        Double lon1 = first.longitude() * PI() / 180.0
        Double deltaLon = Geo.normalizeLongitude(second.longitude() - first.longitude()) * PI() / 180.0
        Double bx = cos(lat2) * cos(deltaLon)
        Double by = cos(lat2) * sin(deltaLon)
        Double denominator = sqrt((1.0 + cos(lat1) * bx + sin(lat1) * by) * 0.5)
        if abs(denominator) < 0.000000000001 {
            return Err(geoError(ErrorKind.InvalidArgument, "Geo.midpoint: antipodal points"))
        }
        Double latitude = atan2(sin(lat1) + sin(lat2), sqrt((cos(lat1) + bx) * (cos(lat1) + bx) + by * by)) * 180.0 / PI()
        Double longitude = Geo.normalizeLongitude((lon1 + atan2(by, cos(lat1) + bx)) * 180.0 / PI())
        return Ok(new GeoPoint(latitude, longitude))
    }

    static Double normalizeLongitude(Double longitude) {
        if !isFinite(longitude) { throw "Geo.normalizeLongitude: non-finite" }
        Double value = longitude
        while value >= 180.0 { value = value - 360.0 }
        while value < -180.0 { value = value + 360.0 }
        return value
    }

    static Result<Pair<Double, Double>, Error> project(GeoPoint point, GeoProjection projection) {
        if point == null || projection == null { throw "Geo.project: null argument" }
        if projection == GeoProjection.Wgs84 {
            return Ok(new Pair<Double, Double>(point.longitude(), point.latitude()))
        }
        if projection == GeoProjection.Utm {
            return Err(geoError(ErrorKind.Unsupported, "Geo.project: UTM not supported"))
        }
        Double latitude = point.latitude()
        if latitude > 85.05112878 { latitude = 85.05112878 }
        if latitude < -85.05112878 { latitude = -85.05112878 }
        Double x = point.longitude() * 20037508.342789244 / 180.0
        Double y = log(tan((90.0 + latitude) * PI() / 360.0)) * 20037508.342789244 / PI()
        return Ok(new Pair<Double, Double>(x, y))
    }

    static Result<GeoPoint, Error> unproject(Pair<Double, Double> projectedCoordinate, GeoProjection projection) {
        if projectedCoordinate == null || projection == null { throw "Geo.unproject: null argument" }
        Double x = projectedCoordinate.first()
        Double y = projectedCoordinate.second()
        if !isFinite(x) || !isFinite(y) {
            return Err(geoError(ErrorKind.InvalidArgument, "Geo.unproject: non-finite coordinate"))
        }
        if projection == GeoProjection.Utm {
            return Err(geoError(ErrorKind.Unsupported, "Geo.unproject: UTM not supported"))
        }
        if projection == GeoProjection.Wgs84 {
            if x < -180.0 || x > 180.0 || y < -90.0 || y > 90.0 {
                return Err(geoError(ErrorKind.InvalidArgument, "Geo.unproject: WGS84 out of range"))
            }
            return Ok(new GeoPoint(y, x))
        }
        if x < -20037508.342789244 || x > 20037508.342789244 ||
            y < -20037508.342789244 || y > 20037508.342789244 {
            return Err(geoError(ErrorKind.InvalidArgument, "Geo.unproject: WebMercator out of range"))
        }
        Double longitude = x * 180.0 / 20037508.342789244
        Double latitude = 180.0 / PI() * (2.0 * atan(exp(y * PI() / 20037508.342789244)) - PI() / 2.0)
        return Ok(new GeoPoint(latitude, longitude))
    }
}
