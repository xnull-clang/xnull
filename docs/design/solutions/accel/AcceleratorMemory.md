# `AcceleratorMemory`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorMemory` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Error`、`AcceleratorDevice` |

---

## 1. 定位

由加速器设备分配的设备内存对象不透明句柄：逻辑字节大小、主机可见/统一内存标记、带偏移的 CPU 写入/读取、关闭、是否可用。

只做无类型字节内存；不解释 dtype、张量形状、量化格式、页表、缓存一致性或物理位置。内核绑定、数据布局与数值语义由程序/内核契约决定。设备级总量/可用量由 [`AcceleratorDevice.totalMemoryBytes`](AcceleratorDevice.md)/[`availableMemoryBytes`](AcceleratorDevice.md) 提供；本类型表示一次分配，不是显存快照。

不做：

- 映射/取消映射、裸指针、设备地址、DMA 描述符；
- 显存分配策略、驻留/驱逐、内存别名、精确预算；
- dtype/张量/图像/采样器/纹理；
- 隐式同步或自动 fence；
- 跨设备/跨进程共享；
- 统一内存的缓存一致性承诺。

---

## 2. 设计逻辑

- 由 [`AcceleratorDevice.allocateMemory`](AcceleratorDevice.md) 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露映射地址、后端指针或 fd。
- `_sizeBytes` 是调用方请求的逻辑大小，必须 >0；适配器可向上取整原生分配，但所有公开边界只使用逻辑大小。
- `hostVisible` 在创建时固定：true 表示允许 CPU `write`/`read`；false 时 CPU 访问返回 `Unsupported`，不尝试映射或模拟。
- `unified` 在创建时固定：true 表示 CPU/设备共享同一物理内存；false 表示未声明统一（可能是非统一，也可能是后端未报告），不表示一定不统一；true 也不表示自动缓存一致，仍必须用 [`AcceleratorFence`](AcceleratorFence.md) 同步。
- `write`/`read` 是宿主拷贝，不插入设备屏障、不等待在飞工作；调用方必须先等 fence signaled。
- `write`/`read` 支持偏移；偏移和长度以字节为单位；越界返回 `InvalidArgument`；零长度且偏移合法时 `Ok(unit)`，不调用原生。
- 关闭后纯元数据（句柄、设备、大小、hostVisible、unified、isOpen）仍可读；读写返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`/`describe`；内存是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_device` | `AcceleratorDevice` | final | 非 null；非拥有引用 |
| `_sizeBytes` | `Long` | final | >0；逻辑大小 |
| `_hostVisible` | `Bool` | final | 创建后固定 |
| `_unified` | `Bool` | final | 创建后固定；true ⇒ hostVisible |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device` 非 null；`sizeBytes > 0`。
- `unified == true` 时 `hostVisible == true`；不允许“统一但主机不可见”。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生内存原语。
- 原生分配可能大于逻辑大小，但所有公开边界只使用 `_sizeBytes`。
- 不持有裸指针、映射地址或设备地址。
- 读写不改变大小、可见性、统一性。

---

## 4. 生命周期

由 `AcceleratorDevice.allocateMemory` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

设备必须比内存活得久。若设备先关闭：

- `write`/`read` 返回 `Unavailable`；
- `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；
- 句柄/设备/大小/可见性/统一性/isOpen 仍可读；设备关闭不会自动把内存标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

提交给设备使用后，内存必须保持打开直到关联 fence signaled；提前关闭可能造成设备使用已释放内存。多个命令缓冲引用同一内存时，调用方必须等所有相关提交完成。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorMemory(Long handle, AcceleratorDevice device, Long sizeBytes, Bool hostVisible, Bool unified)` | handle、device、sizeBytes、hostVisible、unified | handle >0；device 非 null；sizeBytes >0；unified ⇒ hostVisible | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `AcceleratorDevice.allocateMemory` 获取。工厂对 `sizeBytes <= 0` 返回 `InvalidArgument`；hostVisible 不支持返回 `Unsupported`；超限返回 `OutOfMemory`。

---

## 6. 字段表

见 §3；字段私有。不暴露原生指针、映射地址、fd、DMA 描述符或后端分配句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `memoryHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `device` | 所属设备 | 无 | `AcceleratorDevice` | 无 |
| `sizeBytes` | 逻辑大小 | 无 | `Long` | 无 |
| `isHostVisible` | 主机是否可访问 | 无 | `Bool` | 无 |
| `isUnified` | 是否统一内存 | 无 | `Bool` | 无 |
| `write` | CPU 写入 | `Context context, Long offsetBytes, Bytes source` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`Busy`/`Io` |
| `read` | CPU 读取 | `Context context, Long offsetBytes, Bytes target` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`Busy`/`Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `memoryHandle()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程/持久 ID。
- `device()` 返回非拥有引用；内存不关闭设备。
- `sizeBytes()` 返回请求的逻辑大小，不等于适配器实际分配大小。
- `write`：
  - `context == null` 或 `source == null` → panic。
  - 关闭/设备关闭 → `Unavailable`；`hostVisible == false` → `Unsupported`。
  - `offsetBytes < 0` 或 `offsetBytes > sizeBytes` → `InvalidArgument`。
  - `toLong(source.length()) > sizeBytes - offsetBytes` → `InvalidArgument`；`source.length() == 0` 且偏移合法 → `Ok(unit)`。
  - 取消 → `Cancelled`；原生可返回 `Busy`/`Io`。
  - 失败时内容可能部分写入；不保证原子性。
  - 不插入设备屏障；不得与在飞设备使用并发。
- `read`：
  - `context == null` 或 `target == null` → panic。
  - 关闭/设备关闭 → `Unavailable`；`hostVisible == false` → `Unsupported`。
  - `offsetBytes < 0` 或 `offsetBytes > sizeBytes` → `InvalidArgument`。
  - `toLong(target.length()) > sizeBytes - offsetBytes` → `InvalidArgument`；`target.length() == 0` 且偏移合法 → `Ok(unit)`。
  - 成功时 `target` 被完整填充；不返回部分读取。
  - 取消 → `Cancelled`；原生可返回 `Busy`/`Io`。
  - 失败时 `target` 内容未定义；必须在 fence signaled 后读取。
- `close`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续调用返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `map`/`unmap`/`copy`/`fill`/`describe`/`equals`；这些是 X 或调用方组合。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 逻辑大小与原生分配大小分离；
- 主机可见/统一内存标记；
- 带偏移的拷贝式读写；
- 边界检查；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、Bytes、Result；
- 辅助：`toLong`（Int → Long，用于比较 `Bytes.length()` 与逻辑大小）；
- 运行时/适配器：
  - `acceleratorMemoryAllocateRaw(Context context, Long deviceHandle, Long sizeBytes, Bool hostVisible) -> Result<Long, Error>`；
  - `acceleratorMemoryWriteRaw(Context context, Long memoryHandle, Long offsetBytes, Bytes source) -> Result<Unit, Error>`；
  - `acceleratorMemoryReadRaw(Context context, Long memoryHandle, Long offsetBytes, Bytes target) -> Result<Unit, Error>`；
  - `acceleratorMemoryCloseRaw(Long memoryHandle) -> Result<Unit, Error>`；
- 原生分配返回的句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器解析 `AcceleratorDevice` 的内部句柄；公共 API 不暴露；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`AcceleratorDevice`、`AcceleratorFence`。

---

## 10. 依赖的特性/接口/类

[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorFence`](AcceleratorFence.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；内存由调用方拥有；设备是非拥有引用；内存不反向拥有设备。

非线程安全：`write`/`read`/`close` 不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

CPU 读写不得与在飞设备使用并发；提交后必须等 fence signaled 再 `read` 或关闭。若多个命令缓冲绑定同一内存，调用方必须等所有相关提交完成。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- `allocateMemory(context, 4096, true)` → `write(context, 0, source)` → 绑定为内核参数 → 提交 → `fence.wait` → `read(context, 0, target)`。
- 设备内存 `hostVisible = false` 时只作为设备端输入/输出，通过支持设备拷贝的内核或后端路径初始化。
- 统一内存仍用 fence 同步；不假设自动一致。
- 大缓冲区用 `Long` 偏移分块读写，检查每块边界。

反例：

- 对 `hostVisible = false` 的内存调用 `write` 并期望隐式映射。
- 把 `sizeBytes` 当实际分配大小，越界访问原生尾部。
- 提交后未等 fence 就 `read`。
- 把句柄当地址或跨进程 ID。
- 关闭设备后继续读写；关闭内存后继续绑定。
- 假设 `unified` 自动缓存一致。

---

## 13. 测试/场景义务

分配/关闭；`hostVisible` true/false；`unified` 与 `hostVisible` 组合（统一 ⇒ 可见）；
偏移 0/中间/末尾/越界；零长度读写；负偏移；目标容量不足；
设备关闭后读写 `Unavailable`、`close` `Ok(unit)`；关闭后元数据可读；
取消/`Busy`/`Io` 映射；部分写入/未定义读取；大 `Long` 大小；
多命令缓冲共享内存的 fence 顺序；`unified` 仍需 fence；无裸指针。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorMemory {
    final Long _handle
    final AcceleratorDevice _device
    final Long _sizeBytes
    final Bool _hostVisible
    final Bool _unified
    Bool _open

    AcceleratorMemory(Long handle, AcceleratorDevice device, Long sizeBytes,
                      Bool hostVisible, Bool unified) {
        if handle <= 0 || device == null || sizeBytes <= 0 {
            throw "AcceleratorMemory: invalid field"
        }
        if unified && !hostVisible {
            throw "AcceleratorMemory: unified but not host visible"
        }
        _handle = handle
        _device = device
        _sizeBytes = sizeBytes
        _hostVisible = hostVisible
        _unified = unified
        _open = true
    }

    Long memoryHandle() { return _handle }
    AcceleratorDevice device() { return _device }
    Long sizeBytes() { return _sizeBytes }
    Bool isHostVisible() { return _hostVisible }
    Bool isUnified() { return _unified }
    Bool isOpen() { return _open }

    Result<Unit, Error> write(Context context, Long offsetBytes, Bytes source) {
        if context == null || source == null {
            throw "AcceleratorMemory.write: null argument"
        }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
        }
        if !_hostVisible {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory is not host visible"))
        }
        if offsetBytes < 0 || offsetBytes > _sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument, "offset out of range"))
        }
        if toLong(source.length()) > _sizeBytes - offsetBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument, "source too large"))
        }
        if source.length() == 0 { return Ok(unit) }
        return acceleratorMemoryWriteRaw(context, _handle, offsetBytes, source)
    }

    Result<Unit, Error> read(Context context, Long offsetBytes, Bytes target) {
        if context == null || target == null {
            throw "AcceleratorMemory.read: null argument"
        }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
        }
        if !_hostVisible {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory is not host visible"))
        }
        if offsetBytes < 0 || offsetBytes > _sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument, "offset out of range"))
        }
        if toLong(target.length()) > _sizeBytes - offsetBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument, "target too large"))
        }
        if target.length() == 0 { return Ok(unit) }
        return acceleratorMemoryReadRaw(context, _handle, offsetBytes, target)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return acceleratorMemoryCloseRaw(_handle)
    }
}
```
