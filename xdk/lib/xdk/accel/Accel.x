// xdk.accel —— 统一加速器对象模型（A8）
//
// 本实现只提供值对象、句柄生命周期与命令录制状态机；本机没有
// CUDA/ROCm/Vulkan/Metal 等后端，所有真实设备/内存/程序/提交路径在完成
// 参数与状态校验后返回 Unsupported，不做模拟执行。
//
// 与设计文档的偏差：
// - 四个枚举均把 Unknown 放在首位；编译器把枚举 0 当作 null，Unknown
//   不能作为普通成员追加。
// - Accel.fromGpuAdapter 未实现：xdk.gpu/xdk.os.gpu 仍是 design，
//   当前没有 GpuAdapter 类型可依赖。
// - 设计文档中的 accelerator*Raw 原生适配器未实现；所有 close 是逻辑
//   关闭，幂等且不触碰原生句柄。
package xdk.accel
import xdk.errors
import xdk.bytes

// ---------- AcceleratorKind ----------
// Unknown 放首位：编译器把枚举 0 当作 null。
enum AcceleratorKind {
    Unknown,
    Cpu,
    Gpu,
    Npu,
    Dsp,
    Fpga,
    Asic,
    Lpu,
    Ipu,
    Hpu,
    Dpu,
    Vpu,
    Mcu,
    Other,
}

String acceleratorKindName(AcceleratorKind kind) {
    if kind == AcceleratorKind.Unknown { return "unknown" }
    if kind == AcceleratorKind.Cpu { return "cpu" }
    if kind == AcceleratorKind.Gpu { return "gpu" }
    if kind == AcceleratorKind.Npu { return "npu" }
    if kind == AcceleratorKind.Dsp { return "dsp" }
    if kind == AcceleratorKind.Fpga { return "fpga" }
    if kind == AcceleratorKind.Asic { return "asic" }
    if kind == AcceleratorKind.Lpu { return "lpu" }
    if kind == AcceleratorKind.Ipu { return "ipu" }
    if kind == AcceleratorKind.Hpu { return "hpu" }
    if kind == AcceleratorKind.Dpu { return "dpu" }
    if kind == AcceleratorKind.Vpu { return "vpu" }
    if kind == AcceleratorKind.Mcu { return "mcu" }
    return "other"
}

AcceleratorKind? acceleratorKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unknown" { return AcceleratorKind.Unknown }
    if normalized == "cpu" { return AcceleratorKind.Cpu }
    if normalized == "gpu" { return AcceleratorKind.Gpu }
    if normalized == "npu" { return AcceleratorKind.Npu }
    if normalized == "dsp" { return AcceleratorKind.Dsp }
    if normalized == "fpga" { return AcceleratorKind.Fpga }
    if normalized == "asic" { return AcceleratorKind.Asic }
    if normalized == "lpu" { return AcceleratorKind.Lpu }
    if normalized == "ipu" { return AcceleratorKind.Ipu }
    if normalized == "hpu" { return AcceleratorKind.Hpu }
    if normalized == "dpu" { return AcceleratorKind.Dpu }
    if normalized == "vpu" { return AcceleratorKind.Vpu }
    if normalized == "mcu" { return AcceleratorKind.Mcu }
    if normalized == "other" { return AcceleratorKind.Other }
    return null
}

// ---------- AcceleratorBackend ----------
enum AcceleratorBackend {
    Unknown,
    Cuda,
    Rocm,
    Sycl,
    OpenCl,
    Vulkan,
    Metal,
    DirectMl,
    OneApi,
    Custom,
    Cpu,
}

String acceleratorBackendName(AcceleratorBackend backend) {
    if backend == AcceleratorBackend.Unknown { return "unknown" }
    if backend == AcceleratorBackend.Cuda { return "cuda" }
    if backend == AcceleratorBackend.Rocm { return "rocm" }
    if backend == AcceleratorBackend.Sycl { return "sycl" }
    if backend == AcceleratorBackend.OpenCl { return "opencl" }
    if backend == AcceleratorBackend.Vulkan { return "vulkan" }
    if backend == AcceleratorBackend.Metal { return "metal" }
    if backend == AcceleratorBackend.DirectMl { return "directml" }
    if backend == AcceleratorBackend.OneApi { return "oneapi" }
    if backend == AcceleratorBackend.Custom { return "custom" }
    return "cpu"
}

AcceleratorBackend? acceleratorBackendFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unknown" { return AcceleratorBackend.Unknown }
    if normalized == "cuda" { return AcceleratorBackend.Cuda }
    if normalized == "rocm" { return AcceleratorBackend.Rocm }
    if normalized == "sycl" { return AcceleratorBackend.Sycl }
    if normalized == "opencl" { return AcceleratorBackend.OpenCl }
    if normalized == "vulkan" { return AcceleratorBackend.Vulkan }
    if normalized == "metal" { return AcceleratorBackend.Metal }
    if normalized == "directml" { return AcceleratorBackend.DirectMl }
    if normalized == "oneapi" { return AcceleratorBackend.OneApi }
    if normalized == "custom" { return AcceleratorBackend.Custom }
    if normalized == "cpu" { return AcceleratorBackend.Cpu }
    return null
}

// ---------- AcceleratorVendor ----------
enum AcceleratorVendor {
    Unknown,
    Intel,
    Nvidia,
    Amd,
    Apple,
    Qualcomm,
    Arm,
    Imagination,
    Google,
    Microsoft,
    Amazon,
    Samsung,
    Huawei,
    MediaTek,
    Broadcom,
    Marvell,
    Nxp,
    TexasInstruments,
    STMicroelectronics,
    Infineon,
    Renesas,
    Microchip,
    Lattice,
    Xilinx,
    Altera,
    Cerebras,
    Graphcore,
    Groq,
    SambaNova,
    Tenstorrent,
    Hailo,
    Rockchip,
    Espressif,
    NordicSemiconductor,
    SiFive,
    Other,
}

String acceleratorVendorName(AcceleratorVendor vendor) {
    if vendor == AcceleratorVendor.Unknown { return "unknown" }
    if vendor == AcceleratorVendor.Intel { return "intel" }
    if vendor == AcceleratorVendor.Nvidia { return "nvidia" }
    if vendor == AcceleratorVendor.Amd { return "amd" }
    if vendor == AcceleratorVendor.Apple { return "apple" }
    if vendor == AcceleratorVendor.Qualcomm { return "qualcomm" }
    if vendor == AcceleratorVendor.Arm { return "arm" }
    if vendor == AcceleratorVendor.Imagination { return "imagination" }
    if vendor == AcceleratorVendor.Google { return "google" }
    if vendor == AcceleratorVendor.Microsoft { return "microsoft" }
    if vendor == AcceleratorVendor.Amazon { return "amazon" }
    if vendor == AcceleratorVendor.Samsung { return "samsung" }
    if vendor == AcceleratorVendor.Huawei { return "huawei" }
    if vendor == AcceleratorVendor.MediaTek { return "mediatek" }
    if vendor == AcceleratorVendor.Broadcom { return "broadcom" }
    if vendor == AcceleratorVendor.Marvell { return "marvell" }
    if vendor == AcceleratorVendor.Nxp { return "nxp" }
    if vendor == AcceleratorVendor.TexasInstruments { return "texas_instruments" }
    if vendor == AcceleratorVendor.STMicroelectronics { return "stmicroelectronics" }
    if vendor == AcceleratorVendor.Infineon { return "infineon" }
    if vendor == AcceleratorVendor.Renesas { return "renesas" }
    if vendor == AcceleratorVendor.Microchip { return "microchip" }
    if vendor == AcceleratorVendor.Lattice { return "lattice" }
    if vendor == AcceleratorVendor.Xilinx { return "xilinx" }
    if vendor == AcceleratorVendor.Altera { return "altera" }
    if vendor == AcceleratorVendor.Cerebras { return "cerebras" }
    if vendor == AcceleratorVendor.Graphcore { return "graphcore" }
    if vendor == AcceleratorVendor.Groq { return "groq" }
    if vendor == AcceleratorVendor.SambaNova { return "sambanova" }
    if vendor == AcceleratorVendor.Tenstorrent { return "tenstorrent" }
    if vendor == AcceleratorVendor.Hailo { return "hailo" }
    if vendor == AcceleratorVendor.Rockchip { return "rockchip" }
    if vendor == AcceleratorVendor.Espressif { return "espressif" }
    if vendor == AcceleratorVendor.NordicSemiconductor { return "nordic_semiconductor" }
    if vendor == AcceleratorVendor.SiFive { return "sifive" }
    return "other"
}

AcceleratorVendor? acceleratorVendorFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unknown" { return AcceleratorVendor.Unknown }
    if normalized == "intel" { return AcceleratorVendor.Intel }
    if normalized == "nvidia" { return AcceleratorVendor.Nvidia }
    if normalized == "amd" { return AcceleratorVendor.Amd }
    if normalized == "apple" { return AcceleratorVendor.Apple }
    if normalized == "qualcomm" { return AcceleratorVendor.Qualcomm }
    if normalized == "arm" { return AcceleratorVendor.Arm }
    if normalized == "imagination" { return AcceleratorVendor.Imagination }
    if normalized == "google" { return AcceleratorVendor.Google }
    if normalized == "microsoft" { return AcceleratorVendor.Microsoft }
    if normalized == "amazon" { return AcceleratorVendor.Amazon }
    if normalized == "samsung" { return AcceleratorVendor.Samsung }
    if normalized == "huawei" { return AcceleratorVendor.Huawei }
    if normalized == "mediatek" { return AcceleratorVendor.MediaTek }
    if normalized == "broadcom" { return AcceleratorVendor.Broadcom }
    if normalized == "marvell" { return AcceleratorVendor.Marvell }
    if normalized == "nxp" { return AcceleratorVendor.Nxp }
    if normalized == "texas_instruments" { return AcceleratorVendor.TexasInstruments }
    if normalized == "stmicroelectronics" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "infineon" { return AcceleratorVendor.Infineon }
    if normalized == "renesas" { return AcceleratorVendor.Renesas }
    if normalized == "microchip" { return AcceleratorVendor.Microchip }
    if normalized == "lattice" { return AcceleratorVendor.Lattice }
    if normalized == "xilinx" { return AcceleratorVendor.Xilinx }
    if normalized == "altera" { return AcceleratorVendor.Altera }
    if normalized == "cerebras" { return AcceleratorVendor.Cerebras }
    if normalized == "graphcore" { return AcceleratorVendor.Graphcore }
    if normalized == "groq" { return AcceleratorVendor.Groq }
    if normalized == "sambanova" { return AcceleratorVendor.SambaNova }
    if normalized == "tenstorrent" { return AcceleratorVendor.Tenstorrent }
    if normalized == "hailo" { return AcceleratorVendor.Hailo }
    if normalized == "rockchip" { return AcceleratorVendor.Rockchip }
    if normalized == "espressif" { return AcceleratorVendor.Espressif }
    if normalized == "nordic_semiconductor" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "sifive" { return AcceleratorVendor.SiFive }
    if normalized == "other" { return AcceleratorVendor.Other }
    return null
}

AcceleratorVendor acceleratorVendorFromText(String text) {
    if text == null { return AcceleratorVendor.Unknown }
    String normalized = text.trim().toLower()
    if normalized == "" { return AcceleratorVendor.Unknown }
    if normalized == "unknown" { return AcceleratorVendor.Unknown }
    if normalized == "intel" { return AcceleratorVendor.Intel }
    if normalized == "nvidia" { return AcceleratorVendor.Nvidia }
    if normalized == "amd" { return AcceleratorVendor.Amd }
    if normalized == "advanced micro devices" { return AcceleratorVendor.Amd }
    if normalized == "apple" { return AcceleratorVendor.Apple }
    if normalized == "qualcomm" { return AcceleratorVendor.Qualcomm }
    if normalized == "arm" { return AcceleratorVendor.Arm }
    if normalized == "imagination" { return AcceleratorVendor.Imagination }
    if normalized == "imagination technologies" { return AcceleratorVendor.Imagination }
    if normalized == "google" { return AcceleratorVendor.Google }
    if normalized == "microsoft" { return AcceleratorVendor.Microsoft }
    if normalized == "amazon" { return AcceleratorVendor.Amazon }
    if normalized == "aws" { return AcceleratorVendor.Amazon }
    if normalized == "samsung" { return AcceleratorVendor.Samsung }
    if normalized == "huawei" { return AcceleratorVendor.Huawei }
    if normalized == "mediatek" { return AcceleratorVendor.MediaTek }
    if normalized == "broadcom" { return AcceleratorVendor.Broadcom }
    if normalized == "marvell" { return AcceleratorVendor.Marvell }
    if normalized == "nxp" { return AcceleratorVendor.Nxp }
    if normalized == "texas instruments" { return AcceleratorVendor.TexasInstruments }
    if normalized == "ti" { return AcceleratorVendor.TexasInstruments }
    if normalized == "stmicroelectronics" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "st" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "infineon" { return AcceleratorVendor.Infineon }
    if normalized == "renesas" { return AcceleratorVendor.Renesas }
    if normalized == "microchip" { return AcceleratorVendor.Microchip }
    if normalized == "lattice" { return AcceleratorVendor.Lattice }
    if normalized == "xilinx" { return AcceleratorVendor.Xilinx }
    if normalized == "altera" { return AcceleratorVendor.Altera }
    if normalized == "cerebras" { return AcceleratorVendor.Cerebras }
    if normalized == "graphcore" { return AcceleratorVendor.Graphcore }
    if normalized == "groq" { return AcceleratorVendor.Groq }
    if normalized == "sambanova" { return AcceleratorVendor.SambaNova }
    if normalized == "samba nova" { return AcceleratorVendor.SambaNova }
    if normalized == "tenstorrent" { return AcceleratorVendor.Tenstorrent }
    if normalized == "hailo" { return AcceleratorVendor.Hailo }
    if normalized == "rockchip" { return AcceleratorVendor.Rockchip }
    if normalized == "espressif" { return AcceleratorVendor.Espressif }
    if normalized == "nordic" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "nordic semiconductor" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "sifive" { return AcceleratorVendor.SiFive }
    if normalized == "si five" { return AcceleratorVendor.SiFive }
    return AcceleratorVendor.Other
}

// ---------- AcceleratorCapability ----------
enum AcceleratorCapability {
    Unknown,
    Memory,
    Compute,
    Graphics,
    Reconfigurable,
    Quantized,
    LowPower,
    Other,
}

String acceleratorCapabilityName(AcceleratorCapability capability) {
    if capability == AcceleratorCapability.Unknown { return "unknown" }
    if capability == AcceleratorCapability.Memory { return "memory" }
    if capability == AcceleratorCapability.Compute { return "compute" }
    if capability == AcceleratorCapability.Graphics { return "graphics" }
    if capability == AcceleratorCapability.Reconfigurable { return "reconfigurable" }
    if capability == AcceleratorCapability.Quantized { return "quantized" }
    if capability == AcceleratorCapability.LowPower { return "low_power" }
    return "other"
}

AcceleratorCapability? acceleratorCapabilityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unknown" { return AcceleratorCapability.Unknown }
    if normalized == "memory" { return AcceleratorCapability.Memory }
    if normalized == "compute" { return AcceleratorCapability.Compute }
    if normalized == "graphics" { return AcceleratorCapability.Graphics }
    if normalized == "reconfigurable" { return AcceleratorCapability.Reconfigurable }
    if normalized == "quantized" { return AcceleratorCapability.Quantized }
    if normalized == "low_power" { return AcceleratorCapability.LowPower }
    if normalized == "other" { return AcceleratorCapability.Other }
    return null
}

// ---------- Accelerator ----------
class Accelerator {
    final String _acceleratorId
    final String _name
    final AcceleratorVendor _vendor
    final String _vendorName
    final AcceleratorKind _kind
    final AcceleratorBackend _backend
    final String _runtimeVersion
    final Long _memoryBytes
    final Int _computeUnitCount
    final List<AcceleratorCapability> _capabilities

    Accelerator(String acceleratorId, String name, AcceleratorVendor vendor,
                String vendorName, AcceleratorKind kind,
                AcceleratorBackend backend, String runtimeVersion,
                Long memoryBytes, Int computeUnitCount,
                List<AcceleratorCapability> capabilities) {
        if acceleratorId == null || acceleratorId == "" || name == null
            || vendorName == null || runtimeVersion == null
            || capabilities == null {
            throw "Accelerator: invalid field"
        }
        if memoryBytes < (0 as Long) || computeUnitCount < 0 {
            throw "Accelerator: negative value"
        }
        // Unknown 是枚举 0，编译器把它当作 null；这里把 null 归一为 Unknown。
        AcceleratorVendor normalizedVendor = vendor
        if normalizedVendor == null {
            normalizedVendor = AcceleratorVendor.Unknown
        }
        AcceleratorKind normalizedKind = kind
        if normalizedKind == null {
            normalizedKind = AcceleratorKind.Unknown
        }
        AcceleratorBackend normalizedBackend = backend
        if normalizedBackend == null {
            normalizedBackend = AcceleratorBackend.Unknown
        }
        List<AcceleratorCapability> normalized = []
        Int index = 0
        while index < capabilities.length() {
            AcceleratorCapability capability = capabilities.get(index)
            if capability == null { throw "Accelerator: null capability" }
            Bool exists = false
            Int scan = 0
            while scan < normalized.length() {
                if normalized.get(scan) == capability {
                    exists = true
                    break
                }
                scan = scan + 1
            }
            if !exists { normalized.push(capability) }
            index = index + 1
        }
        self._acceleratorId = acceleratorId
        self._name = name
        self._vendor = normalizedVendor
        self._vendorName = vendorName
        self._kind = normalizedKind
        self._backend = normalizedBackend
        self._runtimeVersion = runtimeVersion
        self._memoryBytes = memoryBytes
        self._computeUnitCount = computeUnitCount
        self._capabilities = normalized
    }

    String acceleratorId() { return self._acceleratorId }
    String name() { return self._name }
    AcceleratorVendor vendor() { return self._vendor }
    String vendorName() { return self._vendorName }
    AcceleratorKind kind() { return self._kind }
    AcceleratorBackend backend() { return self._backend }
    String runtimeVersion() { return self._runtimeVersion }
    Long memoryBytes() { return self._memoryBytes }
    Int computeUnitCount() { return self._computeUnitCount }
    List<AcceleratorCapability> capabilities() { return self._capabilities.copy() }

    Bool supports(AcceleratorCapability capability) {
        if capability == null { throw "Accelerator.supports: null capability" }
        Int index = 0
        while index < self._capabilities.length() {
            if self._capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        return "accel " + self._acceleratorId
            + " kind=" + acceleratorKindName(self._kind)
            + " backend=" + acceleratorBackendName(self._backend)
            + " vendor=" + acceleratorVendorName(self._vendor)
            + " name=" + self._name
            + " memory=" + str(self._memoryBytes)
            + " units=" + str(self._computeUnitCount)
    }

    Bool equals(Accelerator other) {
        if other == null { return false }
        if self._acceleratorId != other.acceleratorId()
            || self._name != other.name()
            || self._vendor != other.vendor()
            || self._vendorName != other.vendorName()
            || self._kind != other.kind()
            || self._backend != other.backend()
            || self._runtimeVersion != other.runtimeVersion()
            || self._memoryBytes != other.memoryBytes()
            || self._computeUnitCount != other.computeUnitCount() {
            return false
        }
        List<AcceleratorCapability> otherCapabilities = other.capabilities()
        if self._capabilities.length() != otherCapabilities.length() { return false }
        Int index = 0
        while index < self._capabilities.length() {
            if self._capabilities.get(index) != otherCapabilities.get(index) {
                return false
            }
            index = index + 1
        }
        return true
    }

    Accelerator copy() {
        return new Accelerator(self._acceleratorId, self._name, self._vendor,
            self._vendorName, self._kind, self._backend, self._runtimeVersion,
            self._memoryBytes, self._computeUnitCount, self._capabilities)
    }
}

// ---------- AcceleratorOptions ----------
class AcceleratorOptions {
    final String _label
    final Bool _enableProfiling
    final Bool _enableValidation
    final Long _memoryLimitBytes
    final String _codeFormat
    final List<String> _loadOptions
    final Int _queuePriority

    AcceleratorOptions(String label, Bool enableProfiling, Bool enableValidation,
                       Long memoryLimitBytes, String codeFormat,
                       List<String> loadOptions, Int queuePriority) {
        if label == null || codeFormat == null || loadOptions == null {
            throw "AcceleratorOptions: null field"
        }
        if memoryLimitBytes < (0 as Long) {
            throw "AcceleratorOptions: negative memory limit"
        }
        if queuePriority < -100 || queuePriority > 100 {
            throw "AcceleratorOptions: priority out of range"
        }
        Int index = 0
        while index < loadOptions.length() {
            String option = loadOptions.get(index)
            if option == null || option == "" {
                throw "AcceleratorOptions: empty load option"
            }
            index = index + 1
        }
        self._label = label
        self._enableProfiling = enableProfiling
        self._enableValidation = enableValidation
        self._memoryLimitBytes = memoryLimitBytes
        self._codeFormat = codeFormat
        self._loadOptions = loadOptions.copy()
        self._queuePriority = queuePriority
    }

    static AcceleratorOptions defaults() {
        List<String> loadOptions = []
        return new AcceleratorOptions("", false, false, 0 as Long, "", loadOptions, 0)
    }

    String label() { return self._label }
    Bool isProfilingEnabled() { return self._enableProfiling }
    Bool isValidationEnabled() { return self._enableValidation }
    Long memoryLimitBytes() { return self._memoryLimitBytes }
    String codeFormat() { return self._codeFormat }
    List<String> loadOptions() { return self._loadOptions.copy() }
    Int queuePriority() { return self._queuePriority }

    Bool equals(AcceleratorOptions other) {
        if other == null { return false }
        if self._label != other.label()
            || self._enableProfiling != other.isProfilingEnabled()
            || self._enableValidation != other.isValidationEnabled()
            || self._memoryLimitBytes != other.memoryLimitBytes()
            || self._codeFormat != other.codeFormat()
            || self._queuePriority != other.queuePriority() {
            return false
        }
        List<String> otherOptions = other.loadOptions()
        if self._loadOptions.length() != otherOptions.length() { return false }
        Int index = 0
        while index < self._loadOptions.length() {
            if self._loadOptions.get(index) != otherOptions.get(index) {
                return false
            }
            index = index + 1
        }
        return true
    }

    AcceleratorOptions copy() {
        return new AcceleratorOptions(self._label, self._enableProfiling,
            self._enableValidation, self._memoryLimitBytes, self._codeFormat,
            self._loadOptions, self._queuePriority)
    }

    String describe() {
        return "accel options label=" + self._label
            + " format=" + self._codeFormat
            + " priority=" + str(self._queuePriority)
            + " limit=" + str(self._memoryLimitBytes)
            + " profiling=" + str(self._enableProfiling)
            + " validation=" + str(self._enableValidation)
    }
}

Result<Unit, Error> acceleratorOptionsCheckOpen(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckOpen: null options" }
    if options.codeFormat() != "" || options.loadOptions().length() != 0
        || options.queuePriority() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for open"))
    }
    return Ok()
}

Result<Unit, Error> acceleratorOptionsCheckProgram(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckProgram: null options" }
    if options.isProfilingEnabled() || options.isValidationEnabled()
        || options.memoryLimitBytes() != (0 as Long)
        || options.queuePriority() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for program"))
    }
    return Ok()
}

Result<Unit, Error> acceleratorOptionsCheckQueue(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckQueue: null options" }
    if options.isProfilingEnabled() || options.isValidationEnabled()
        || options.memoryLimitBytes() != (0 as Long)
        || options.codeFormat() != "" || options.loadOptions().length() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for queue"))
    }
    return Ok()
}

// ---------- AcceleratorDevice ----------
class AcceleratorDevice {
    final Long _handle
    final Accelerator _accelerator
    final AcceleratorOptions _options
    final List<AcceleratorQueue> _queues
    Bool _open

    AcceleratorDevice(Long handle, Accelerator accelerator,
                      AcceleratorOptions options) {
        if handle <= (0 as Long) || accelerator == null || options == null {
            throw "AcceleratorDevice: invalid field"
        }
        self._handle = handle
        self._accelerator = accelerator
        self._options = options.copy()
        self._queues = []
        self._open = true
    }

    Long deviceHandle() { return self._handle }
    Accelerator accelerator() { return self._accelerator }
    String acceleratorId() { return self._accelerator.acceleratorId() }
    AcceleratorKind kind() { return self._accelerator.kind() }
    AcceleratorBackend backend() { return self._accelerator.backend() }
    AcceleratorVendor vendor() { return self._accelerator.vendor() }
    AcceleratorOptions options() { return self._options.copy() }
    Long memoryLimitBytes() { return self._options.memoryLimitBytes() }
    Bool isOpen() { return self._open }

    Result<Long, Error> totalMemoryBytes(Context context) {
        if context == null { throw "AcceleratorDevice.totalMemoryBytes: null context" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Long, Error> availableMemoryBytes(Context context) {
        if context == null {
            throw "AcceleratorDevice.availableMemoryBytes: null context"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorMemory, Error> allocateMemory(Context context,
                                                    Long sizeBytes,
                                                    Bool hostVisible) {
        if context == null { throw "AcceleratorDevice.allocateMemory: null context" }
        if sizeBytes <= (0 as Long) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid memory size"))
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !self._accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory unsupported"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorQueue, Error> createQueue(Context context,
                                                AcceleratorOptions options) {
        if context == null || options == null {
            throw "AcceleratorDevice.createQueue: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !self._accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "compute unsupported"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckQueue(options)
        if checked.isErr() { return Err(checked.error()) }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorProgram, Error> createProgram(Context context, Bytes code,
                                                    AcceleratorOptions options) {
        if context == null || code == null || options == null {
            throw "AcceleratorDevice.createProgram: null argument"
        }
        if code.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty program code"))
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !self._accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "compute unsupported"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckProgram(options)
        if checked.isErr() { return Err(checked.error()) }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorKernel, Error> createKernel(Context context,
                                                  AcceleratorProgram program,
                                                  String kernelName) {
        if context == null || program == null || kernelName == null {
            throw "AcceleratorDevice.createKernel: null argument"
        }
        if kernelName == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty kernel name"))
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if program.device() != self {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "program from another device"))
        }
        if !program.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator program"))
        }
        if !self._accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "compute unsupported"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorCommandBuffer, Error> createCommandBuffer(
            Context context, AcceleratorQueue queue) {
        if context == null || queue == null {
            throw "AcceleratorDevice.createCommandBuffer: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !queue.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator queue"))
        }
        Bool found = false
        Int index = 0
        while index < self._queues.length() {
            if self._queues.get(index) == queue {
                found = true
                break
            }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "queue from another device"))
        }
        if !self._accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "compute unsupported"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<AcceleratorFence, Error> createFence(
            Context context, AcceleratorCommandBuffer commandBuffer) {
        if context == null || commandBuffer == null {
            throw "AcceleratorDevice.createFence: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if commandBuffer.device() != self {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer from another device"))
        }
        if !commandBuffer.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if commandBuffer.isSubmitted() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer submitted"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        Result<Unit, Error> first = Ok()
        Bool hasError = false
        Int index = 0
        while index < self._queues.length() {
            Result<Unit, Error> queueResult = self._queues.get(index).close()
            if queueResult.isErr() && !hasError {
                first = Err(queueResult.error())
                hasError = true
            }
            index = index + 1
        }
        if hasError { return first }
        return Ok()
    }
}

// ---------- AcceleratorMemory ----------
class AcceleratorMemory {
    final Long _handle
    final AcceleratorDevice _device
    final Long _sizeBytes
    final Bool _hostVisible
    final Bool _unified
    Bool _open

    AcceleratorMemory(Long handle, AcceleratorDevice device, Long sizeBytes,
                      Bool hostVisible, Bool unified) {
        if handle <= (0 as Long) || device == null || sizeBytes <= (0 as Long) {
            throw "AcceleratorMemory: invalid field"
        }
        if unified && !hostVisible {
            throw "AcceleratorMemory: unified not host visible"
        }
        self._handle = handle
        self._device = device
        self._sizeBytes = sizeBytes
        self._hostVisible = hostVisible
        self._unified = unified
        self._open = true
    }

    Long memoryHandle() { return self._handle }
    AcceleratorDevice device() { return self._device }
    Long sizeBytes() { return self._sizeBytes }
    Bool isHostVisible() { return self._hostVisible }
    Bool isUnified() { return self._unified }
    Bool isOpen() { return self._open }

    Result<Unit, Error> write(Context context, Long offsetBytes, Bytes source) {
        if context == null || source == null {
            throw "AcceleratorMemory.write: null argument"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
        }
        if !self._hostVisible {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory is not host visible"))
        }
        if offsetBytes < (0 as Long) || offsetBytes > self._sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "offset out of range"))
        }
        if (source.length() as Long) > self._sizeBytes - offsetBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "source too large"))
        }
        if source.length() == 0 { return Ok() }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> read(Context context, Long offsetBytes, Bytes target) {
        if context == null || target == null {
            throw "AcceleratorMemory.read: null argument"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
        }
        if !self._hostVisible {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory is not host visible"))
        }
        if offsetBytes < (0 as Long) || offsetBytes > self._sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "offset out of range"))
        }
        if (target.length() as Long) > self._sizeBytes - offsetBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "target too large"))
        }
        if target.length() == 0 { return Ok() }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        if !self._device.isOpen() { return Ok() }
        return Ok()
    }
}

// ---------- AcceleratorProgram ----------
class AcceleratorProgram {
    final Long _handle
    final AcceleratorDevice _device
    final Long _codeSizeBytes
    final String _codeFormat
    Bool _open

    AcceleratorProgram(Long handle, AcceleratorDevice device,
                       Long codeSizeBytes, String codeFormat) {
        if handle <= (0 as Long) || device == null
            || codeSizeBytes <= (0 as Long) {
            throw "AcceleratorProgram: invalid field"
        }
        if codeFormat == null {
            throw "AcceleratorProgram: null format"
        }
        self._handle = handle
        self._device = device
        self._codeSizeBytes = codeSizeBytes
        self._codeFormat = codeFormat
        self._open = true
    }

    Long programHandle() { return self._handle }
    AcceleratorDevice device() { return self._device }
    AcceleratorBackend backend() { return self._device.backend() }
    Long codeSizeBytes() { return self._codeSizeBytes }
    String codeFormat() { return self._codeFormat }
    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        if !self._device.isOpen() { return Ok() }
        return Ok()
    }
}

// ---------- AcceleratorKernel ----------
class AcceleratorKernel {
    final Long _handle
    final AcceleratorProgram _program
    final String _kernelName
    Bool _open

    AcceleratorKernel(Long handle, AcceleratorProgram program,
                      String kernelName) {
        if handle <= (0 as Long) {
            throw "AcceleratorKernel: invalid handle"
        }
        if program == null { throw "AcceleratorKernel: null program" }
        if kernelName == null || kernelName == "" {
            throw "AcceleratorKernel: empty kernel name"
        }
        self._handle = handle
        self._program = program
        self._kernelName = kernelName
        self._open = true
    }

    Long kernelHandle() { return self._handle }
    AcceleratorProgram program() { return self._program }
    AcceleratorDevice device() { return self._program.device() }
    String kernelName() { return self._kernelName }
    AcceleratorBackend backend() { return self._program.backend() }
    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        if !self._program.isOpen() || !self._program.device().isOpen() {
            return Ok()
        }
        return Ok()
    }
}

// ---------- AcceleratorQueue ----------
class AcceleratorQueue {
    final Long _handle
    final Int _priority
    Bool _open

    AcceleratorQueue(Long handle, Int priority) {
        if handle <= (0 as Long) {
            throw "AcceleratorQueue: invalid handle"
        }
        if priority < -100 || priority > 100 {
            throw "AcceleratorQueue: priority out of range"
        }
        self._handle = handle
        self._priority = priority
        self._open = true
    }

    Long queueHandle() { return self._handle }
    Int priority() { return self._priority }
    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- AcceleratorCommandBuffer ----------
class AcceleratorCommandBuffer {
    final Long _handle
    final AcceleratorDevice _device
    final AcceleratorQueue _queue
    final Map<Int, AcceleratorMemory> _memoryBindings
    final Map<Int, Bytes> _valueBindings
    final List<AcceleratorKernel> _usedKernels
    final List<AcceleratorMemory> _usedMemories
    AcceleratorKernel? _kernel
    Int _dispatchCount
    Bool _recording
    Bool _ended
    Bool _submitted
    Bool _open

    AcceleratorCommandBuffer(Long handle, AcceleratorDevice device,
                             AcceleratorQueue queue) {
        if handle <= (0 as Long) {
            throw "AcceleratorCommandBuffer: invalid handle"
        }
        if device == null { throw "AcceleratorCommandBuffer: null device" }
        if queue == null { throw "AcceleratorCommandBuffer: null queue" }
        if !queue.isOpen() {
            throw "AcceleratorCommandBuffer: queue closed"
        }
        self._handle = handle
        self._device = device
        self._queue = queue
        Map<Int, AcceleratorMemory> memoryBindings = [:]
        Map<Int, Bytes> valueBindings = [:]
        self._memoryBindings = memoryBindings
        self._valueBindings = valueBindings
        self._usedKernels = []
        self._usedMemories = []
        self._kernel = null
        self._dispatchCount = 0
        self._recording = false
        self._ended = false
        self._submitted = false
        self._open = true
    }

    Long commandBufferHandle() { return self._handle }
    AcceleratorDevice device() { return self._device }
    AcceleratorQueue queue() { return self._queue }
    Bool isRecording() { return self._recording }
    Bool isSubmitted() { return self._submitted }
    Bool isOpen() { return self._open }

    Result<Unit, Error> begin(Context context) {
        if context == null {
            throw "AcceleratorCommandBuffer.begin: null context"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if self._recording || self._ended || self._submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid state"))
        }
        self._recording = true
        return Ok()
    }

    Result<Unit, Error> bindKernel(Context context, AcceleratorKernel kernel) {
        if context == null || kernel == null {
            throw "AcceleratorCommandBuffer.bindKernel: null argument"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._recording || self._ended || self._submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "not recording"))
        }
        if !kernel.isOpen() || !kernel.program().isOpen()
            || !kernel.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator kernel"))
        }
        if kernel.device() != self._device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "kernel from another device"))
        }
        self._kernel = kernel
        self._memoryBindings.clear()
        self._valueBindings.clear()
        return Ok()
    }

    Result<Unit, Error> bindMemory(Context context, Int argumentIndex,
                                   AcceleratorMemory memory, Long offsetBytes) {
        if context == null || memory == null {
            throw "AcceleratorCommandBuffer.bindMemory: null argument"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._recording || self._ended || self._submitted
            || self._kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no current kernel"))
        }
        if argumentIndex < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid argument index"))
        }
        if !memory.isOpen() || !memory.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator memory"))
        }
        if memory.device() != self._device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "memory from another device"))
        }
        if offsetBytes < (0 as Long) || offsetBytes >= memory.sizeBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid binding offset"))
        }
        self._memoryBindings.put(argumentIndex, memory)
        self._valueBindings.remove(argumentIndex)
        return Ok()
    }

    Result<Unit, Error> bindValue(Context context, Int argumentIndex,
                                  Bytes value) {
        if context == null || value == null {
            throw "AcceleratorCommandBuffer.bindValue: null argument"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._recording || self._ended || self._submitted
            || self._kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no current kernel"))
        }
        if argumentIndex < 0 || value.length() == 0 || value.length() > 16 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid value binding"))
        }
        Bytes storedValue = copy(value)
        self._valueBindings.put(argumentIndex, storedValue)
        self._memoryBindings.remove(argumentIndex)
        return Ok()
    }

    Result<Unit, Error> dispatch(Context context, Int groupCountX,
                                 Int groupCountY, Int groupCountZ,
                                 Int workGroupSizeX, Int workGroupSizeY,
                                 Int workGroupSizeZ) {
        if context == null {
            throw "AcceleratorCommandBuffer.dispatch: null context"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._recording || self._ended || self._submitted
            || self._kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "not recording"))
        }
        AcceleratorKernel currentKernel = self._kernel as AcceleratorKernel
        if !currentKernel.isOpen() || !currentKernel.program().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator kernel"))
        }
        if groupCountX <= 0 || groupCountY <= 0 || groupCountZ <= 0
            || workGroupSizeX <= 0 || workGroupSizeY <= 0
            || workGroupSizeZ <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid dispatch size"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> end(Context context) {
        if context == null {
            throw "AcceleratorCommandBuffer.end: null context"
        }
        if !self._open || !self._device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._recording || self._ended || self._submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "not recording"))
        }
        if self._dispatchCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no dispatch recorded"))
        }
        if self._kernel == null {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator kernel"))
        }
        AcceleratorKernel currentKernel = self._kernel as AcceleratorKernel
        if !currentKernel.isOpen() || !currentKernel.program().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator kernel"))
        }
        self._recording = false
        self._ended = true
        return Ok()
    }

    Result<Unit, Error> submit(Context context, AcceleratorFence fence) {
        if context == null || fence == null {
            throw "AcceleratorCommandBuffer.submit: null argument"
        }
        if !self._open || !self._device.isOpen() || !self._queue.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator command buffer"))
        }
        if !self._ended || self._submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid state"))
        }
        if !fence.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable,
                "accelerator fence"))
        }
        if fence.commandBuffer() != self {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "fence from another buffer"))
        }
        Int kernelIndex = 0
        while kernelIndex < self._usedKernels.length() {
            AcceleratorKernel usedKernel = self._usedKernels.get(kernelIndex)
            if !usedKernel.isOpen() || !usedKernel.program().isOpen()
                || !usedKernel.device().isOpen() {
                return Err(new BasicError(ErrorKind.Unavailable,
                    "accelerator kernel"))
            }
            kernelIndex = kernelIndex + 1
        }
        Int memoryIndex = 0
        while memoryIndex < self._usedMemories.length() {
            AcceleratorMemory usedMemory = self._usedMemories.get(memoryIndex)
            if !usedMemory.isOpen() || !usedMemory.device().isOpen() {
                return Err(new BasicError(ErrorKind.Unavailable,
                    "accelerator memory"))
            }
            memoryIndex = memoryIndex + 1
        }
        self._submitted = true
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._recording = false
        self._kernel = null
        self._memoryBindings.clear()
        self._valueBindings.clear()
        self._usedKernels.clear()
        self._usedMemories.clear()
        if !self._device.isOpen() { return Ok() }
        return Ok()
    }
}

// ---------- AcceleratorFence ----------
class AcceleratorFence {
    final Long _handle
    final AcceleratorCommandBuffer _commandBuffer
    Bool _signaled
    Bool _open

    AcceleratorFence(Long handle, AcceleratorCommandBuffer commandBuffer) {
        if handle <= (0 as Long) {
            throw "AcceleratorFence: invalid handle"
        }
        if commandBuffer == null {
            throw "AcceleratorFence: null command buffer"
        }
        if !commandBuffer.isOpen() {
            throw "AcceleratorFence: command buffer closed"
        }
        if commandBuffer.isSubmitted() {
            throw "AcceleratorFence: command buffer submitted"
        }
        self._handle = handle
        self._commandBuffer = commandBuffer
        self._signaled = false
        self._open = true
    }

    Long fenceHandle() { return self._handle }
    AcceleratorCommandBuffer commandBuffer() { return self._commandBuffer }
    Bool isOpen() { return self._open }

    Result<Unit, Error> wait(Context context, Long timeoutMillis) {
        if context == null { throw "AcceleratorFence.wait: null context" }
        if timeoutMillis < (0 as Long) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative timeout"))
        }
        if !self._open || !self._commandBuffer.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator fence"))
        }
        if !self._commandBuffer.isSubmitted() {
            if timeoutMillis == (0 as Long) {
                return Err(new BasicError(ErrorKind.Timeout,
                    "accelerator fence timeout"))
            }
            return Err(new BasicError(ErrorKind.Unsupported,
                "no accelerator backend"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Bool, Error> isSignaled() {
        if !self._open || !self._commandBuffer.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator fence"))
        }
        if !self._commandBuffer.isSubmitted() { return Ok(false) }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        if !self._commandBuffer.device().isOpen() { return Ok() }
        return Ok()
    }
}

// ---------- Accel ----------
class Accel {
    private Accel() { }

    static Result<AcceleratorDevice, Error> open(Context context,
                                                 Accelerator accelerator,
                                                 AcceleratorOptions options) {
        if context == null || accelerator == null || options == null {
            throw "Accel.open: null argument"
        }
        if !accelerator.supports(AcceleratorCapability.Compute)
            && !accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "accelerator has no usable capability"))
        }
        if options.memoryLimitBytes() > (0 as Long)
            && !accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory limit without memory capability"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckOpen(options)
        if checked.isErr() { return Err(checked.error()) }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no accelerator backend"))
    }

    static Accelerator cpu() {
        List<AcceleratorCapability> capabilities = [
            AcceleratorCapability.Memory,
            AcceleratorCapability.Compute
        ]
        return new Accelerator("cpu", "host-cpu", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", 0 as Long, 0,
            capabilities)
    }
}
