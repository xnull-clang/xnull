import xdk.fs

static Int main() {
    String path = "/tmp/xnull_xdk_fs_probe.txt"
    print(writeText(path, "hello xdk.fs"))
    print(exists(path))
    print(readText(path))
    return 0
}
