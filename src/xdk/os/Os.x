// xdk.os —— OS 根类型（M20.1）
//
// 实现 OsKind/OsFamily/OsCapability/OsInfo/OsProfile 与 osDetectProfile。
// OsHost/Os 静态入口与 os.* 子包留后续批次。
// 稳定性：preview。合同见 docs/design/platform/os/。
package xdk.os

// ---------- OsFamily ----------
enum OsFamily {
    Unix,
    Windows,
    Wasm,
    Unknown,
}

String osFamilyName(OsFamily family) {
    if family == OsFamily.Unix { return "unix" }
    if family == OsFamily.Windows { return "windows" }
    if family == OsFamily.Wasm { return "wasm" }
    return "unknown"
}

OsFamily osFamilyFromName(String name) {
    if name == null { return OsFamily.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "unix" { return OsFamily.Unix }
    if normalized == "windows" { return OsFamily.Windows }
    if normalized == "wasm" { return OsFamily.Wasm }
    if normalized == "unknown" { return OsFamily.Unknown }
    return OsFamily.Unknown
}

Bool osFamilyIsUnixLike(OsFamily family) {
    return family == OsFamily.Unix
}

// ---------- OsKind ----------
enum OsKind {
    Linux,
    Windows,
    MacOS,
    Android,
    IOS,
    FreeBsd,
    Wasm,
    Unknown,
}

String osKindName(OsKind kind) {
    if kind == OsKind.Linux { return "linux" }
    if kind == OsKind.Windows { return "windows" }
    if kind == OsKind.MacOS { return "macos" }
    if kind == OsKind.Android { return "android" }
    if kind == OsKind.IOS { return "ios" }
    if kind == OsKind.FreeBsd { return "freebsd" }
    if kind == OsKind.Wasm { return "wasm" }
    return "unknown"
}

String osKindDisplayName(OsKind kind) {
    if kind == OsKind.Linux { return "Linux" }
    if kind == OsKind.Windows { return "Windows" }
    if kind == OsKind.MacOS { return "macOS" }
    if kind == OsKind.Android { return "Android" }
    if kind == OsKind.IOS { return "iOS" }
    if kind == OsKind.FreeBsd { return "FreeBSD" }
    if kind == OsKind.Wasm { return "WebAssembly" }
    return "Unknown"
}

OsKind osKindFromName(String name) {
    if name == null { return OsKind.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "linux" { return OsKind.Linux }
    if normalized == "windows" { return OsKind.Windows }
    if normalized == "macos" || normalized == "darwin" { return OsKind.MacOS }
    if normalized == "android" { return OsKind.Android }
    if normalized == "ios" { return OsKind.IOS }
    if normalized == "freebsd" { return OsKind.FreeBsd }
    if normalized == "wasm" || normalized == "webassembly" { return OsKind.Wasm }
    return OsKind.Unknown
}

OsFamily osKindFamily(OsKind kind) {
    if kind == OsKind.Windows { return OsFamily.Windows }
    if kind == OsKind.Wasm { return OsFamily.Wasm }
    if kind == OsKind.Unknown { return OsFamily.Unknown }
    return OsFamily.Unix
}

// ---------- OsCapability ----------
enum OsCapability {
    CpuTopology,
    CpuAffinity,
    CpuFeatures,
    PhysicalMemory,
    Numa,
    Pci,
    Usb,
    Storage,
    Sensors,
    Gpu,
    GpuCompute,
    Firewall,
    Container,
    Virtualization,
    ServiceManager,
    RawDevice,
    Session,
    Unknown,
}

String osCapabilityName(OsCapability capability) {
    if capability == OsCapability.CpuTopology { return "cpu_topology" }
    if capability == OsCapability.CpuAffinity { return "cpu_affinity" }
    if capability == OsCapability.CpuFeatures { return "cpu_features" }
    if capability == OsCapability.PhysicalMemory { return "physical_memory" }
    if capability == OsCapability.Numa { return "numa" }
    if capability == OsCapability.Pci { return "pci" }
    if capability == OsCapability.Usb { return "usb" }
    if capability == OsCapability.Storage { return "storage" }
    if capability == OsCapability.Sensors { return "sensors" }
    if capability == OsCapability.Gpu { return "gpu" }
    if capability == OsCapability.GpuCompute { return "gpu_compute" }
    if capability == OsCapability.Firewall { return "firewall" }
    if capability == OsCapability.Container { return "container" }
    if capability == OsCapability.Virtualization { return "virtualization" }
    if capability == OsCapability.ServiceManager { return "service_manager" }
    if capability == OsCapability.RawDevice { return "raw_device" }
    if capability == OsCapability.Session { return "session" }
    return "unknown"
}

OsCapability osCapabilityFromName(String name) {
    if name == null { return OsCapability.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "cpu_topology" { return OsCapability.CpuTopology }
    if normalized == "cpu_affinity" { return OsCapability.CpuAffinity }
    if normalized == "cpu_features" { return OsCapability.CpuFeatures }
    if normalized == "physical_memory" { return OsCapability.PhysicalMemory }
    if normalized == "numa" { return OsCapability.Numa }
    if normalized == "pci" { return OsCapability.Pci }
    if normalized == "usb" { return OsCapability.Usb }
    if normalized == "storage" { return OsCapability.Storage }
    if normalized == "sensors" { return OsCapability.Sensors }
    if normalized == "gpu" { return OsCapability.Gpu }
    if normalized == "gpu_compute" { return OsCapability.GpuCompute }
    if normalized == "firewall" { return OsCapability.Firewall }
    if normalized == "container" { return OsCapability.Container }
    if normalized == "virtualization" { return OsCapability.Virtualization }
    if normalized == "service_manager" { return OsCapability.ServiceManager }
    if normalized == "raw_device" { return OsCapability.RawDevice }
    if normalized == "session" { return OsCapability.Session }
    return OsCapability.Unknown
}

Bool osCapabilityRequiresPrivilege(OsCapability capability) {
    if capability == OsCapability.CpuAffinity { return true }
    if capability == OsCapability.Firewall { return true }
    if capability == OsCapability.Container { return true }
    if capability == OsCapability.Virtualization { return true }
    if capability == OsCapability.ServiceManager { return true }
    if capability == OsCapability.RawDevice { return true }
    return false
}

Bool osCapabilityIsSensitive(OsCapability capability) {
    if capability == OsCapability.Pci { return true }
    if capability == OsCapability.Usb { return true }
    if capability == OsCapability.Sensors { return true }
    if capability == OsCapability.Firewall { return true }
    if capability == OsCapability.ServiceManager { return true }
    if capability == OsCapability.RawDevice { return true }
    return false
}

// ---------- OsInfo ----------
class OsInfo {
    final OsKind _kind
    final OsFamily _family
    final String _name
    final String _version
    final String _kernelVersion
    final String _architecture
    final String _hostname
    final String _session
    final String _libc
    final Bool _isContainerized

    OsInfo(OsKind kind, OsFamily family, String name, String version,
           String kernelVersion, String architecture, String hostname,
           String session, String libc, Bool isContainerized) {
        if name == null || name == "" {
            throw "OsInfo: empty name"
        }
        if architecture == null || architecture == "" {
            throw "OsInfo: empty architecture"
        }
        if version == null || kernelVersion == null || hostname == null ||
            session == null || libc == null {
            throw "OsInfo: null string"
        }
        if family != osKindFamily(kind) {
            throw "OsInfo: family does not match kind"
        }
        self._kind = kind
        self._family = family
        self._name = name
        self._version = version
        self._kernelVersion = kernelVersion
        self._architecture = architecture
        self._hostname = hostname
        self._session = session
        self._libc = libc
        self._isContainerized = isContainerized
    }

    OsKind kind() { return self._kind }
    OsFamily family() { return self._family }
    String name() { return self._name }
    String version() { return self._version }
    String kernelVersion() { return self._kernelVersion }
    String architecture() { return self._architecture }
    String hostname() { return self._hostname }
    String session() { return self._session }
    String libc() { return self._libc }
    Bool isContainerized() { return self._isContainerized }
    Bool isHeadless() { return self._session == "" }

    String describe() {
        String text = osKindName(self._kind) + " " + self._name
        text = text + " version=" + self._version
        text = text + " kernel=" + self._kernelVersion
        text = text + " arch=" + self._architecture
        text = text + " session=" + self._session
        return text
    }

    Bool equals(OsInfo other) {
        if other == null { return false }
        return self._kind == other.kind() &&
            self._family == other.family() &&
            self._name == other.name() &&
            self._version == other.version() &&
            self._kernelVersion == other.kernelVersion() &&
            self._architecture == other.architecture() &&
            self._hostname == other.hostname() &&
            self._session == other.session() &&
            self._libc == other.libc() &&
            self._isContainerized == other.isContainerized()
    }

    OsInfo copy() {
        return new OsInfo(self._kind, self._family, self._name, self._version,
            self._kernelVersion, self._architecture, self._hostname,
            self._session, self._libc, self._isContainerized)
    }

    static OsInfo detect() {
        String platform = platformRaw()
        OsKind kind = OsKind.Unknown
        if platform == "darwin" { kind = OsKind.MacOS }
        if platform == "linux" { kind = OsKind.Linux }
        if platform == "windows" { kind = OsKind.Windows }
        if platform == "freebsd" { kind = OsKind.FreeBsd }
        if platform == "wasm" { kind = OsKind.Wasm }
        String detectedName = osNameRaw()
        if detectedName == "" {
            if kind == OsKind.MacOS { detectedName = "macOS" }
            if kind == OsKind.Linux { detectedName = "Linux" }
            if kind == OsKind.Windows { detectedName = "Windows" }
            if kind == OsKind.FreeBsd { detectedName = "FreeBSD" }
            if kind == OsKind.Wasm { detectedName = "WebAssembly" }
            if kind == OsKind.Unknown { detectedName = "unknown" }
        }
        String architecture = archRaw()
        if architecture == "" { architecture = "unknown" }
        Bool containerized = false
        if isContainerizedRaw() != 0 { containerized = true }
        return new OsInfo(kind, osKindFamily(kind), detectedName, osVersionRaw(),
            kernelVersionRaw(), architecture, hostnameRaw(), "", libcVersionRaw(),
            containerized)
    }
}

// ---------- OsProfile ----------
class OsProfile {
    final String _name
    final OsInfo _info
    final List<OsCapability> _capabilities

    OsProfile(String name, OsInfo info, List<OsCapability> capabilities) {
        if name == null || name == "" {
            throw "OsProfile: empty name"
        }
        if info == null || capabilities == null {
            throw "OsProfile: null field"
        }
        self._name = name
        self._info = info
        List<OsCapability> collected = []
        self._capabilities = collected
        Int index = 0
        while index < capabilities.length() {
            OsCapability capability = capabilities.get(index)
            if !self.has(capability) {
                self._capabilities.push(capability)
            }
            index = index + 1
        }
    }

    String name() { return self._name }
    OsInfo info() { return self._info }
    OsKind kind() { return self._info.kind() }
    OsFamily family() { return self._info.family() }

    List<OsCapability> capabilities() {
        return self._capabilities.copy()
    }

    Bool has(OsCapability capability) {
        Int index = 0
        while index < self._capabilities.length() {
            if self._capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    List<OsCapability> missing(List<OsCapability> required) {
        if required == null {
            throw "OsProfile.missing: null list"
        }
        List<OsCapability> result = []
        Int index = 0
        while index < required.length() {
            OsCapability capability = required.get(index)
            if !self.has(capability) {
                result.push(capability)
            }
            index = index + 1
        }
        return result
    }

    OsProfile withCapability(OsCapability capability) {
        List<OsCapability> next = self.capabilities()
        if !self.has(capability) {
            next.push(capability)
        }
        return new OsProfile(self._name, self._info, next)
    }

    OsProfile withoutCapability(OsCapability capability) {
        List<OsCapability> next = []
        Int index = 0
        while index < self._capabilities.length() {
            if self._capabilities.get(index) != capability {
                next.push(self._capabilities.get(index))
            }
            index = index + 1
        }
        return new OsProfile(self._name, self._info, next)
    }

    OsProfile withName(String value) {
        if value == null || value == "" {
            throw "OsProfile.withName: empty"
        }
        return new OsProfile(value, self._info, self.capabilities())
    }

    String describe() {
        return "os " + self._name + " kind=" + osKindName(self._info.kind()) +
            " caps=" + str(self._capabilities.length())
    }

    Bool equals(OsProfile other) {
        if other == null { return false }
        if self._name != other.name() { return false }
        if !self._info.equals(other.info()) { return false }
        List<OsCapability> values = other.capabilities()
        if self._capabilities.length() != values.length() { return false }
        Int index = 0
        while index < values.length() {
            if !self.has(values.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    OsProfile copy() {
        return new OsProfile(self._name, self._info.copy(), self.capabilities())
    }
}

// ---------- 静态 helper ----------
// Os.detectProfile 属于 xdk.os.host.Os；本批以顶层 helper 提供等价能力。
OsProfile osDetectProfile() {
    OsInfo info = OsInfo.detect()
    List<OsCapability> capabilities = []
    if info.isContainerized() {
        capabilities.push(OsCapability.Container)
    }
    String name = osKindName(info.kind()) + "-headless"
    if info.isContainerized() { name = name + "-container" }
    return new OsProfile(name, info, capabilities)
}
