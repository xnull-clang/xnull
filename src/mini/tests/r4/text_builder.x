// R4 evidence: xdk.text.StringBuilder T0 surface (append/appendInt/appendLong/
// appendChar/length/isEmpty/clear/toString) and snapshot semantics.
import xdk.text

static Int main() {
    StringBuilder builder = new StringBuilder()
    print(builder.length())
    print(builder.isEmpty())
    print(builder.toString() == "")
    builder.append("ab").appendInt(7).appendChar('-')
    print(builder.length())
    print(builder.toString())
    builder.appendLong(9000000000)
    print(builder.length())
    print(builder.toString())
    builder.clear()
    print(builder.length())
    print(builder.isEmpty())
    builder.append("x")
    String snapshot = builder.toString()
    builder.append("y")
    print(snapshot)
    print(builder.toString())
    return 0
}
