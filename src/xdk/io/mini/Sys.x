// xdk.sys —— mini 引擎最小系统面
package xdk.sys

Bool fileExists(String path) {
    return fileExistsRaw(path) != 0
}

Bool resourceExists(String path) {
    return resourceExistsRaw(path) != 0
}

String readResourceText(String path) {
    return readResourceTextRaw(path)
}

Int resourceCount() {
    return resourceCountRaw()
}
