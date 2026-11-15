import xdk.runtime

static Int main() {
    diagnose("runtime ok")
    print(nowMono() > 0)
    print(nowWall() > 0)
    return 0
}
