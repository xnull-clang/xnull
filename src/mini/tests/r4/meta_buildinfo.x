import xdk.meta

static Int main() {
    BuildInfo info = buildInfo()
    print(info.complete())
    print(info.languageVersion)
    print(info.xdkVersion)
    print(info.compiler)
    print(info.compilerVersion)
    print(info.platform.length() > 0)
    print(info.arch.length() > 0)
    print(info.mode.length() > 0)
    print(info.builtAt.length() > 0)
    print(info.describe().length() > 0)
    print(targetArch().length() > 0)
    print(buildMode().length() > 0)
    print(compilerName())
    print(compilerVersion())
    print(buildDate().length() > 0)
    return 0
}
