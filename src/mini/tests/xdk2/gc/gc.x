package xdk2.gc
import xdk.runtime
import xdk.codec

static Int main() {
    JsonValue keep = Json.bool(true)
    Int index = 0
    while index < 500 {
        JsonValue temporary = Json.string("temporary-value")
        JsonObject object = new JsonObject()
        object.set("n", Json.number(str(index)))
        index = index + 1
    }

    Long first = gcCollect()
    print("gc=" + str(first >= 0) + "," + str(keep.isBool()) + "," + str(keep.asBool()))

    Int repeat = 0
    while repeat < 3 {
        gcCollect()
        if !keep.isBool() || !(keep.asBool() as Bool) { return 1 }
        repeat = repeat + 1
    }
    print("gc-repeat=ok")
    return 0
}
