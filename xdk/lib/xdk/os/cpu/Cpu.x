// xdk.os.cpu —— CPU 拓扑/缓存/亲和性（M20.2）
//
// 实现 CpuCacheKind/CpuCore/CpuCache/CpuTopology/CpuAffinity 子集。
// 绑定核 API 本批明确 Unsupported；DIMM/深度 NUMA 留后续。
// 稳定性：preview。合同见 docs/design/platform/os/cpu/。
package xdk.os.cpu
import xdk.errors

// ---------- CpuCacheKind ----------
enum CpuCacheKind {
    Data,
    Instruction,
    Unified,
    Unknown,
}

String cpuCacheKindName(CpuCacheKind kind) {
    if kind == CpuCacheKind.Data { return "data" }
    if kind == CpuCacheKind.Instruction { return "instruction" }
    if kind == CpuCacheKind.Unified { return "unified" }
    return "unknown"
}

CpuCacheKind? cpuCacheKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "data" { return CpuCacheKind.Data }
    if normalized == "instruction" { return CpuCacheKind.Instruction }
    if normalized == "unified" { return CpuCacheKind.Unified }
    if normalized == "unknown" { return CpuCacheKind.Unknown }
    return null
}

// ---------- CpuCore ----------
class CpuCore {
    final Int _id
    final Int _socketId
    final Int _coreId
    final Int _threadId
    final Int _numaNodeId
    final Int _frequencyMhz
    final Bool _isOnline

    CpuCore(Int id, Int socketId, Int coreId, Int threadId,
            Int numaNodeId, Int frequencyMhz, Bool isOnline) {
        if id < 0 || socketId < 0 || coreId < 0 || threadId < 0 ||
            numaNodeId < 0 || frequencyMhz < 0 {
            throw "CpuCore: negative field"
        }
        self._id = id
        self._socketId = socketId
        self._coreId = coreId
        self._threadId = threadId
        self._numaNodeId = numaNodeId
        self._frequencyMhz = frequencyMhz
        self._isOnline = isOnline
    }

    Int id() { return self._id }
    Int socketId() { return self._socketId }
    Int coreId() { return self._coreId }
    Int threadId() { return self._threadId }
    Int numaNodeId() { return self._numaNodeId }
    Int frequencyMhz() { return self._frequencyMhz }
    Bool isOnline() { return self._isOnline }

    String describe() {
        String text = "cpu " + str(self._id)
        text = text + " socket=" + str(self._socketId)
        text = text + " core=" + str(self._coreId)
        text = text + " thread=" + str(self._threadId)
        text = text + " numa=" + str(self._numaNodeId)
        text = text + " mhz=" + str(self._frequencyMhz)
        return text
    }

    Bool equals(CpuCore other) {
        if other == null { return false }
        return self._id == other.id() &&
            self._socketId == other.socketId() &&
            self._coreId == other.coreId() &&
            self._threadId == other.threadId() &&
            self._numaNodeId == other.numaNodeId() &&
            self._frequencyMhz == other.frequencyMhz() &&
            self._isOnline == other.isOnline()
    }

    CpuCore copy() {
        return new CpuCore(self._id, self._socketId, self._coreId,
            self._threadId, self._numaNodeId, self._frequencyMhz, self._isOnline)
    }
}

// ---------- CpuCache ----------
class CpuCache {
    final Int _level
    final CpuCacheKind _kind
    final Long _sizeBytes
    final Int _lineBytes
    final Int _sharedByCpuCount

    CpuCache(Int level, CpuCacheKind kind, Long sizeBytes,
             Int lineBytes, Int sharedByCpuCount) {
        if level <= 0 || sizeBytes < 0 as Long || lineBytes < 0 ||
            sharedByCpuCount < 0 {
            throw "CpuCache: invalid field"
        }
        self._level = level
        self._kind = kind
        self._sizeBytes = sizeBytes
        self._lineBytes = lineBytes
        self._sharedByCpuCount = sharedByCpuCount
    }

    Int level() { return self._level }
    CpuCacheKind kind() { return self._kind }
    Long sizeBytes() { return self._sizeBytes }
    Int lineBytes() { return self._lineBytes }
    Int sharedByCpuCount() { return self._sharedByCpuCount }

    String describe() {
        String text = "cache L" + str(self._level) + " " + cpuCacheKindName(self._kind)
        text = text + " size=" + str(self._sizeBytes)
        text = text + " line=" + str(self._lineBytes)
        text = text + " shared=" + str(self._sharedByCpuCount)
        return text
    }

    Bool equals(CpuCache other) {
        if other == null { return false }
        return self._level == other.level() &&
            self._kind == other.kind() &&
            self._sizeBytes == other.sizeBytes() &&
            self._lineBytes == other.lineBytes() &&
            self._sharedByCpuCount == other.sharedByCpuCount()
    }

    CpuCache copy() {
        return new CpuCache(self._level, self._kind, self._sizeBytes,
            self._lineBytes, self._sharedByCpuCount)
    }
}

// ---------- CpuTopology ----------
class CpuTopology {
    final List<CpuCore> _cores
    final List<CpuCache> _caches
    final List<String> _features
    final Int _socketCount
    final Int _numaNodeCount

    CpuTopology(List<CpuCore> cores, List<CpuCache> caches,
                List<String> features, Int socketCount, Int numaNodeCount) {
        if cores == null || caches == null || features == null {
            throw "CpuTopology: null list"
        }
        if socketCount < 0 || numaNodeCount < 0 {
            throw "CpuTopology: negative count"
        }
        self._cores = cores.copy()
        self._caches = caches.copy()
        self._features = features.copy()
        self._socketCount = socketCount
        self._numaNodeCount = numaNodeCount
    }

    List<CpuCore> cores() { return self._cores.copy() }
    List<CpuCache> caches() { return self._caches.copy() }
    List<String> features() { return self._features.copy() }
    Int socketCount() { return self._socketCount }
    Int numaNodeCount() { return self._numaNodeCount }
    Int logicalCoreCount() { return self._cores.length() }

    Int physicalCoreCount() {
        List<String> seen = []
        Int index = 0
        while index < self._cores.length() {
            CpuCore core = self._cores.get(index)
            String key = str(core.socketId()) + ":" + str(core.coreId())
            Bool exists = false
            Int scan = 0
            while scan < seen.length() {
                if seen.get(scan) == key { exists = true; break }
                scan = scan + 1
            }
            if !exists { seen.push(key) }
            index = index + 1
        }
        return seen.length()
    }

    CpuCore? findCore(Int id) {
        Int index = 0
        while index < self._cores.length() {
            CpuCore core = self._cores.get(index)
            if core.id() == id { return core }
            index = index + 1
        }
        return null
    }

    List<CpuCore> findByCore(Int socketId, Int coreId) {
        List<CpuCore> result = []
        Int index = 0
        while index < self._cores.length() {
            CpuCore core = self._cores.get(index)
            if core.socketId() == socketId && core.coreId() == coreId {
                result.push(core)
            }
            index = index + 1
        }
        return result
    }

    String describe() {
        String text = "cpu sockets=" + str(self._socketCount)
        text = text + " physical=" + str(self.physicalCoreCount())
        text = text + " logical=" + str(self.logicalCoreCount())
        text = text + " numa=" + str(self._numaNodeCount)
        text = text + " caches=" + str(self._caches.length())
        return text
    }

    CpuTopology copy() {
        return new CpuTopology(self._cores, self._caches, self._features,
            self._socketCount, self._numaNodeCount)
    }

    static CpuTopology detect() {
        Int logical = sysctlInt64Raw("hw.logicalcpu") as Int
        if logical <= 0 { logical = sysctlInt64Raw("hw.ncpu") as Int }
        if logical <= 0 { logical = 1 }
        Int physical = sysctlInt64Raw("hw.physicalcpu") as Int
        if physical <= 0 { physical = logical }
        if physical > logical { physical = logical }
        Int threadsPerCore = logical / physical
        if threadsPerCore < 1 { threadsPerCore = 1 }
        Int frequency = 0
        Long frequencyRaw = sysctlInt64Raw("hw.cpufrequency")
        if frequencyRaw <= 0 as Long { frequencyRaw = sysctlInt64Raw("hw.cpufrequency_max") }
        if frequencyRaw > 0 as Long { frequency = (frequencyRaw / 1000000 as Long) as Int }
        Int numa = numaNodeCountRaw() as Int
        if numa < 0 { numa = 0 }

        List<CpuCore> cores = []
        Int index = 0
        while index < logical {
            Int coreId = index / threadsPerCore
            Int threadId = index % threadsPerCore
            cores.push(new CpuCore(index, 0, coreId, threadId, 0, frequency, true))
            index = index + 1
        }

        Long lineRaw = sysctlInt64Raw("hw.cachelinesize")
        Int lineBytes = 0
        if lineRaw > 0 as Long { lineBytes = lineRaw as Int }
        List<CpuCache> caches = []
        Long l1i = sysctlInt64Raw("hw.l1icachesize")
        if l1i > 0 as Long {
            caches.push(new CpuCache(1, CpuCacheKind.Instruction, l1i, lineBytes, 0))
        }
        Long l1d = sysctlInt64Raw("hw.l1dcachesize")
        if l1d > 0 as Long {
            caches.push(new CpuCache(1, CpuCacheKind.Data, l1d, lineBytes, 0))
        }
        Long l2 = sysctlInt64Raw("hw.l2cachesize")
        if l2 > 0 as Long {
            caches.push(new CpuCache(2, CpuCacheKind.Unified, l2, lineBytes, 0))
        }
        Long l3 = sysctlInt64Raw("hw.l3cachesize")
        if l3 > 0 as Long {
            caches.push(new CpuCache(3, CpuCacheKind.Unified, l3, lineBytes, 0))
        }

        List<String> features = []
        cpuAddFeatureTokens(features, sysctlStringRaw("machdep.cpu.features"))
        cpuAddFeatureTokens(features, sysctlStringRaw("machdep.cpu.leaf7_features"))
        return new CpuTopology(cores, caches, features, 1, numa)
    }
}

// ---------- CpuAffinity ----------
class CpuAffinity {
    final Long _handle
    Bool _open

    CpuAffinity(Long handle) {
        if handle <= 0 as Long { throw "CpuAffinity: invalid handle" }
        self._handle = handle
        self._open = true
    }

    Result<List<Int>, Error> get(Context context) {
        if context == null { throw "CpuAffinity.get: null context" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "cpu affinity"))
        }
        return Err(new BasicError(ErrorKind.Unsupported, "cpu affinity get is not supported"))
    }

    Result<Unit, Error> set(Context context, List<Int> cpuIds) {
        if context == null { throw "CpuAffinity.set: null context" }
        if cpuIds == null || cpuIds.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty cpu set"))
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "cpu affinity"))
        }
        return Err(new BasicError(ErrorKind.Unsupported, "cpu affinity set is not supported"))
    }

    Result<Unit, Error> reset(Context context) {
        if context == null { throw "CpuAffinity.reset: null context" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "cpu affinity"))
        }
        return Err(new BasicError(ErrorKind.Unsupported, "cpu affinity reset is not supported"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }

    Bool isOpen() { return self._open }
}

static Void cpuAddFeatureTokens(List<String> features, String raw) {
    if raw == "" { return }
    List<String> tokens = raw.trim().split(" ")
    Int index = 0
    while index < tokens.length() {
        String token = tokens.get(index).trim()
        if token != "" {
            Bool exists = false
            Int scan = 0
            while scan < features.length() {
                if features.get(scan) == token { exists = true; break }
                scan = scan + 1
            }
            if !exists { features.push(token) }
        }
        index = index + 1
    }
}
