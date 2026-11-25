// xdk.os.memory —— 物理内存/NUMA/DIMM 快照（M20.2）
//
// 实现 NumaNode/MemoryModule/PhysicalMemory 子集。
// DIMM/SMBIOS 与深度 NUMA 本批不采集；检测失败返回 0/空，不 panic。
// 稳定性：preview。合同见 docs/design/platform/os/memory/。
package xdk.os.memory

// ---------- NumaNode ----------
class NumaNode {
    final Int _id
    final Long _memoryBytes
    final List<Int> _cpuIds

    NumaNode(Int nodeId, Long memoryBytes, List<Int> cpuIds) {
        if nodeId < 0 || memoryBytes < 0 as Long || cpuIds == null {
            throw "NumaNode: invalid field"
        }
        self._id = nodeId
        self._memoryBytes = memoryBytes
        self._cpuIds = cpuIds.copy()
    }

    Int id() { return self._id }
    Long memoryBytes() { return self._memoryBytes }
    List<Int> cpuIds() { return self._cpuIds.copy() }

    String describe() {
        return "numa " + str(self._id) + " memory=" + str(self._memoryBytes) +
            " cpus=" + str(self._cpuIds.length())
    }

    Bool equals(NumaNode other) {
        if other == null { return false }
        if self._id != other.id() || self._memoryBytes != other.memoryBytes() {
            return false
        }
        List<Int> values = other.cpuIds()
        if self._cpuIds.length() != values.length() { return false }
        Int index = 0
        while index < self._cpuIds.length() {
            if self._cpuIds.get(index) != values.get(index) { return false }
            index = index + 1
        }
        return true
    }

    NumaNode copy() {
        return new NumaNode(self._id, self._memoryBytes, self._cpuIds)
    }
}

// ---------- MemoryModule ----------
class MemoryModule {
    final String _slot
    final Long _sizeBytes
    final String _kind
    final Int _speedMhz
    final String _manufacturer
    final String _partNumber

    MemoryModule(String slot, Long sizeBytes, String kind, Int speedMhz,
                 String manufacturer, String partNumber) {
        if slot == null || kind == null || manufacturer == null ||
            partNumber == null {
            throw "MemoryModule: null string"
        }
        if sizeBytes < 0 as Long || speedMhz < 0 {
            throw "MemoryModule: negative field"
        }
        self._slot = slot
        self._sizeBytes = sizeBytes
        self._kind = kind
        self._speedMhz = speedMhz
        self._manufacturer = manufacturer
        self._partNumber = partNumber
    }

    String slot() { return self._slot }
    Long sizeBytes() { return self._sizeBytes }
    String kind() { return self._kind }
    Int speedMhz() { return self._speedMhz }
    String manufacturer() { return self._manufacturer }
    String partNumber() { return self._partNumber }

    String describe() {
        String text = "dimm " + self._slot
        text = text + " size=" + str(self._sizeBytes)
        text = text + " kind=" + self._kind
        text = text + " speed=" + str(self._speedMhz)
        return text
    }

    Bool equals(MemoryModule other) {
        if other == null { return false }
        return self._slot == other.slot() &&
            self._sizeBytes == other.sizeBytes() &&
            self._kind == other.kind() &&
            self._speedMhz == other.speedMhz() &&
            self._manufacturer == other.manufacturer() &&
            self._partNumber == other.partNumber()
    }

    MemoryModule copy() {
        return new MemoryModule(self._slot, self._sizeBytes, self._kind,
            self._speedMhz, self._manufacturer, self._partNumber)
    }
}

// ---------- PhysicalMemory ----------
class PhysicalMemory {
    final Long _totalBytes
    final Long _freeBytes
    final Long _availableBytes
    final List<MemoryModule> _modules
    final List<NumaNode> _numaNodes

    PhysicalMemory(Long totalBytes, Long freeBytes, Long availableBytes,
                   List<MemoryModule> modules, List<NumaNode> numaNodes) {
        if totalBytes < 0 as Long || freeBytes < 0 as Long || availableBytes < 0 as Long {
            throw "PhysicalMemory: negative size"
        }
        if modules == null || numaNodes == null {
            throw "PhysicalMemory: null list"
        }
        self._totalBytes = totalBytes
        self._freeBytes = freeBytes
        self._availableBytes = availableBytes
        self._modules = modules.copy()
        self._numaNodes = numaNodes.copy()
    }

    Long totalBytes() { return self._totalBytes }
    Long freeBytes() { return self._freeBytes }
    Long availableBytes() { return self._availableBytes }
    List<MemoryModule> modules() { return self._modules.copy() }
    List<NumaNode> numaNodes() { return self._numaNodes.copy() }
    Int moduleCount() { return self._modules.length() }
    Int numaNodeCount() { return self._numaNodes.length() }

    String describe() {
        String text = "memory total=" + str(self._totalBytes)
        text = text + " free=" + str(self._freeBytes)
        text = text + " available=" + str(self._availableBytes)
        text = text + " modules=" + str(self._modules.length())
        text = text + " numa=" + str(self._numaNodes.length())
        return text
    }

    Bool equals(PhysicalMemory other) {
        if other == null { return false }
        if self._totalBytes != other.totalBytes() ||
            self._freeBytes != other.freeBytes() ||
            self._availableBytes != other.availableBytes() {
            return false
        }
        List<MemoryModule> otherModules = other.modules()
        if self._modules.length() != otherModules.length() { return false }
        Int index = 0
        while index < self._modules.length() {
            if !self._modules.get(index).equals(otherModules.get(index)) {
                return false
            }
            index = index + 1
        }
        List<NumaNode> otherNodes = other.numaNodes()
        if self._numaNodes.length() != otherNodes.length() { return false }
        index = 0
        while index < self._numaNodes.length() {
            if !self._numaNodes.get(index).equals(otherNodes.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    PhysicalMemory copy() {
        return new PhysicalMemory(self._totalBytes, self._freeBytes,
            self._availableBytes, self._modules, self._numaNodes)
    }

    static PhysicalMemory detect() {
        Long total = sysctlInt64Raw("hw.memsize")
        if total < 0 as Long { total = 0 as Long }
        Long free = memoryFreeBytesRaw()
        if free < 0 as Long { free = 0 as Long }
        List<MemoryModule> modules = []
        List<NumaNode> nodes = []
        return new PhysicalMemory(total, free, free, modules, nodes)
    }
}
