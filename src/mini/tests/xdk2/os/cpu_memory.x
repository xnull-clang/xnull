package xdk2.os
import xdk.os.cpu
import xdk.os.memory
import xdk.errors

static Bool hasDuplicate(List<String> values) {
    Int index = 0
    while index < values.length() {
        Int scan = index + 1
        while scan < values.length() {
            if values.get(index) == values.get(scan) { return true }
            scan = scan + 1
        }
        index = index + 1
    }
    return false
}

static Bool cachesValid(List<CpuCache> caches) {
    Int index = 0
    while index < caches.length() {
        CpuCache cache = caches.get(index)
        if cache.level() <= 0 || cache.sizeBytes() < 0 as Long ||
            cache.lineBytes() < 0 || cache.sharedByCpuCount() < 0 {
            return false
        }
        index = index + 1
    }
    return true
}

static Int main() {
    Context context = Context.background()

    print("cache-kind-names=" + cpuCacheKindName(CpuCacheKind.Data) + "," +
        cpuCacheKindName(CpuCacheKind.Instruction) + "," +
        cpuCacheKindName(CpuCacheKind.Unified) + "," +
        cpuCacheKindName(CpuCacheKind.Unknown))
    CpuCacheKind? parsed = cpuCacheKindFromName(" INSTRUCTION ")
    CpuCacheKind? missing = cpuCacheKindFromName("bogus")
    print("cache-kind-parse=" + cpuCacheKindName(parsed as CpuCacheKind) + "," +
        str(missing == null) + "," + str(cpuCacheKindFromName(null) == null))

    CpuCore core = new CpuCore(0, 0, 0, 0, 0, 3200, true)
    print("cpu-core=" + core.describe() + "," + str(core.equals(core.copy())) + "," +
        str(core.equals(null)) + "," + str(core.isOnline()))
    CpuCache cache = new CpuCache(1, CpuCacheKind.Data, 32768 as Long, 64, 2)
    print("cpu-cache=" + cache.describe() + "," + str(cache.equals(cache.copy())) +
        "," + str(cache.equals(null)))

    List<CpuCore> manualCores = [new CpuCore(0, 0, 0, 0, 0, 3000, true),
        new CpuCore(1, 0, 0, 1, 0, 3000, true),
        new CpuCore(2, 0, 1, 0, 0, 3000, true)]
    List<CpuCache> manualCaches = [cache]
    List<String> manualFeatures = ["sse", "avx"]
    CpuTopology manual = new CpuTopology(manualCores, manualCaches, manualFeatures, 1, 0)
    CpuCore? found = manual.findCore(1)
    print("cpu-manual=" + manual.describe() + "," + str(manual.physicalCoreCount()) +
        "," + str(manual.logicalCoreCount()) + "," + str(found != null) + "," +
        str(manual.findByCore(0, 0).length()) + "," + str(manual.copy().physicalCoreCount()) +
        "," + str(manual.findCore(99) == null))

    CpuTopology detected = CpuTopology.detect()
    Int logical = detected.logicalCoreCount()
    Int physical = detected.physicalCoreCount()
    Bool logicalOk = logical >= 1
    Bool physicalOk = physical >= 1 && physical <= logical
    CpuCore? first = detected.findCore(0)
    Bool featureOk = !hasDuplicate(detected.features())
    Bool cacheOk = cachesValid(detected.caches())
    Bool detectNumbersOk = detected.socketCount() >= 1 && detected.numaNodeCount() >= 0
    print("cpu-detect=" + str(logicalOk) + "," + str(physicalOk) + "," +
        str(logical == detected.cores().length()) + "," + str(first != null) + "," +
        str(cacheOk) + "," + str(featureOk) + "," + str(detectNumbersOk) + "," +
        str(detected.cores().get(0).isOnline()))

    CpuAffinity affinity = new CpuAffinity(1 as Long)
    List<Int> empty = []
    List<Int> one = [0]
    print("affinity=" + errorKindName(affinity.get(context).error().kind()) + "," +
        errorKindName(affinity.set(context, empty).error().kind()) + "," +
        errorKindName(affinity.set(context, one).error().kind()) + "," +
        errorKindName(affinity.reset(context).error().kind()) + "," +
        str(affinity.isOpen()))
    Result<Unit, Error> affinityClose = affinity.close()
    Result<Unit, Error> affinityCloseAgain = affinity.close()
    print("affinity-close=" + str(affinityClose.isOk()) + "," +
        str(affinityCloseAgain.isOk()) + "," + str(affinity.isOpen()) + "," +
        errorKindName(affinity.get(context).error().kind()))

    MemoryModule module = new MemoryModule("DIMM_A1", 17179869184 as Long,
        "DDR5", 5600, "Vendor", "PN-1")
    print("memory-module=" + module.describe() + "," +
        str(module.equals(module.copy())) + "," + str(module.equals(null)))
    List<Int> nodeCpus = [0, 1]
    NumaNode node = new NumaNode(0, 17179869184 as Long, nodeCpus)
    print("memory-numa=" + node.describe() + "," + str(node.equals(node.copy())) + "," +
        str(node.equals(null)) + "," + str(node.cpuIds().length()))
    List<MemoryModule> modules = [module]
    List<NumaNode> nodes = [node]
    PhysicalMemory memory = new PhysicalMemory(34359738368 as Long, 8589934592 as Long,
        17179869184 as Long, modules, nodes)
    print("memory-value=" + memory.describe() + "," + str(memory.moduleCount()) + "," +
        str(memory.numaNodeCount()) + "," + str(memory.equals(memory.copy())) + "," +
        str(memory.equals(null)))

    PhysicalMemory detectedMemory = PhysicalMemory.detect()
    print("memory-detect=" + str(detectedMemory.totalBytes() > 0 as Long) + "," +
        str(detectedMemory.freeBytes() >= 0 as Long) + "," +
        str(detectedMemory.availableBytes() >= 0 as Long) + "," +
        str(detectedMemory.availableBytes() == detectedMemory.freeBytes()) + "," +
        str(detectedMemory.moduleCount() == 0) + "," +
        str(detectedMemory.numaNodeCount() == 0))
    return 0
}
