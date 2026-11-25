#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.os
import xdk.os
import xdk.os.cpu
import xdk.os.memory

static OsInfo sampleInfo() {
    return new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
        "6.1.0", "x86_64", "host", "", "glibc", false)
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "infoEmptyName" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "", "1.0",
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "infoEmptyArch" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
            "6.1.0", "", "host", "", "glibc", false)
    } else if name == "infoNullVersion" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", null,
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "infoNullSession" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
            "6.1.0", "x86_64", "host", null, "glibc", false)
    } else if name == "infoFamilyMismatch" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Windows, "TestOS", "1.0",
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "profileEmptyName" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("", sampleInfo(), caps)
    } else if name == "profileNullInfo" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", null, caps)
    } else if name == "profileNullCaps" {
        OsProfile profile = new OsProfile("p", sampleInfo(), null)
    } else if name == "profileWithName" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", sampleInfo(), caps)
        OsProfile renamed = profile.withName("")
    } else if name == "cpuCoreNegativeId" {
        CpuCore core = new CpuCore(-1, 0, 0, 0, 0, 0, true)
    } else if name == "cpuCoreNegativeFrequency" {
        CpuCore core = new CpuCore(0, 0, 0, 0, 0, -1, true)
    } else if name == "cpuCacheLevel" {
        CpuCache cache = new CpuCache(0, CpuCacheKind.Data, 0 as Long, 0, 0)
    } else if name == "cpuCacheNegativeSize" {
        CpuCache cache = new CpuCache(1, CpuCacheKind.Data, -1 as Long, 0, 0)
    } else if name == "cpuTopologyNull" {
        List<CpuCore> nullCores = []
        List<CpuCache> nullCaches = []
        List<String> nullFeatures = []
        CpuTopology topology = new CpuTopology(null, nullCaches, nullFeatures, 1, 0)
    } else if name == "cpuTopologyNegative" {
        List<CpuCore> cores = []
        List<CpuCache> caches = []
        List<String> features = []
        CpuTopology topology = new CpuTopology(cores, caches, features, -1, 0)
    } else if name == "cpuAffinityHandle" {
        CpuAffinity affinity = new CpuAffinity(0 as Long)
    } else if name == "numaNegativeId" {
        List<Int> cpus = []
        NumaNode node = new NumaNode(-1, 0 as Long, cpus)
    } else if name == "numaNegativeMemory" {
        List<Int> cpus = []
        NumaNode node = new NumaNode(0, -1 as Long, cpus)
    } else if name == "numaNullCpus" {
        NumaNode node = new NumaNode(0, 0 as Long, null)
    } else if name == "moduleNullSlot" {
        MemoryModule module = new MemoryModule(null, 0 as Long, "", 0, "", "")
    } else if name == "moduleNegativeSize" {
        MemoryModule module = new MemoryModule("A1", -1 as Long, "", 0, "", "")
    } else if name == "moduleNegativeSpeed" {
        MemoryModule module = new MemoryModule("A1", 0 as Long, "", -1, "", "")
    } else if name == "physicalNegative" {
        List<MemoryModule> modules = []
        List<NumaNode> nodes = []
        PhysicalMemory memory = new PhysicalMemory(-1 as Long, 0 as Long, 0 as Long,
            modules, nodes)
    } else if name == "physicalNullModules" {
        List<NumaNode> nodes = []
        PhysicalMemory memory = new PhysicalMemory(0 as Long, 0 as Long, 0 as Long,
            null, nodes)
    } else if name == "profileMissing" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", sampleInfo(), caps)
        List<OsCapability> missing = profile.missing(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "os panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "os panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic infoEmptyName "OsInfo: empty name"
check_panic infoEmptyArch "OsInfo: empty architecture"
check_panic infoNullVersion "OsInfo: null string"
check_panic infoNullSession "OsInfo: null string"
check_panic infoFamilyMismatch "OsInfo: family does not match kind"
check_panic profileEmptyName "OsProfile: empty name"
check_panic profileNullInfo "OsProfile: null field"
check_panic profileNullCaps "OsProfile: null field"
check_panic profileWithName "OsProfile.withName: empty"
check_panic profileMissing "OsProfile.missing: null list"
check_panic cpuCoreNegativeId "CpuCore: negative field"
check_panic cpuCoreNegativeFrequency "CpuCore: negative field"
check_panic cpuCacheLevel "CpuCache: invalid field"
check_panic cpuCacheNegativeSize "CpuCache: invalid field"
check_panic cpuTopologyNull "CpuTopology: null list"
check_panic cpuTopologyNegative "CpuTopology: negative count"
check_panic cpuAffinityHandle "CpuAffinity: invalid handle"
check_panic numaNegativeId "NumaNode: invalid field"
check_panic numaNegativeMemory "NumaNode: invalid field"
check_panic numaNullCpus "NumaNode: invalid field"
check_panic moduleNullSlot "MemoryModule: null string"
check_panic moduleNegativeSize "MemoryModule: negative field"
check_panic moduleNegativeSpeed "MemoryModule: negative field"
check_panic physicalNegative "PhysicalMemory: negative size"
check_panic physicalNullModules "PhysicalMemory: null list"
echo "os_panic: PASS"
