# `VirtualMachineState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum VirtualMachineState` |
| 包 | `xdk.os.virt` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

VM 状态快照分类：运行、停止、暂停、未知。

不做：状态机/转换规则、启动/停止/暂停/恢复、迁移、健康检查。

---

## 2. 设计逻辑

- 只表示一次快照中的可见状态；不定义合法转换，也不保证状态单调。
- `Unknown` 是合法值：权限不足、适配器不支持或状态不可读时返回 `Unknown`，不 panic。
- 状态由 `VirtualMachine.state()` 承载；不把“无 VM”塞进枚举。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。
- 名称映射使用稳定小写名；显示名不进入协议。

---

## 3. 表示与不变量

| 成员 | 含义 | 典型线索 |
| --- | --- | --- |
| `Running` | 正在运行 | `running`/`active` |
| `Stopped` | 已停止/关机 | `stopped`/`shutoff` |
| `Paused` | 已暂停 | `paused`/`suspended` |
| `Unknown` | 未知/不可读 | 适配器自定义 |

不变量：成员固定；只允许追加；值语义；`Unknown` 不携带额外语义。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

枚举无实例方法；以下为包级辅助函数。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `virtualMachineStateName` | 稳定小写名 | `VirtualMachineState state` | `String` | 无 |
| `virtualMachineStateFromName` | 名称解析 | `String name` | `VirtualMachineState?` | 无；null/未知返回 null |

`virtualMachineStateName` 返回 `running`/`stopped`/`paused`/`unknown`；
`virtualMachineStateFromName` 同时接受 `active`/`shutoff`/`suspended` 别名，大小写不敏感。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 适配器状态归一。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`VirtualMachine`。

---

## 10. 依赖的特性/接口/类

`VirtualMachine`、`VirtualizationHost`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`vm.state() == VirtualMachineState.Running`；用 `virtualMachineStateName` 输出。  
反例：把 `Paused` 当 `Stopped`；用状态推断健康；未知状态 panic；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；`active`/`shutoff`/`suspended` 别名；大小写与空白；未知名称；null；
`Unknown` 与权限不足；与 `VirtualMachine` 组合。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum VirtualMachineState {
    Running,
    Stopped,
    Paused,
    Unknown,
}

String virtualMachineStateName(VirtualMachineState state) {
    if state == VirtualMachineState.Running { return "running" }
    if state == VirtualMachineState.Stopped { return "stopped" }
    if state == VirtualMachineState.Paused { return "paused" }
    return "unknown"
}

VirtualMachineState? virtualMachineStateFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "running" || normalized == "active" {
        return VirtualMachineState.Running
    }
    if normalized == "stopped" || normalized == "shutoff" {
        return VirtualMachineState.Stopped
    }
    if normalized == "paused" || normalized == "suspended" {
        return VirtualMachineState.Paused
    }
    if normalized == "unknown" { return VirtualMachineState.Unknown }
    return null
}
```
