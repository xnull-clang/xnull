# `CpuCacheKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum CpuCacheKind` |
| 包 | `xdk.os.cpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

CPU 缓存类型：数据、指令、统一、未知。

不做：缓存策略、替换算法、性能计数器。

---

## 2. 设计逻辑

- 只区分缓存用途；层级/大小/行宽由 `CpuCache` 承载。
- `Unknown` 是合法值；未知平台不得 panic。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Data` | 数据缓存 |
| `Instruction` | 指令缓存 |
| `Unified` | 统一缓存 |
| `Unknown` | 未知 |

不变量：成员固定；只允许追加；值语义。

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

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `cpuCacheKindName` | 稳定小写名 | `CpuCacheKind kind` | `String` | 无 |
| `cpuCacheKindFromName` | 名称解析 | `String name` | `CpuCacheKind?` | 无；未知返回 null |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`CpuCache`。

---

## 10. 依赖的特性/接口/类

`CpuCache`、`CpuTopology`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`cache.kind() == CpuCacheKind.Unified`。  
反例：用 kind 推断层级；未知值 panic；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；未知名称；X86/ARM 常见缓存；与 `CpuCache` 组合。

---

## 14. XNull 伪代码

```xnull
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
```
