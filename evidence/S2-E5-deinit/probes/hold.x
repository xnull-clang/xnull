import xdk.sys

class Holder {
    File f
}

static Int main() {
    Holder h = new Holder()
    String p = "in.txt"
    File g = fileOpenRead(p)
    h.f = g
    Bool ok = fileClose(g)
    if (!ok) {
        return 12
    }
    return 0
}
