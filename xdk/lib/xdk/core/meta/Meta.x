// xdk.meta —— 语言/XDK 版本与目标平台（T0-A）
// Tier: T0；依赖：ext_raw.platformRaw；稳定性：stable。
package xdk.meta

String languageVersion() {
    return "3.4.0"
}

String xdkVersion() {
    return "0.1.0"
}

String targetPlatform() {
    return platformRaw()
}
