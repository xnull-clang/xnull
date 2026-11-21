// R4 evidence: RuntimeInfo is a real runtime surface, not a stub.
import xdk.runtime
import xdk.meta

static Int main() {
    RuntimeInfo info = runtimeInfo()
    print(info.languageVersion.length() > 0)
    print(info.xdkVersion.length() > 0)
    print(info.platform.length() > 0)
    print(info.arch.length() > 0)
    print(info.mode == "release" || info.mode == "debug")
    print(info.complete())
    print(info.describe().length() > 0)
    print(info.languageVersion == languageVersion())
    print(info.xdkVersion == xdkVersion())
    print(info.platform == targetPlatform())
    return 0
}
