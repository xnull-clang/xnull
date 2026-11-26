# 硬件原语清单（实现阻塞说明）

> 本文是**实现阻塞说明**，不是公共 API 合同。合同仍以各包 `README.md` / 类型文档为准。
> 目的：明确 `xdk.accel`、`xdk.embedded`、`xdk.os.*`、`xdk.serial`、`xdk.device`、TLS 等包为什么只能停在 `design`，以及补齐时要加什么。

## 1. 定义

“硬件原语”指宿主/runtime 已经封装好、XNull 代码可以直接调用的一条最低层能力：

```text
.xfb 声明 C FFI
      ↓
src/runtime/*.c 真实实现（syscall / ioctl / 驱动 / 厂商 SDK）
      ↓
xdk 包组装类型、校验、生命周期
```

没有这条 C 桥，包只能实现描述符、枚举、校验和状态机；一旦走到“真正操作设备”就必须返回 `Unsupported`，不能标记为 implemented。

## 2. accel（GPU/NPU/加速器）

至少需要：

| 能力 | 典型底层 API |
| --- | --- |
| 枚举/打开设备 | CUDA Driver `cuInit/cuDeviceGet`；Metal `MTLCreateSystemDefaultDevice`；ROCm `hipGetDevice`；Vulkan `vkEnumeratePhysicalDevices`；OpenCL `clGetPlatformIDs` |
| 分配/释放设备内存 | `cuMemAlloc/cuMemFree`、`MTLBuffer`、`hipMalloc`、`vkAllocateMemory` |
| Host↔Device 拷贝 | `cuMemcpyHtoD/DtoH`、Metal blit encoder |
| 加载程序/模块 | `cuModuleLoadData`、`MTLComputePipelineState`、`hipModuleLoad` |
| 建队列/流 | `cuStreamCreate`、`MTLCommandQueue`、`hipStreamCreate` |
| 启动内核 | `cuLaunchKernel`、`MTLComputeCommandEncoder`、`hipLaunchKernel` |
| 栅栏/事件/同步 | `cuEventRecord/cuEventSynchronize`、`MTLFence`、`vkFence` |

对应 FFI（示意，命名以实现为准）：

```text
accelDeviceCountRaw()
accelOpenRaw(deviceIndex)
accelMemAllocRaw(device, bytes)
accelMemFreeRaw(...)
accelMemCopyRaw(...)
accelModuleLoadRaw(...)
accelKernelLaunchRaw(...)
accelFenceWaitRaw(...)
accelCloseRaw(...)
```

当前 macOS 可用的是 **Metal** 后端；CUDA/ROCm/OpenVINO/DirectML 无法在本机真实验证。可以先把 Metal 原语补齐并只把 Metal 标为可用，其余后端保持 `Unsupported`。

## 3. embedded（MCU/板级）

至少需要：

| 能力 | 典型底层接口 |
| --- | --- |
| GPIO 方向/读写 | `/dev/gpiochipN` + `ioctl(GPIO_GET_LINEHANDLE_IOCTL/GPIO_V2_LINE_SET_VALUES_IOCTL)`、sysfs |
| I2C | `/dev/i2c-N` + `I2C_RDWR` ioctl |
| SPI | `/dev/spidevX.Y` + `SPI_IOC_MESSAGE` |
| UART | `termios`（`cfsetispeed/cfsetospeed/tcsetattr`） |
| ADC/PWM | IIO sysfs、`/sys/class/pwm` |
| Watchdog | `/dev/watchdog` + `WDIOC_KEEPALIVE` |
| RTC | `/dev/rtc` + `RTC_RD_TIME/RTC_SET_TIME` |
| Flash | MTD ioctl、厂商 SDK |
| 低功耗 | SoC PMIC/电源管理驱动、设备树 |

对应 FFI（示意）：

```text
gpioOpenRaw/gpioSetDirectionRaw/gpioReadRaw/gpioWriteRaw
i2cTransferRaw/spiTransferRaw
uartConfigureRaw/uartReadRaw/uartWriteRaw
adcReadRaw/pwmSetRaw
watchdogStartRaw/watchdogKickRaw
rtcReadRaw/rtcSetRaw
flashEraseRaw/flashReadRaw/flashWriteRaw
```

这些接口在 macOS 上不存在；只能交叉编译到目标 Linux/RTOS，或用 QEMU 外设/真实板子验证。

## 4. 平台/OS 相关阻塞

- `xdk.os.host/hardware/gpu`：需要 IOKit、`sysctl`、PCI/DRM 信息；当前仅有部分 sysctl/挂载点。
- `xdk.os.firewall/container/virt/service`：需要特权 ioctl、cgroup/namespace、systemd/launchd 接口。
- `xdk.serial`：需要 termios/IOKit serial。
- `xdk.device`：需要 IOKit/USB/PCI 枚举与权限。
- `xdk.net.tls`、`https`：需要 TLS 库或安全传输原语（证书校验、握手、SNI、ALPN）。
- `xdk.reflect`：需要编译器生成类型元数据表；纯运行时反射不可靠。

## 5. 处理原则

1. 描述符/枚举/校验可以写；设备打开、内存分配、内核启动、引脚读写没有原语就返回 `Unsupported`。
2. 不把“假后端组合测试”当成硬件实现；可以在 README 标注“contract-only / simulator”。
3. 优先补一个真实后端（macOS Metal、Linux GPIO/I2C），其余保持 planned。
4. 新原语必须同时补 `.xfb` 声明、C 实现、错误映射和至少一个真实设备/模拟器场景。
