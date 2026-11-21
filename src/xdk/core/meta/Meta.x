// xdk.meta —— 语言/XDK 版本、目标平台与构建元数据（T0-A/T0-X）
// Tier: T0；依赖：ext_raw.platformRaw/archRaw、runtime_raw.buildModeRaw/buildDateRaw；
// 稳定性：stable。
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

// ---------- BuildInfo / 构建元数据（T0-X） ----------

String targetArch() {
    return archRaw()
}

String buildMode() {
    return buildModeRaw()
}

String compilerName() {
    return "mini"
}

String compilerVersion() {
    return "3.4.0"
}

// 编译期 __DATE__/__TIME__；格式与可重现性见 03-meta.md。
String buildDate() {
    return buildDateRaw()
}

class BuildInfo {
    final String languageVersion
    final String xdkVersion
    final String compiler
    final String compilerVersion
    final String platform
    final String arch
    final String mode
    final String builtAt

    BuildInfo(String languageVersion0, String xdkVersion0, String compiler0,
        String compilerVersion0, String platform0, String arch0,
        String mode0, String builtAt0) {
        self.languageVersion = languageVersion0
        self.xdkVersion = xdkVersion0
        self.compiler = compiler0
        self.compilerVersion = compilerVersion0
        self.platform = platform0
        self.arch = arch0
        self.mode = mode0
        self.builtAt = builtAt0
    }

    Bool complete() {
        return self.languageVersion.length() > 0 &&
            self.xdkVersion.length() > 0 &&
            self.compiler.length() > 0 &&
            self.compilerVersion.length() > 0 &&
            self.platform.length() > 0 &&
            self.arch.length() > 0 &&
            self.mode.length() > 0 &&
            self.builtAt.length() > 0
    }

    String describe() {
        return self.compiler + " " + self.compilerVersion +
            " / " + self.languageVersion + " / xdk " + self.xdkVersion +
            " / " + self.platform + "-" + self.arch +
            " / " + self.mode + " / " + self.builtAt
    }
}

BuildInfo buildInfo() {
    return new BuildInfo(languageVersion(), xdkVersion(), compilerName(),
        compilerVersion(), targetPlatform(), targetArch(), buildMode(), buildDate())
}
