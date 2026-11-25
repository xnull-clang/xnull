package xdk2.os
import xdk.os

static OsInfo sampleInfo() {
    return new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
        "6.1.0", "x86_64", "test-host", "", "glibc 2.39", false)
}

static String capabilityList(List<OsCapability> values) {
    String text = ""
    Int index = 0
    while index < values.length() {
        if index > 0 { text = text + "," }
        text = text + osCapabilityName(values.get(index))
        index = index + 1
    }
    return text
}

static Int main() {
    print("kind-names=" + osKindName(OsKind.Linux) + "," + osKindName(OsKind.Windows) +
        "," + osKindName(OsKind.MacOS) + "," + osKindName(OsKind.Android) + "," +
        osKindName(OsKind.IOS) + "," + osKindName(OsKind.FreeBsd) + "," +
        osKindName(OsKind.Wasm) + "," + osKindName(OsKind.Unknown))
    print("kind-display=" + osKindDisplayName(OsKind.MacOS) + "," +
        osKindDisplayName(OsKind.FreeBsd) + "," + osKindDisplayName(OsKind.Wasm))
    print("kind-parse=" + osKindName(osKindFromName("Darwin")) + "," +
        osKindName(osKindFromName(" WEBASSEMBLY ")) + "," +
        osKindName(osKindFromName("bogus")) + "," +
        osKindName(osKindFromName(null)))
    print("kind-family=" + osFamilyName(osKindFamily(OsKind.Linux)) + "," +
        osFamilyName(osKindFamily(OsKind.Windows)) + "," +
        osFamilyName(osKindFamily(OsKind.Wasm)) + "," +
        osFamilyName(osKindFamily(OsKind.Unknown)))
    print("family-names=" + osFamilyName(OsFamily.Unix) + "," +
        osFamilyName(OsFamily.Windows) + "," + osFamilyName(OsFamily.Wasm) + "," +
        osFamilyName(OsFamily.Unknown))
    print("family-parse=" + osFamilyName(osFamilyFromName("UNIX")) + "," +
        osFamilyName(osFamilyFromName("Wasm")) + "," +
        osFamilyName(osFamilyFromName("nope")) + "," +
        str(osFamilyIsUnixLike(OsFamily.Unix)) + "," +
        str(osFamilyIsUnixLike(OsFamily.Windows)))

    print("cap-names=" + osCapabilityName(OsCapability.CpuTopology) + "," +
        osCapabilityName(OsCapability.PhysicalMemory) + "," +
        osCapabilityName(OsCapability.GpuCompute) + "," +
        osCapabilityName(OsCapability.ServiceManager) + "," +
        osCapabilityName(OsCapability.Session) + "," +
        osCapabilityName(OsCapability.Unknown))
    print("cap-parse=" + osCapabilityName(osCapabilityFromName("cpu_features")) + "," +
        osCapabilityName(osCapabilityFromName(" RAW_DEVICE ")) + "," +
        osCapabilityName(osCapabilityFromName("bogus")) + "," +
        osCapabilityName(osCapabilityFromName(null)))
    print("cap-flags=" + str(osCapabilityRequiresPrivilege(OsCapability.CpuAffinity)) +
        "," + str(osCapabilityRequiresPrivilege(OsCapability.CpuTopology)) + "," +
        str(osCapabilityIsSensitive(OsCapability.Pci)) + "," +
        str(osCapabilityIsSensitive(OsCapability.Gpu)))

    OsInfo detected = OsInfo.detect()
    Bool detectedKind = detected.kind() != OsKind.Unknown
    Bool detectedFamily = detected.family() == osKindFamily(detected.kind())
    print("detect=" + str(detectedKind) + "," + str(detectedFamily) + "," +
        str(detected.name().length() > 0) + "," + str(detected.architecture().length() > 0) +
        "," + str(detected.version().length() > 0) + "," +
        str(detected.kernelVersion().length() > 0) + "," +
        str(detected.kind() == OsKind.MacOS) + "," + str(detected.isHeadless()) + "," +
        str(detected.libc().length() > 0))
    print("detect-kind-name=" + osKindName(detected.kind()) + "," +
        osKindDisplayName(detected.kind()) + "," +
        osFamilyName(detected.family()))

    OsInfo sample = sampleInfo()
    OsInfo copy = sample.copy()
    print("info=" + sample.describe() + "," + str(sample.equals(copy)) + "," +
        str(sample.isHeadless()) + "," + str(sample.isContainerized()) + "," +
        sample.libc())
    OsInfo another = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
        "6.1.0", "x86_64", "test-host", "", "glibc 2.39", false)
    print("info-equals=" + str(sample.equals(another)) + "," +
        str(sample.equals(null)))

    List<OsCapability> initial = [OsCapability.CpuTopology, OsCapability.Gpu,
        OsCapability.CpuTopology, OsCapability.Gpu]
    OsProfile profile = new OsProfile("test-profile", sample, initial)
    print("profile=" + profile.describe() + "," + str(profile.capabilities().length()) +
        "," + capabilityList(profile.capabilities()) + "," + str(profile.has(OsCapability.Gpu)) +
        "," + str(profile.has(OsCapability.Storage)))
    List<OsCapability> required = [OsCapability.Gpu, OsCapability.Storage,
        OsCapability.Session]
    print("profile-missing=" + capabilityList(profile.missing(required)))
    OsProfile withMore = profile.withCapability(OsCapability.Storage)
    OsProfile withExisting = withMore.withCapability(OsCapability.Gpu)
    OsProfile without = withMore.withoutCapability(OsCapability.CpuTopology)
    OsProfile renamed = profile.withName("renamed")
    print("profile-with=" + str(withMore.capabilities().length()) + "," +
        str(withExisting.capabilities().length()) + "," +
        str(without.has(OsCapability.CpuTopology)) + "," + renamed.name() + "," +
        str(profile.capabilities().length()))
    print("profile-equals=" + str(profile.equals(profile.copy())) + "," +
        str(profile.equals(anotherProfile(sample))) + "," + str(profile.equals(null)))
    print("profile-kinds=" + osKindName(profile.kind()) + "," +
        osFamilyName(profile.family()) + "," + profile.info().name())

    OsProfile detectedProfile = osDetectProfile()
    print("detected-profile=" + str(detectedProfile.info().kind() == detected.kind()) + "," +
        str(detectedProfile.has(OsCapability.Container) == detected.isContainerized()) +
        "," + str(detectedProfile.capabilities().length() <= 1) + "," +
        str(detectedProfile.name().length() > 0))
    return 0
}

static OsProfile anotherProfile(OsInfo info) {
    List<OsCapability> capabilities = [OsCapability.Gpu, OsCapability.CpuTopology]
    return new OsProfile("test-profile", info, capabilities)
}
