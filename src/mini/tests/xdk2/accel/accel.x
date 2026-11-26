package xdk2.accel
import xdk.accel
import xdk.errors
import xdk.bytes

static String asResult(Result<Unit, Error> result) {
    if result.isErr() { return errorKindName(result.error().kind()) }
    return "ok"
}

static String asBoolResult(Result<Bool, Error> result) {
    if result.isErr() { return errorKindName(result.error().kind()) }
    return str(result.value())
}

static String asOpenResult(Result<AcceleratorDevice, Error> result) {
    if result.isErr() { return errorKindName(result.error().kind()) }
    return "ok"
}

static String asQueueResult(Result<AcceleratorQueue, Error> result) {
    if result.isErr() { return errorKindName(result.error().kind()) }
    return "ok"
}

static Accelerator emptyAccelerator() {
    List<AcceleratorCapability> capabilities = []
    return new Accelerator("empty", "", AcceleratorVendor.Unknown, "",
        AcceleratorKind.Other, AcceleratorBackend.Custom, "", 0 as Long, 0,
        capabilities)
}

static Int main() {
    Context context = Context.background()

    print("kind-names=" + acceleratorKindName(AcceleratorKind.Unknown) + "," +
        acceleratorKindName(AcceleratorKind.Cpu) + "," +
        acceleratorKindName(AcceleratorKind.Gpu) + "," +
        acceleratorKindName(AcceleratorKind.Npu) + "," +
        acceleratorKindName(AcceleratorKind.Dsp) + "," +
        acceleratorKindName(AcceleratorKind.Fpga) + "," +
        acceleratorKindName(AcceleratorKind.Asic) + "," +
        acceleratorKindName(AcceleratorKind.Lpu) + "," +
        acceleratorKindName(AcceleratorKind.Ipu) + "," +
        acceleratorKindName(AcceleratorKind.Hpu) + "," +
        acceleratorKindName(AcceleratorKind.Dpu) + "," +
        acceleratorKindName(AcceleratorKind.Vpu) + "," +
        acceleratorKindName(AcceleratorKind.Mcu) + "," +
        acceleratorKindName(AcceleratorKind.Other))
    AcceleratorKind? parsedKind = acceleratorKindFromName(" GPU ")
    print("kind-parse=" +
        str((parsedKind as AcceleratorKind) == AcceleratorKind.Gpu) + "," +
        str((acceleratorKindFromName("UNKNOWN") as AcceleratorKind) ==
            AcceleratorKind.Unknown) + "," +
        str(acceleratorKindFromName("bogus") == null) + "," +
        str(acceleratorKindFromName(null) == null))

    print("backend-names=" + acceleratorBackendName(AcceleratorBackend.Unknown) +
        "," + acceleratorBackendName(AcceleratorBackend.Cuda) + "," +
        acceleratorBackendName(AcceleratorBackend.Rocm) + "," +
        acceleratorBackendName(AcceleratorBackend.Sycl) + "," +
        acceleratorBackendName(AcceleratorBackend.OpenCl) + "," +
        acceleratorBackendName(AcceleratorBackend.Vulkan) + "," +
        acceleratorBackendName(AcceleratorBackend.Metal) + "," +
        acceleratorBackendName(AcceleratorBackend.DirectMl) + "," +
        acceleratorBackendName(AcceleratorBackend.OneApi) + "," +
        acceleratorBackendName(AcceleratorBackend.Custom) + "," +
        acceleratorBackendName(AcceleratorBackend.Cpu))
    AcceleratorBackend? parsedBackend = acceleratorBackendFromName(" DirectML ")
    print("backend-parse=" +
        str((parsedBackend as AcceleratorBackend) ==
            AcceleratorBackend.DirectMl) + "," +
        str((acceleratorBackendFromName("cpu") as AcceleratorBackend) ==
            AcceleratorBackend.Cpu) + "," +
        str(acceleratorBackendFromName("bogus") == null) + "," +
        str(acceleratorBackendFromName(null) == null))

    print("vendor-names=" + acceleratorVendorName(AcceleratorVendor.Unknown) +
        "," + acceleratorVendorName(AcceleratorVendor.Intel) + "," +
        acceleratorVendorName(AcceleratorVendor.Nvidia) + "," +
        acceleratorVendorName(AcceleratorVendor.Amd) + "," +
        acceleratorVendorName(AcceleratorVendor.Apple) + "," +
        acceleratorVendorName(AcceleratorVendor.Qualcomm) + "," +
        acceleratorVendorName(AcceleratorVendor.Arm) + "," +
        acceleratorVendorName(AcceleratorVendor.Imagination) + "," +
        acceleratorVendorName(AcceleratorVendor.Google) + "," +
        acceleratorVendorName(AcceleratorVendor.Microsoft) + "," +
        acceleratorVendorName(AcceleratorVendor.Amazon) + "," +
        acceleratorVendorName(AcceleratorVendor.Samsung) + "," +
        acceleratorVendorName(AcceleratorVendor.Huawei) + "," +
        acceleratorVendorName(AcceleratorVendor.MediaTek) + "," +
        acceleratorVendorName(AcceleratorVendor.Broadcom) + "," +
        acceleratorVendorName(AcceleratorVendor.Marvell) + "," +
        acceleratorVendorName(AcceleratorVendor.Nxp) + "," +
        acceleratorVendorName(AcceleratorVendor.TexasInstruments) + "," +
        acceleratorVendorName(AcceleratorVendor.STMicroelectronics) + "," +
        acceleratorVendorName(AcceleratorVendor.Infineon) + "," +
        acceleratorVendorName(AcceleratorVendor.Renesas) + "," +
        acceleratorVendorName(AcceleratorVendor.Microchip) + "," +
        acceleratorVendorName(AcceleratorVendor.Lattice) + "," +
        acceleratorVendorName(AcceleratorVendor.Xilinx) + "," +
        acceleratorVendorName(AcceleratorVendor.Altera) + "," +
        acceleratorVendorName(AcceleratorVendor.Cerebras) + "," +
        acceleratorVendorName(AcceleratorVendor.Graphcore) + "," +
        acceleratorVendorName(AcceleratorVendor.Groq) + "," +
        acceleratorVendorName(AcceleratorVendor.SambaNova) + "," +
        acceleratorVendorName(AcceleratorVendor.Tenstorrent) + "," +
        acceleratorVendorName(AcceleratorVendor.Hailo) + "," +
        acceleratorVendorName(AcceleratorVendor.Rockchip) + "," +
        acceleratorVendorName(AcceleratorVendor.Espressif) + "," +
        acceleratorVendorName(AcceleratorVendor.NordicSemiconductor) + "," +
        acceleratorVendorName(AcceleratorVendor.SiFive) + "," +
        acceleratorVendorName(AcceleratorVendor.Other))
    AcceleratorVendor? parsedVendor = acceleratorVendorFromName(
        " TEXAS_INSTRUMENTS ")
    print("vendor-parse=" +
        str((parsedVendor as AcceleratorVendor) ==
            AcceleratorVendor.TexasInstruments) + "," +
        str((acceleratorVendorFromName("other") as AcceleratorVendor) ==
            AcceleratorVendor.Other) + "," +
        str(acceleratorVendorFromName("bogus") == null) + "," +
        str(acceleratorVendorFromName(null) == null))
    print("vendor-text=" + acceleratorVendorName(
        acceleratorVendorFromText(null)) + "," +
        acceleratorVendorName(acceleratorVendorFromText("  ")) + "," +
        acceleratorVendorName(acceleratorVendorFromText("NVIDIA")) + "," +
        acceleratorVendorName(
            acceleratorVendorFromText("Advanced Micro Devices")) + "," +
        acceleratorVendorName(acceleratorVendorFromText("TI")) + "," +
        acceleratorVendorName(
            acceleratorVendorFromText("Nordic Semiconductor")) + "," +
        acceleratorVendorName(
            acceleratorVendorFromText(" STMicroelectronics ")) + "," +
        acceleratorVendorName(acceleratorVendorFromText("Acme Silicon")))

    print("capability-names=" +
        acceleratorCapabilityName(AcceleratorCapability.Unknown) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Memory) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Compute) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Graphics) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Reconfigurable) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Quantized) + "," +
        acceleratorCapabilityName(AcceleratorCapability.LowPower) + "," +
        acceleratorCapabilityName(AcceleratorCapability.Other))
    AcceleratorCapability? parsedCapability = acceleratorCapabilityFromName(
        " LOW_POWER ")
    print("capability-parse=" +
        str((parsedCapability as AcceleratorCapability) ==
            AcceleratorCapability.LowPower) + "," +
        str((acceleratorCapabilityFromName("other") as AcceleratorCapability) ==
            AcceleratorCapability.Other) + "," +
        str(acceleratorCapabilityFromName("bogus") == null) + "," +
        str(acceleratorCapabilityFromName(null) == null))

    List<AcceleratorCapability> capabilities = [
        AcceleratorCapability.Memory,
        AcceleratorCapability.Compute,
        AcceleratorCapability.Memory,
        AcceleratorCapability.Quantized
    ]
    Accelerator accelerator = new Accelerator("npu0", "Acme NPU",
        AcceleratorVendor.Other, "Acme", AcceleratorKind.Npu,
        AcceleratorBackend.Custom, "1.2", 1024 as Long, 8, capabilities)
    capabilities.push(AcceleratorCapability.Other)
    print("accel=" + accelerator.describe())
    print("accel-fields=" + accelerator.acceleratorId() + "," +
        accelerator.name() + "," +
        acceleratorVendorName(accelerator.vendor()) + "," +
        accelerator.vendorName() + "," +
        acceleratorKindName(accelerator.kind()) + "," +
        acceleratorBackendName(accelerator.backend()) + "," +
        accelerator.runtimeVersion() + "," +
        str(accelerator.memoryBytes()) + "," +
        str(accelerator.computeUnitCount()))
    List<AcceleratorCapability> acceleratorCapabilities =
        accelerator.capabilities()
    print("accel-caps=" + str(acceleratorCapabilities.length()) + "," +
        acceleratorCapabilityName(acceleratorCapabilities.get(0)) + "," +
        acceleratorCapabilityName(acceleratorCapabilities.get(1)) + "," +
        acceleratorCapabilityName(acceleratorCapabilities.get(2)))
    acceleratorCapabilities.push(AcceleratorCapability.Graphics)
    print("accel-caps-copy=" + str(acceleratorCapabilities.length()) + "," +
        str(accelerator.capabilities().length()))
    print("accel-supports=" +
        str(accelerator.supports(AcceleratorCapability.Memory)) + "," +
        str(accelerator.supports(AcceleratorCapability.Quantized)) + "," +
        str(accelerator.supports(AcceleratorCapability.LowPower)))
    print("accel-equals=" + str(accelerator.equals(accelerator.copy())) + "," +
        str(accelerator.equals(null)) + "," +
        str(accelerator.equals(emptyAccelerator())))
    Accelerator empty = emptyAccelerator()
    print("accel-empty=" + str(empty.capabilities().length()) + "," +
        str(empty.supports(AcceleratorCapability.Compute)))
    Accelerator large = new Accelerator("big", "Big", AcceleratorVendor.Unknown,
        "", AcceleratorKind.Gpu, AcceleratorBackend.Vulkan, "",
        4294967296 as Long, 128, capabilities)
    print("accel-large=" + str(large.memoryBytes()) + "," +
        str(large.computeUnitCount()))

    AcceleratorOptions defaults = AcceleratorOptions.defaults()
    print("options-default=" + defaults.describe() + "," +
        str(defaults.equals(defaults.copy())) + "," +
        str(defaults.loadOptions().length()))
    List<String> loadOptions = ["fast", "safe"]
    AcceleratorOptions custom = new AcceleratorOptions("train", true, true,
        4096 as Long, "spirv", loadOptions, 10)
    loadOptions.push("late")
    print("options-custom=" + custom.describe() + "," + custom.label() + "," +
        str(custom.isProfilingEnabled()) + "," +
        str(custom.isValidationEnabled()) + "," +
        str(custom.memoryLimitBytes()) + "," + custom.codeFormat() + "," +
        str(custom.loadOptions().length()) + "," +
        str(custom.queuePriority()))
    List<String> returnedOptions = custom.loadOptions()
    returnedOptions.push("external")
    print("options-copy=" + str(custom.equals(custom.copy())) + "," +
        str(custom.loadOptions().length()) + "," +
        str(custom.equals(null)) + "," +
        str(custom.describe().indexOf("fast") < 0))
    print("options-checks=" + asResult(acceleratorOptionsCheckOpen(defaults)) +
        "," + asResult(acceleratorOptionsCheckOpen(custom)) + "," +
        asResult(acceleratorOptionsCheckProgram(defaults)) + "," +
        asResult(acceleratorOptionsCheckProgram(custom)) + "," +
        asResult(acceleratorOptionsCheckQueue(defaults)) + "," +
        asResult(acceleratorOptionsCheckQueue(custom)))

    Accelerator cpu = Accel.cpu()
    print("cpu=" + cpu.describe())
    print("cpu-fields=" + cpu.acceleratorId() + "," + cpu.name() + "," +
        acceleratorVendorName(cpu.vendor()) + "," +
        acceleratorKindName(cpu.kind()) + "," +
        acceleratorBackendName(cpu.backend()) + "," +
        cpu.runtimeVersion() + "," + str(cpu.memoryBytes()) + "," +
        str(cpu.computeUnitCount()))
    print("cpu-caps=" + str(cpu.capabilities().length()) + "," +
        str(cpu.supports(AcceleratorCapability.Memory)) + "," +
        str(cpu.supports(AcceleratorCapability.Compute)))
    print("open-cpu=" + asOpenResult(Accel.open(context, cpu, defaults)))
    print("open-empty=" + asOpenResult(Accel.open(context, emptyAccelerator(),
        defaults)))
    print("open-bad-option=" + asOpenResult(Accel.open(context, cpu, custom)))
    List<AcceleratorCapability> graphicsOnly = [AcceleratorCapability.Graphics]
    Accelerator graphics = new Accelerator("gfx", "Graphics",
        AcceleratorVendor.Unknown, "", AcceleratorKind.Gpu,
        AcceleratorBackend.Vulkan, "", 0 as Long, 0, graphicsOnly)
    print("open-graphics=" + asOpenResult(Accel.open(context, graphics, defaults)))

    AcceleratorDevice device = new AcceleratorDevice(7 as Long, cpu, defaults)
    print("device=" + str(device.deviceHandle()) + "," +
        str(device.isOpen()) + "," + str(device.options().equals(defaults)) +
        "," + device.acceleratorId() + "," +
        acceleratorKindName(device.kind()) + "," +
        acceleratorBackendName(device.backend()) + "," +
        acceleratorVendorName(device.vendor()) + "," +
        str(device.memoryLimitBytes()))
    Result<Long, Error> total = device.totalMemoryBytes(context)
    Result<Long, Error> available = device.availableMemoryBytes(context)
    print("device-memory=" + errorKindName(total.error().kind()) + "," +
        errorKindName(available.error().kind()))
    print("device-alloc=" +
        errorKindName(device.allocateMemory(context, 0 as Long, true)
            .error().kind()) + "," +
        errorKindName(device.allocateMemory(context, -1 as Long, false)
            .error().kind()) + "," +
        errorKindName(device.allocateMemory(context, 16 as Long, true)
            .error().kind()))
    print("device-create-queue=" +
        asQueueResult(device.createQueue(context, defaults)))
    Result<AcceleratorQueue, Error> badQueue = device.createQueue(context,
        custom)
    print("device-create-queue-option=" +
        errorKindName(badQueue.error().kind()))
    print("device-program=" +
        errorKindName(device.createProgram(context, Bytes.fromString(""),
            defaults).error().kind()) + "," +
        errorKindName(device.createProgram(context, Bytes.fromString("code"),
            defaults).error().kind()))
    AcceleratorProgram program = new AcceleratorProgram(11 as Long, device,
        4 as Long, "spirv")
    print("device-kernel=" +
        errorKindName(device.createKernel(context, program, "")
            .error().kind()) + "," +
        errorKindName(device.createKernel(context, program, "vector_add")
            .error().kind()))
    AcceleratorQueue queue = new AcceleratorQueue(41 as Long, 5)
    Result<AcceleratorCommandBuffer, Error> unregistered =
        device.createCommandBuffer(context, queue)
    print("device-command-buffer=" +
        errorKindName(unregistered.error().kind()))

    AcceleratorMemory memory = new AcceleratorMemory(31 as Long, device,
        16 as Long, true, false)
    print("memory=" + str(memory.memoryHandle()) + "," +
        str(memory.sizeBytes()) + "," + str(memory.isHostVisible()) + "," +
        str(memory.isUnified()) + "," + str(memory.isOpen()))
    print("memory-write=" +
        errorKindName(memory.write(context, 0 as Long,
            Bytes.fromString("abcd")).error().kind()) + "," +
        asResult(memory.write(context, 16 as Long, Bytes.fromString(""))) +
        "," + errorKindName(memory.write(context, 17 as Long,
            Bytes.fromString("x")).error().kind()) + "," +
        errorKindName(memory.write(context, -1 as Long,
            Bytes.fromString("")).error().kind()) + "," +
        errorKindName(memory.write(context, 0 as Long,
            Bytes.fromString("0123456789abcdefg")).error().kind()))
    print("memory-read=" +
        errorKindName(memory.read(context, 0 as Long,
            Bytes.fromString("abcd")).error().kind()) + "," +
        asResult(memory.read(context, 16 as Long, Bytes.fromString(""))) +
        "," + errorKindName(memory.read(context, 0 as Long,
            Bytes.fromString("0123456789abcdefg")).error().kind()))
    AcceleratorMemory hidden = new AcceleratorMemory(32 as Long, device,
        8 as Long, false, false)
    print("memory-hidden=" +
        errorKindName(hidden.write(context, 0 as Long,
            Bytes.fromString("x")).error().kind()) + "," +
        errorKindName(hidden.read(context, 0 as Long,
            Bytes.fromString("x")).error().kind()))
    print("memory-close=" + asResult(memory.close()) + "," +
        str(memory.isOpen()) + "," + asResult(memory.close()) + "," +
        errorKindName(memory.write(context, 0 as Long,
            Bytes.fromString("x")).error().kind()))
    print("memory-meta=" + str(memory.memoryHandle()) + "," +
        str(memory.sizeBytes()) + "," + str(memory.isHostVisible()) + "," +
        str(memory.isUnified()))

    print("program=" + str(program.programHandle()) + "," +
        str(program.codeSizeBytes()) + "," + program.codeFormat() + "," +
        acceleratorBackendName(program.backend()) + "," +
        str(program.isOpen()))
    print("program-close=" + asResult(program.close()) + "," +
        str(program.isOpen()) + "," + asResult(program.close()))
    print("program-meta=" + str(program.programHandle()) + "," +
        str(program.codeSizeBytes()) + "," + program.codeFormat())

    AcceleratorKernel kernel = new AcceleratorKernel(12 as Long, program,
        "vector_add")
    print("kernel=" + str(kernel.kernelHandle()) + "," + kernel.kernelName() +
        "," + acceleratorBackendName(kernel.backend()) + "," +
        str(kernel.isOpen()) + "," + str(kernel.program() == program))
    print("kernel-close=" + asResult(kernel.close()) + "," +
        str(kernel.isOpen()) + "," + asResult(kernel.close()))
    print("kernel-meta=" + str(kernel.kernelHandle()) + "," +
        kernel.kernelName())
    print("queue=" + str(queue.queueHandle()) + "," + str(queue.priority()) +
        "," + str(queue.isOpen()) + "," + asResult(queue.close()) + "," +
        str(queue.isOpen()) + "," + asResult(queue.close()))

    AcceleratorQueue submitQueue = new AcceleratorQueue(42 as Long, 0)
    AcceleratorProgram submitProgram = new AcceleratorProgram(13 as Long,
        device, 8 as Long, "")
    AcceleratorKernel submitKernel = new AcceleratorKernel(14 as Long,
        submitProgram, "main")
    AcceleratorMemory submitMemory = new AcceleratorMemory(33 as Long, device,
        32 as Long, true, true)
    AcceleratorCommandBuffer buffer = new AcceleratorCommandBuffer(51 as Long,
        device, submitQueue)
    AcceleratorFence fence = new AcceleratorFence(61 as Long, buffer)
    print("cb-initial=" + str(buffer.isRecording()) + "," +
        str(buffer.isSubmitted()) + "," + str(buffer.isOpen()))
    print("cb-before=" +
        asResult(buffer.bindKernel(context, submitKernel)) + "," +
        asResult(buffer.bindMemory(context, 0, submitMemory, 0 as Long)) + "," +
        asResult(buffer.bindValue(context, 0, Bytes.fromString("abcd"))) + "," +
        asResult(buffer.dispatch(context, 1, 1, 1, 1, 1, 1)) + "," +
        asResult(buffer.end(context)) + "," +
        asResult(buffer.submit(context, fence)))
    print("cb-begin=" + asResult(buffer.begin(context)) + "," +
        asResult(buffer.begin(context)) + "," + str(buffer.isRecording()))
    AcceleratorDevice otherDevice = new AcceleratorDevice(8 as Long, cpu,
        defaults)
    AcceleratorProgram otherProgram = new AcceleratorProgram(15 as Long,
        otherDevice, 8 as Long, "")
    AcceleratorKernel otherKernel = new AcceleratorKernel(16 as Long,
        otherProgram, "main")
    AcceleratorMemory otherMemory = new AcceleratorMemory(34 as Long,
        otherDevice, 8 as Long, true, false)
    AcceleratorMemory closedMemory = new AcceleratorMemory(35 as Long, device,
        8 as Long, true, false)
    closedMemory.close()
    print("cb-bind-invalid=" +
        asResult(buffer.bindKernel(context, otherKernel)) + "," +
        asResult(buffer.bindMemory(context, 0, otherMemory, 0 as Long)) + "," +
        asResult(buffer.bindMemory(context, 0, closedMemory, 0 as Long)))
    print("cb-bind=" + asResult(buffer.bindKernel(context, submitKernel)) +
        "," + asResult(buffer.bindMemory(context, 0, submitMemory, 0 as Long)) +
        "," + asResult(buffer.bindMemory(context, 1, submitMemory, 16 as Long)) +
        "," + asResult(buffer.bindValue(context, 0,
            Bytes.fromString("abcd"))) + "," +
        asResult(buffer.bindValue(context, 1,
            Bytes.fromString("0123456789abcdef"))))
    print("cb-bind-bad=" +
        asResult(buffer.bindMemory(context, -1, submitMemory, 0 as Long)) +
        "," + asResult(buffer.bindMemory(context, 0, submitMemory,
            32 as Long)) + "," +
        asResult(buffer.bindValue(context, 0, Bytes.fromString(""))) + "," +
        asResult(buffer.bindValue(context, 0,
            Bytes.fromString("0123456789abcdefg"))))
    print("cb-dispatch=" +
        asResult(buffer.dispatch(context, 0, 1, 1, 1, 1, 1)) + "," +
        asResult(buffer.dispatch(context, 1, 1, 1, 0, 1, 1)) + "," +
        asResult(buffer.dispatch(context, 1, 1, 1, 1, 1, 1)))
    print("cb-end=" + asResult(buffer.end(context)) + "," +
        asResult(buffer.submit(context, fence)))
    print("cb-close=" + asResult(buffer.close()) + "," +
        str(buffer.isOpen()) + "," + str(buffer.isRecording()) + "," +
        asResult(buffer.begin(context)) + "," + asResult(buffer.close()))

    print("fence=" + str(fence.fenceHandle()) + "," +
        asBoolResult(fence.isSignaled()) + "," + str(fence.isOpen()))
    print("fence-wait=" + asResult(fence.wait(context, 0 as Long)) + "," +
        asResult(fence.wait(context, -1 as Long)) + "," +
        asResult(fence.wait(context, 10 as Long)))
    print("fence-close=" + asResult(fence.close()) + "," +
        str(fence.isOpen()) + "," + asResult(fence.close()) + "," +
        asBoolResult(fence.isSignaled()))

    AcceleratorDevice closing = new AcceleratorDevice(9 as Long, cpu, defaults)
    print("device-close=" + asResult(closing.close()) + "," +
        str(closing.isOpen()) + "," + asResult(closing.close()) + "," +
        str(closing.deviceHandle()))
    print("device-closed=" +
        errorKindName(closing.totalMemoryBytes(context).error().kind()) + "," +
        errorKindName(closing.allocateMemory(context, 4 as Long, true)
            .error().kind()) + "," +
        asQueueResult(closing.createQueue(context, defaults)))

    AcceleratorDevice memoryDevice = new AcceleratorDevice(10 as Long, cpu,
        defaults)
    AcceleratorMemory lateMemory = new AcceleratorMemory(36 as Long,
        memoryDevice, 4 as Long, true, false)
    memoryDevice.close()
    print("memory-device-closed=" +
        errorKindName(lateMemory.write(context, 0 as Long,
            Bytes.fromString("x")).error().kind()) + "," +
        asResult(lateMemory.close()) + "," + str(lateMemory.isOpen()))
    return 0
}
