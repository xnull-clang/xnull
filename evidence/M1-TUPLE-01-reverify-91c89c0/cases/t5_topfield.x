static (Int, Int) top = (11, 12)
static (Int, String)? topOpt = null
static Int main() {
    print(top.0)
    print(top.1)
    print(topOpt == null)
    return 0
}
