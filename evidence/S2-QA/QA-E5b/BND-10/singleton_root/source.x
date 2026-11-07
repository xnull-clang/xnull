singleton AppInfo {
    Int count = 3;
}
static Int main() {
    print(AppInfo.instance.count)
    return 0
}
