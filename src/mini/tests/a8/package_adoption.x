import xdk.errors
import xdk.config
import xdk.log
import xdk.meta
import xdk.runtime

static Int main() {
    ErrorDetail detail0 = new ErrorDetail("alpha", "one")
    ErrorDetail detail1 = new ErrorDetail("alpha", "one")
    ErrorDetail detail2 = new ErrorDetail("alpha", "two")
    print(detail0.equals(detail1))
    print(detail0.equals(detail2))
    print(detail0.equals(null))
    print(detail0.toString())
    ErrorDetail detailCopy = detail0.copy()
    print(detailCopy.equals(detail0))

    ConfigEntry config0 = new ConfigEntry("key", "value")
    ConfigEntry config1 = new ConfigEntry("key", "value")
    ConfigEntry config2 = new ConfigEntry("key", "other")
    print(config0.equals(config1))
    print(config0.equals(config2))
    print(config0.toString())
    print(config0.copy().equals(config0))

    Field logField0 = new Field("level", "info")
    Field logField1 = new Field("level", "info")
    print(logField0.equals(logField1))
    print(logField0.toString())
    print(logField0.copy().equals(logField0))

    BuildInfo build0 = new BuildInfo("3.4.0", "1.0.0", "mini", "0.4", "linux", "x64", "release", "2026-11-22")
    BuildInfo build1 = new BuildInfo("3.4.0", "1.0.0", "mini", "0.4", "linux", "x64", "release", "2026-11-22")
    print(build0.equals(build1))
    print(build0.toString())
    print(build0.copy().equals(build0))

    RuntimeInfo runtime0 = new RuntimeInfo("3.4.0", "1.0.0", "linux", "x64", "release")
    RuntimeInfo runtime1 = new RuntimeInfo("3.4.0", "1.0.0", "linux", "x64", "release")
    print(runtime0.equals(runtime1))
    print(runtime0.toString())
    print(runtime0.copy().equals(runtime0))

    RuntimeStats stats0 = new RuntimeStats(1, 2, 3, 4, 5)
    RuntimeStats stats1 = new RuntimeStats(1, 2, 3, 4, 5)
    RuntimeStats stats2 = new RuntimeStats(1, 2, 3, 4, 6)
    print(stats0.equals(stats1))
    print(stats0.equals(stats2))
    print(stats0.toString())
    print(stats0.copy().equals(stats0))
    return 0
}
