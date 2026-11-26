#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/accel-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.accel
import xdk.accel
import xdk.errors
import xdk.bytes

static List<AcceleratorCapability> panicCapabilities() {
    List<AcceleratorCapability> result = []
    return result
}

static List<String> panicStrings() {
    List<String> result = []
    return result
}

static AcceleratorDevice panicDevice() {
    return new AcceleratorDevice(1 as Long, Accel.cpu(),
        AcceleratorOptions.defaults())
}

static AcceleratorQueue panicQueue() {
    return new AcceleratorQueue(2 as Long, 0)
}

static AcceleratorProgram panicProgram() {
    return new AcceleratorProgram(3 as Long, panicDevice(), 4 as Long, "")
}

static AcceleratorCommandBuffer panicBuffer() {
    return new AcceleratorCommandBuffer(4 as Long, panicDevice(),
        panicQueue())
}

static AcceleratorMemory panicMemory() {
    return new AcceleratorMemory(5 as Long, panicDevice(), 8 as Long, true,
        false)
}

static AcceleratorFence panicFence() {
    return new AcceleratorFence(6 as Long, panicBuffer())
}

static Int main(String[] args) {
    Context context = Context.background()
    String name = args.get(0)
    if name == "accelId" {
        List<AcceleratorCapability> capabilities = panicCapabilities()
        Accelerator value = new Accelerator("", "n", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", 0 as Long, 0,
            capabilities)
    } else if name == "accelCap" {
        List<AcceleratorCapability> capabilities = panicCapabilities()
        capabilities.push(null)
        Accelerator value = new Accelerator("a", "n", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", 0 as Long, 0,
            capabilities)
    } else if name == "accelMemory" {
        List<AcceleratorCapability> capabilities = panicCapabilities()
        Accelerator value = new Accelerator("a", "n", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", -1 as Long, 0,
            capabilities)
    } else if name == "accelUnits" {
        List<AcceleratorCapability> capabilities = panicCapabilities()
        Accelerator value = new Accelerator("a", "n", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", 0 as Long, -1,
            capabilities)
    } else if name == "optionsMemory" {
        List<String> loadOptions = panicStrings()
        AcceleratorOptions value = new AcceleratorOptions("", false, false,
            -1 as Long, "", loadOptions, 0)
    } else if name == "optionsPriority" {
        List<String> loadOptions = panicStrings()
        AcceleratorOptions value = new AcceleratorOptions("", false, false,
            0 as Long, "", loadOptions, 101)
    } else if name == "optionsLoad" {
        List<String> loadOptions = panicStrings()
        loadOptions.push("")
        AcceleratorOptions value = new AcceleratorOptions("", false, false,
            0 as Long, "", loadOptions, 0)
    } else if name == "optionsNull" {
        List<String> loadOptions = panicStrings()
        AcceleratorOptions value = new AcceleratorOptions(null, false, false,
            0 as Long, "", loadOptions, 0)
    } else if name == "deviceHandle" {
        AcceleratorDevice value = new AcceleratorDevice(0 as Long, Accel.cpu(),
            AcceleratorOptions.defaults())
    } else if name == "memoryHandle" {
        AcceleratorMemory value = new AcceleratorMemory(0 as Long, panicDevice(),
            4 as Long, true, false)
    } else if name == "memoryUnified" {
        AcceleratorMemory value = new AcceleratorMemory(1 as Long, panicDevice(),
            4 as Long, false, true)
    } else if name == "memorySize" {
        AcceleratorMemory value = new AcceleratorMemory(1 as Long, panicDevice(),
            0 as Long, true, false)
    } else if name == "programSize" {
        AcceleratorProgram value = new AcceleratorProgram(1 as Long,
            panicDevice(), 0 as Long, "")
    } else if name == "programFormat" {
        AcceleratorProgram value = new AcceleratorProgram(1 as Long,
            panicDevice(), 4 as Long, null)
    } else if name == "kernelHandle" {
        AcceleratorKernel value = new AcceleratorKernel(0 as Long,
            panicProgram(), "main")
    } else if name == "kernelProgram" {
        AcceleratorKernel value = new AcceleratorKernel(1 as Long, null, "main")
    } else if name == "kernelName" {
        AcceleratorKernel value = new AcceleratorKernel(1 as Long,
            panicProgram(), "")
    } else if name == "queueHandle" {
        AcceleratorQueue value = new AcceleratorQueue(0 as Long, 0)
    } else if name == "queuePriority" {
        AcceleratorQueue value = new AcceleratorQueue(1 as Long, 101)
    } else if name == "cbHandle" {
        AcceleratorCommandBuffer value = new AcceleratorCommandBuffer(0 as Long,
            panicDevice(), panicQueue())
    } else if name == "cbQueueClosed" {
        AcceleratorQueue queue = panicQueue()
        queue.close()
        AcceleratorCommandBuffer value = new AcceleratorCommandBuffer(1 as Long,
            panicDevice(), queue)
    } else if name == "fenceHandle" {
        AcceleratorFence value = new AcceleratorFence(0 as Long, panicBuffer())
    } else if name == "fenceClosed" {
        AcceleratorCommandBuffer buffer = panicBuffer()
        buffer.close()
        AcceleratorFence value = new AcceleratorFence(1 as Long, buffer)
    } else if name == "openContext" {
        Result<AcceleratorDevice, Error> value = Accel.open(null, Accel.cpu(),
            AcceleratorOptions.defaults())
    } else if name == "optionsCheckOpenNull" {
        Result<Unit, Error> value = acceleratorOptionsCheckOpen(null)
    } else if name == "optionsCheckProgramNull" {
        Result<Unit, Error> value = acceleratorOptionsCheckProgram(null)
    } else if name == "optionsCheckQueueNull" {
        Result<Unit, Error> value = acceleratorOptionsCheckQueue(null)
    } else if name == "memoryWriteNull" {
        Result<Unit, Error> value = panicMemory().write(context, 0 as Long, null)
    } else if name == "memoryReadNull" {
        Result<Unit, Error> value = panicMemory().read(context, 0 as Long, null)
    } else if name == "deviceTotalNull" {
        Result<Long, Error> value = panicDevice().totalMemoryBytes(null)
    } else if name == "deviceAvailableNull" {
        Result<Long, Error> value = panicDevice().availableMemoryBytes(null)
    } else if name == "deviceAllocateNull" {
        Result<AcceleratorMemory, Error> value = panicDevice().allocateMemory(
            null, 4 as Long, true)
    } else if name == "deviceProgramNull" {
        Result<AcceleratorProgram, Error> value = panicDevice().createProgram(
            context, null, AcceleratorOptions.defaults())
    } else if name == "deviceKernelNull" {
        Result<AcceleratorKernel, Error> value = panicDevice().createKernel(
            context, null, "main")
    } else if name == "deviceQueueNull" {
        Result<AcceleratorQueue, Error> value = panicDevice().createQueue(
            context, null)
    } else if name == "deviceCbNull" {
        Result<AcceleratorCommandBuffer, Error> value =
            panicDevice().createCommandBuffer(context, null)
    } else if name == "deviceFenceNull" {
        Result<AcceleratorFence, Error> value = panicDevice().createFence(
            context, null)
    } else if name == "cbBeginNull" {
        Result<Unit, Error> value = panicBuffer().begin(null)
    } else if name == "cbBindKernelNull" {
        Result<Unit, Error> value = panicBuffer().bindKernel(context, null)
    } else if name == "cbBindMemoryNull" {
        Result<Unit, Error> value = panicBuffer().bindMemory(context, 0, null,
            0 as Long)
    } else if name == "cbBindValueNull" {
        Result<Unit, Error> value = panicBuffer().bindValue(context, 0, null)
    } else if name == "cbDispatchNull" {
        Result<Unit, Error> value = panicBuffer().dispatch(null, 1, 1, 1, 1, 1,
            1)
    } else if name == "cbEndNull" {
        Result<Unit, Error> value = panicBuffer().end(null)
    } else if name == "cbSubmitNull" {
        Result<Unit, Error> value = panicBuffer().submit(context, null)
    } else if name == "fenceWaitNull" {
        Result<Unit, Error> value = panicFence().wait(null, 0 as Long)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "accel panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "accel panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic accelId "Accelerator: invalid field"
check_panic accelCap "Accelerator: null capability"
check_panic accelMemory "Accelerator: negative value"
check_panic accelUnits "Accelerator: negative value"
check_panic optionsMemory "AcceleratorOptions: negative memory limit"
check_panic optionsPriority "AcceleratorOptions: priority out of range"
check_panic optionsLoad "AcceleratorOptions: empty load option"
check_panic optionsNull "AcceleratorOptions: null field"
check_panic deviceHandle "AcceleratorDevice: invalid field"
check_panic memoryHandle "AcceleratorMemory: invalid field"
check_panic memoryUnified "AcceleratorMemory: unified not host visible"
check_panic memorySize "AcceleratorMemory: invalid field"
check_panic programSize "AcceleratorProgram: invalid field"
check_panic programFormat "AcceleratorProgram: null format"
check_panic kernelHandle "AcceleratorKernel: invalid handle"
check_panic kernelProgram "AcceleratorKernel: null program"
check_panic kernelName "AcceleratorKernel: empty kernel name"
check_panic queueHandle "AcceleratorQueue: invalid handle"
check_panic queuePriority "AcceleratorQueue: priority out of range"
check_panic cbHandle "AcceleratorCommandBuffer: invalid handle"
check_panic cbQueueClosed "AcceleratorCommandBuffer: queue closed"
check_panic fenceHandle "AcceleratorFence: invalid handle"
check_panic fenceClosed "AcceleratorFence: command buffer closed"
check_panic openContext "Accel.open: null argument"
check_panic optionsCheckOpenNull "acceleratorOptionsCheckOpen: null options"
check_panic optionsCheckProgramNull "acceleratorOptionsCheckProgram: null options"
check_panic optionsCheckQueueNull "acceleratorOptionsCheckQueue: null options"
check_panic memoryWriteNull "AcceleratorMemory.write: null argument"
check_panic memoryReadNull "AcceleratorMemory.read: null argument"
check_panic deviceTotalNull "AcceleratorDevice.totalMemoryBytes: null context"
check_panic deviceAvailableNull "AcceleratorDevice.availableMemoryBytes: null context"
check_panic deviceAllocateNull "AcceleratorDevice.allocateMemory: null context"
check_panic deviceProgramNull "AcceleratorDevice.createProgram: null argument"
check_panic deviceKernelNull "AcceleratorDevice.createKernel: null argument"
check_panic deviceQueueNull "AcceleratorDevice.createQueue: null argument"
check_panic deviceCbNull "AcceleratorDevice.createCommandBuffer: null argument"
check_panic deviceFenceNull "AcceleratorDevice.createFence: null argument"
check_panic cbBeginNull "AcceleratorCommandBuffer.begin: null context"
check_panic cbBindKernelNull "AcceleratorCommandBuffer.bindKernel: null argument"
check_panic cbBindMemoryNull "AcceleratorCommandBuffer.bindMemory: null argument"
check_panic cbBindValueNull "AcceleratorCommandBuffer.bindValue: null argument"
check_panic cbDispatchNull "AcceleratorCommandBuffer.dispatch: null context"
check_panic cbEndNull "AcceleratorCommandBuffer.end: null context"
check_panic cbSubmitNull "AcceleratorCommandBuffer.submit: null argument"
check_panic fenceWaitNull "AcceleratorFence.wait: null context"
echo "accel_panic: PASS"
