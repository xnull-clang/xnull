package xdk2.os
import xdk.os.storage
import xdk.math

static Bool idsSorted(List<String> values) {
    Int index = 1
    while index < values.length() {
        if values.get(index - 1) > values.get(index) { return false }
        index = index + 1
    }
    return true
}

static Bool idsUnique(List<String> values) {
    Int index = 0
    while index < values.length() {
        Int scan = index + 1
        while scan < values.length() {
            if values.get(index) == values.get(scan) { return false }
            scan = scan + 1
        }
        index = index + 1
    }
    return true
}

static Int main() {
    print("health-names=" + smartHealthName(SmartHealth.Good) + "," +
        smartHealthName(SmartHealth.Warning) + "," +
        smartHealthName(SmartHealth.Critical) + "," +
        smartHealthName(SmartHealth.Unknown))
    SmartHealth? warning = smartHealthFromName(" WARNING ")
    SmartHealth? missing = smartHealthFromName("bogus")
    print("health-parse=" + smartHealthName(warning as SmartHealth) + "," +
        str(missing == null) + "," + str(smartHealthFromName(null) == null) + "," +
        str(smartHealthIsHealthy(SmartHealth.Good)) + "," +
        str(smartHealthIsHealthy(SmartHealth.Unknown)))

    SmartInfo smart = new SmartInfo(SmartHealth.Good, 35.0, 100 as Long, 0 as Long, true)
    print("smart=" + smart.describe() + "," + str(smart.equals(smart.copy())) + "," +
        str(smart.equals(null)) + "," + str(smart.isAvailable()))
    SmartInfo unavailable = new SmartInfo(SmartHealth.Unknown, 0.0, 0 as Long, 0 as Long, false)
    print("smart-unavailable=" + unavailable.describe() + "," +
        str(unavailable.isAvailable()))
    SmartInfo nanInfo = new SmartInfo(SmartHealth.Warning, NaN(), 10 as Long, 2 as Long, true)
    print("smart-nan=" + str(isNaN(nanInfo.temperatureCelsius())) + "," +
        str(nanInfo.powerOnHours()) + "," + str(nanInfo.reallocatedSectors()))

    StorageDevice device = new StorageDevice("disk0", "disk0", "ModelX", 1000 as Long,
        false, true, smart)
    print("device=" + device.describe() + "," + str(device.equals(device.copy())) +
        "," + str(device.equals(null)) + "," + str(device.isSolidState()) + "," +
        str(device.smart() != null))
    StorageDevice plain = new StorageDevice("disk1", "disk1", "", 500 as Long,
        true, false, null)
    print("device-plain=" + plain.describe() + "," + str(plain.smart() == null) + "," +
        str(plain.isRemovable()))

    Partition partition = new Partition("disk0@/data", "disk0", "/data", "apfs",
        600 as Long, 100 as Long)
    print("partition=" + partition.describe() + "," +
        str(partition.equals(partition.copy())) + "," + str(partition.equals(null)))

    List<StorageDevice> manualDevices = [device, plain]
    List<Partition> manualPartitions = [partition]
    StorageInventory manual = new StorageInventory(manualDevices, manualPartitions)
    print("inventory=" + manual.describe() + "," + str(manual.deviceCount()) + "," +
        str(manual.partitionCount()) + "," + str(manual.totalDeviceBytes()) + "," +
        str(manual.totalPartitionBytes()) + "," + str(manual.totalFreeBytes()))
    StorageDevice? foundDevice = manual.findDevice("disk0")
    Partition? foundMount = manual.findPartitionByMountPoint("/data")
    print("inventory-find=" + str(foundDevice != null) + "," +
        str(foundMount != null) + "," +
        str(manual.partitionsFor("disk0").length()) + "," +
        str(manual.findDevice("missing") == null) + "," +
        str(manual.findPartitionByMountPoint("/missing") == null))
    print("inventory-equals=" + str(manual.equals(manual.copy())) + "," +
        str(manual.equals(null)))

    StorageInventory detected = StorageInventory.detect()
    Int partitionCount = detected.partitionCount()
    Int deviceCount = detected.deviceCount()
    List<Partition> parts = detected.partitions()
    Bool partitionsOk = partitionCount > 0
    Bool fieldsOk = true
    Int index = 0
    while index < parts.length() {
        Partition value = parts.get(index)
        if value.mountPoint() == "" || value.sizeBytes() < 0 as Long ||
            value.freeBytes() < 0 as Long || value.partitionId() == "" {
            fieldsOk = false
        }
        index = index + 1
    }
    List<String> deviceIds = []
    index = 0
    while index < detected.devices().length() {
        deviceIds.push(detected.devices().get(index).deviceId())
        index = index + 1
    }
    Bool sumsOk = detected.totalDeviceBytes() == detected.totalPartitionBytes()
    Bool sortedOk = idsSorted(deviceIds) && idsUnique(deviceIds)
    Partition first = parts.get(0)
    Bool lookupOk = detected.findPartitionByMountPoint(first.mountPoint()) != null
    Bool deviceLookup = detected.findDevice(first.deviceId()) != null
    print("storage-detect=" + str(partitionsOk) + "," + str(deviceCount > 0) + "," +
        str(fieldsOk) + "," + str(sumsOk) + "," + str(sortedOk) + "," +
        str(lookupOk) + "," + str(deviceLookup) + "," +
        str(detected.equals(detected.copy())) + "," + str(detected.describe().length() > 0))
    return 0
}
