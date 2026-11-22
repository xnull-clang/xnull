import xdk.collections
import xdk.meta
import xdk.runtime
static Int main() {
    Pair p0 = new Pair("a", 1)
    Pair p1 = new Pair("a", 1)
    Pair p2 = new Pair("b", 2)
    print(p0.equals(p1))
    print(p0.equals(p2))
    print(p0.equals(null))
    print(p0.toString())
    Pair p3 = p0.withFirst("b").withSecond(2)
    print(p0.first)
    print(p3.first)
    print(p3.equals(p2))
    Pair p4 = p0.copy()
    print(p4.equals(p0))

    IntPair i0 = new IntPair(1, 2)
    IntPair i1 = new IntPair(1, 2)
    print(i0.equals(i1))
    print(i0.toString())
    IntPair i2 = i0.withFirst(3).withSecond(4)
    print(i0.first)
    print(i2.first)

    Entry<String, Long> e0 = new Entry<String, Long>("k", 9)
    Entry<String, Long> e1 = new Entry<String, Long>("k", 9)
    print(e0.equals(e1))
    print(e0.toString())
    Entry<String, Long> e2 = e0.withKey("x").withValue(10)
    print(e0.key)
    print(e2.key)
    print(e2.equals(e0))

    BuildInfoBuilder bb = new BuildInfoBuilder()
    BuildInfo buildInfo = bb.withLanguageVersion("3.4.0").withXdkVersion("1.0.0").withCompiler("mini").withCompilerVersion("0.4").withPlatform("linux").withArch("x64").withMode("release").withBuiltAt("2026-11-23").build()
    print(buildInfo.languageVersion)
    print(buildInfo.builtAt)

    RuntimeInfoBuilder rb = new RuntimeInfoBuilder()
    RuntimeInfo runtimeInfo = rb.withLanguageVersion("3.4.0").withXdkVersion("1.0.0").withPlatform("linux").withArch("x64").withMode("release").build()
    print(runtimeInfo.platform)
    print(runtimeInfo.mode)
    return 0
}
