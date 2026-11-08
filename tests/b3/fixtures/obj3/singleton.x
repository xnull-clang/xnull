singleton AppInfo {
    final String name = "XNull"
    Int n = 3
    Int twice() { return self.n * 2 }
}
static Int main() {
    print(AppInfo.instance.name)
    print(AppInfo.instance.twice())
    AppInfo.instance.n = 4
    print(AppInfo.instance.twice())
    return 0
}
