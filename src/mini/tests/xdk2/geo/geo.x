import xdk.geo
static Int main() {
    GeoPoint a = new GeoPoint(0.0, 0.0)
    GeoPoint b = new GeoPoint(0.0, 1.0)
    print(Geo.distanceMeters(a, b))
    print(Geo.bearingDegrees(a, b))
    print(Geo.normalizeLongitude(180.0))
    GeoPoint dest = Geo.destination(a, 90.0, 111195.0)
    print(dest.latitude())
    print(dest.longitude())
    Result<GeoPoint, Error> mid = Geo.midpoint(a, b)
    print(mid.isOk())
    GeoBounds bounds = new GeoBounds(-1.0, -1.0, 1.0, 1.0)
    print(bounds.containsPoint(a))
    print(bounds.widthDegrees())
    List<GeoPoint> points = [a, b]
    GeoPath path = new GeoPath(points)
    print(path.pointCount())
    print(path.length() > 0.0)
    List<GeoPoint> ringPoints = [new GeoPoint(0.0,0.0), new GeoPoint(0.0,2.0), new GeoPoint(2.0,2.0), new GeoPoint(2.0,0.0)]
    GeoPolygon polygon = new GeoPolygon(new GeoPath(ringPoints))
    print(polygon.contains(new GeoPoint(1.0, 1.0)))
    print(geoProjectionName(GeoProjection.WebMercator))
    print(geoProjectionName(null as GeoProjection))
    print(geoProjectionFromName("unknown") == null)
    print(geoProjectionFromName("other") == null)
    Result<Pair<Double,Double>, Error> projected = Geo.project(a, GeoProjection.WebMercator)
    print(projected.isOk())
    Result<GeoPoint, Error> unprojected = Geo.unproject(projected.value(), GeoProjection.WebMercator)
    print(unprojected.isOk())
    return 0
}
