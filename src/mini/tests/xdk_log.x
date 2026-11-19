import xdk.log

static Int main() {
    Logger l = new Logger("app", Level.Info)
    l.debug("hidden")
    l.info("started")
    l.warn("careful")
    l.error("bad")
    Logger d = new Logger("dbg", Level.Debug)
    d.debug("visible")
    return 0
}
