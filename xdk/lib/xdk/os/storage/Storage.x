// xdk.os.storage —— 存储清单快照（M20.3）
//
// 实现 SmartHealth/SmartInfo/StorageDevice/Partition/StorageInventory 子集。
// SMART、可移动/SSD 探测、IOKit/sysfs 深度属性留后续；挂载点来自 getmntinfo。
// 稳定性：preview。合同见 docs/design/platform/os/storage/。
package xdk.os.storage

// ---------- SmartHealth ----------
enum SmartHealth {
    Good,
    Warning,
    Critical,
    Unknown,
}

String smartHealthName(SmartHealth health) {
    if health == SmartHealth.Good { return "good" }
    if health == SmartHealth.Warning { return "warning" }
    if health == SmartHealth.Critical { return "critical" }
    return "unknown"
}

SmartHealth? smartHealthFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "good" { return SmartHealth.Good }
    if normalized == "warning" { return SmartHealth.Warning }
    if normalized == "critical" { return SmartHealth.Critical }
    if normalized == "unknown" { return SmartHealth.Unknown }
    return null
}

Bool smartHealthIsHealthy(SmartHealth health) {
    return health == SmartHealth.Good
}

// ---------- SmartInfo ----------
class SmartInfo {
    final SmartHealth _kind
    final Double _temperatureCelsius
    final Long _powerOnHours
    final Long _reallocatedSectors
    final Bool _isAvailable

    SmartInfo(SmartHealth kind, Double temperatureCelsius,
              Long powerOnHours, Long reallocatedSectors, Bool isAvailable) {
        if powerOnHours < 0 as Long || reallocatedSectors < 0 as Long {
            throw "SmartInfo: negative field"
        }
        self._kind = kind
        self._temperatureCelsius = temperatureCelsius
        self._powerOnHours = powerOnHours
        self._reallocatedSectors = reallocatedSectors
        self._isAvailable = isAvailable
    }

    SmartHealth kind() { return self._kind }
    Double temperatureCelsius() { return self._temperatureCelsius }
    Long powerOnHours() { return self._powerOnHours }
    Long reallocatedSectors() { return self._reallocatedSectors }
    Bool isAvailable() { return self._isAvailable }

    String describe() {
        if !self._isAvailable { return "smart unavailable" }
        String text = "smart " + smartHealthName(self._kind)
        text = text + " temp=" + str(self._temperatureCelsius)
        text = text + " hours=" + str(self._powerOnHours)
        text = text + " reallocated=" + str(self._reallocatedSectors)
        return text
    }

    Bool equals(SmartInfo other) {
        if other == null { return false }
        return self._kind == other.kind() &&
            self._temperatureCelsius == other.temperatureCelsius() &&
            self._powerOnHours == other.powerOnHours() &&
            self._reallocatedSectors == other.reallocatedSectors() &&
            self._isAvailable == other.isAvailable()
    }

    SmartInfo copy() {
        return new SmartInfo(self._kind, self._temperatureCelsius,
            self._powerOnHours, self._reallocatedSectors, self._isAvailable)
    }
}

// ---------- StorageDevice ----------
class StorageDevice {
    final String _deviceId
    final String _name
    final String _model
    final Long _sizeBytes
    final Bool _isRemovable
    final Bool _isSolidState
    final SmartInfo? _smart

    StorageDevice(String deviceId, String name, String model, Long sizeBytes,
                  Bool isRemovable, Bool isSolidState, SmartInfo? smart) {
        if deviceId == null || deviceId == "" || name == null || name == "" {
            throw "StorageDevice: empty id/name"
        }
        if model == null { throw "StorageDevice: null model" }
        if sizeBytes < 0 as Long { throw "StorageDevice: negative size" }
        self._deviceId = deviceId
        self._name = name
        self._model = model
        self._sizeBytes = sizeBytes
        self._isRemovable = isRemovable
        self._isSolidState = isSolidState
        self._smart = smart
    }

    String deviceId() { return self._deviceId }
    String name() { return self._name }
    String model() { return self._model }
    Long sizeBytes() { return self._sizeBytes }
    Bool isRemovable() { return self._isRemovable }
    Bool isSolidState() { return self._isSolidState }
    SmartInfo? smart() { return self._smart }

    String describe() {
        String text = self._name + " " + self._model
        text = text + " size=" + str(self._sizeBytes)
        text = text + " ssd=" + str(self._isSolidState)
        return text
    }

    Bool equals(StorageDevice other) {
        if other == null { return false }
        if self._deviceId != other.deviceId() ||
            self._name != other.name() ||
            self._model != other.model() ||
            self._sizeBytes != other.sizeBytes() ||
            self._isRemovable != other.isRemovable() ||
            self._isSolidState != other.isSolidState() {
            return false
        }
        if self._smart == null { return other.smart() == null }
        SmartInfo value = self._smart as SmartInfo
        SmartInfo? otherSmart = other.smart()
        if otherSmart == null { return false }
        return value.equals(otherSmart as SmartInfo)
    }

    StorageDevice copy() {
        return new StorageDevice(self._deviceId, self._name, self._model,
            self._sizeBytes, self._isRemovable, self._isSolidState, self._smart)
    }
}

// ---------- Partition ----------
class Partition {
    final String _partitionId
    final String _deviceId
    final String _mountPoint
    final String _fileSystem
    final Long _sizeBytes
    final Long _freeBytes

    Partition(String partitionId, String deviceId, String mountPoint,
              String fileSystem, Long sizeBytes, Long freeBytes) {
        if partitionId == null || partitionId == "" {
            throw "Partition: empty partition id"
        }
        if deviceId == null || deviceId == "" {
            throw "Partition: empty device id"
        }
        if mountPoint == null || fileSystem == null {
            throw "Partition: null string"
        }
        if sizeBytes < 0 as Long || freeBytes < 0 as Long {
            throw "Partition: negative size"
        }
        self._partitionId = partitionId
        self._deviceId = deviceId
        self._mountPoint = mountPoint
        self._fileSystem = fileSystem
        self._sizeBytes = sizeBytes
        self._freeBytes = freeBytes
    }

    String partitionId() { return self._partitionId }
    String deviceId() { return self._deviceId }
    String mountPoint() { return self._mountPoint }
    String fileSystem() { return self._fileSystem }
    Long sizeBytes() { return self._sizeBytes }
    Long freeBytes() { return self._freeBytes }

    String describe() {
        String text = "partition " + self._partitionId
        text = text + " device=" + self._deviceId
        text = text + " mount=" + self._mountPoint
        text = text + " fs=" + self._fileSystem
        text = text + " free=" + str(self._freeBytes) + "/" + str(self._sizeBytes)
        return text
    }

    Bool equals(Partition other) {
        if other == null { return false }
        return self._partitionId == other.partitionId() &&
            self._deviceId == other.deviceId() &&
            self._mountPoint == other.mountPoint() &&
            self._fileSystem == other.fileSystem() &&
            self._sizeBytes == other.sizeBytes() &&
            self._freeBytes == other.freeBytes()
    }

    Partition copy() {
        return new Partition(self._partitionId, self._deviceId, self._mountPoint,
            self._fileSystem, self._sizeBytes, self._freeBytes)
    }
}

// ---------- StorageInventory ----------
class StorageInventory {
    final List<StorageDevice> _devices
    final List<Partition> _partitions

    StorageInventory(List<StorageDevice> devices, List<Partition> partitions) {
        if devices == null || partitions == null {
            throw "StorageInventory: null list"
        }
        self._devices = devices.copy()
        self._partitions = partitions.copy()
    }

    List<StorageDevice> devices() { return self._devices.copy() }
    List<Partition> partitions() { return self._partitions.copy() }
    Int deviceCount() { return self._devices.length() }
    Int partitionCount() { return self._partitions.length() }

    StorageDevice? findDevice(String deviceId) {
        if deviceId == null { throw "StorageInventory.findDevice: null id" }
        Int index = 0
        while index < self._devices.length() {
            StorageDevice device = self._devices.get(index)
            if device.deviceId() == deviceId { return device }
            index = index + 1
        }
        return null
    }

    List<Partition> partitionsFor(String deviceId) {
        if deviceId == null {
            throw "StorageInventory.partitionsFor: null id"
        }
        List<Partition> result = []
        Int index = 0
        while index < self._partitions.length() {
            Partition partition = self._partitions.get(index)
            if partition.deviceId() == deviceId { result.push(partition) }
            index = index + 1
        }
        return result
    }

    Partition? findPartitionByMountPoint(String mountPoint) {
        if mountPoint == null {
            throw "StorageInventory.findPartitionByMountPoint: null mount"
        }
        Int index = 0
        while index < self._partitions.length() {
            Partition partition = self._partitions.get(index)
            if partition.mountPoint() == mountPoint { return partition }
            index = index + 1
        }
        return null
    }

    Long totalDeviceBytes() {
        Long total = 0 as Long
        Int index = 0
        while index < self._devices.length() {
            total = total + self._devices.get(index).sizeBytes()
            index = index + 1
        }
        return total
    }

    Long totalPartitionBytes() {
        Long total = 0 as Long
        Int index = 0
        while index < self._partitions.length() {
            total = total + self._partitions.get(index).sizeBytes()
            index = index + 1
        }
        return total
    }

    Long totalFreeBytes() {
        Long total = 0 as Long
        Int index = 0
        while index < self._partitions.length() {
            total = total + self._partitions.get(index).freeBytes()
            index = index + 1
        }
        return total
    }

    String describe() {
        return "storage devices=" + str(self._devices.length()) +
            " partitions=" + str(self._partitions.length())
    }

    Bool equals(StorageInventory other) {
        if other == null { return false }
        List<StorageDevice> otherDevices = other.devices()
        if self._devices.length() != otherDevices.length() { return false }
        Int index = 0
        while index < self._devices.length() {
            if !self._devices.get(index).equals(otherDevices.get(index)) {
                return false
            }
            index = index + 1
        }
        List<Partition> otherPartitions = other.partitions()
        if self._partitions.length() != otherPartitions.length() { return false }
        index = 0
        while index < self._partitions.length() {
            if !self._partitions.get(index).equals(otherPartitions.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    StorageInventory copy() {
        return new StorageInventory(self._devices, self._partitions)
    }

    static StorageInventory detect() {
        List<Partition> partitions = []
        List<String> partitionIds = []
        String text = mountsTextRaw()
        if text != "" {
            List<String> lines = text.split("\n")
            Int lineIndex = 0
            while lineIndex < lines.length() {
                String line = lines.get(lineIndex).trim()
                if line != "" {
                    List<String> fields = line.split("|")
                    if fields.length() >= 5 {
                        String device = fields.get(0).trim()
                        String mount = fields.get(1).trim()
                        String fileSystem = fields.get(2).trim()
                        Long sizeBytes = storageParseLong(fields.get(3))
                        Long freeBytes = storageParseLong(fields.get(4))
                        if sizeBytes < 0 as Long { sizeBytes = 0 as Long }
                        if freeBytes < 0 as Long { freeBytes = 0 as Long }
                        if sizeBytes < freeBytes { freeBytes = sizeBytes }
                        String partitionId = device + "@" + mount
                        if device != "" && mount != "" &&
                            !storageContains(partitionIds, partitionId) {
                            partitionIds.push(partitionId)
                            partitions.push(new Partition(partitionId, device, mount,
                                fileSystem, sizeBytes, freeBytes))
                        }
                    }
                }
                lineIndex = lineIndex + 1
            }
        }

        List<String> deviceIds = []
        List<Long> deviceSizes = []
        Int index = 0
        while index < partitions.length() {
            Partition partition = partitions.get(index)
            String deviceId = partition.deviceId()
            Bool found = false
            Int scan = 0
            while scan < deviceIds.length() {
                if deviceIds.get(scan) == deviceId {
                    deviceSizes.set(scan, deviceSizes.get(scan) + partition.sizeBytes())
                    found = true
                    break
                }
                scan = scan + 1
            }
            if !found {
                deviceIds.push(deviceId)
                deviceSizes.push(partition.sizeBytes())
            }
            index = index + 1
        }

        List<String> sortedIds = []
        List<Long> sortedSizes = []
        index = 0
        while index < deviceIds.length() {
            String deviceId = deviceIds.get(index)
            Long sizeBytes = deviceSizes.get(index)
            Int position = 0
            while position < sortedIds.length() && sortedIds.get(position) < deviceId {
                position = position + 1
            }
            sortedIds.insert(position, deviceId)
            sortedSizes.insert(position, sizeBytes)
            index = index + 1
        }

        List<StorageDevice> devices = []
        index = 0
        while index < sortedIds.length() {
            String deviceId = sortedIds.get(index)
            devices.push(new StorageDevice(deviceId, deviceId, deviceId,
                sortedSizes.get(index), false, false, null))
            index = index + 1
        }
        return new StorageInventory(devices, partitions)
    }
}

static Bool storageContains(List<String> values, String target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Long storageParseLong(String text) {
    if text == null || text == "" { return -1 as Long }
    Long value = 0 as Long
    Int index = 0
    while index < text.length() {
        Int code = text.get(index)
        if code < 48 || code > 57 { return -1 as Long }
        Long digit = code - 48 as Long
        value = value * (10 as Long) + digit
        index = index + 1
    }
    return value
}
