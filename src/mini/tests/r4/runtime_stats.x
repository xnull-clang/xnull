// R4 evidence: public xdk.runtime allocation/GC stats snapshot.
import xdk.runtime

static Int main() {
    statsReset()
    statsSetEnabled(true)
    print(statsEnabled())
    String marker = "stats" + "-" + "probe"
    print(marker.length())
    RuntimeStats snapshot = stats()
    print(snapshot.allocs >= 1)
    print(snapshot.bytes > 0)
    print(snapshot.live() >= 0)
    print(snapshot.frees >= 0)
    print(snapshot.gcCollections >= 0)
    print(snapshot.gcFreed >= 0)
    statsSetEnabled(false)
    print(statsEnabled())
    return 0
}
