# `xdk.os.host` 宿主聚合

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.host` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.os` 基础 + `xdk.os.cpu/memory/hardware/storage/gpu/firewall/container/virt/service` |
| 被依赖 | 应用/服务器入口 |
| 稳定性 | `preview` |

---

## 1. 定位

把 `xdk.os` 基础类型与各 domain 服务聚合为 `OsHost`，并提供静态入口 `Os`。

为什么单独成包：

- `xdk.os` 基础只含 `OsKind/OsFamily/OsCapability/OsInfo/OsProfile`，不依赖任何 domain；
- `xdk.os.cpu` 等 domain 只依赖 `xdk.os` 基础，可单独导入；
- `xdk.os.host` 依赖全部 domain，负责聚合；
- 这样避免 `基础 ↔ domain` 循环依赖，也避免只想用 CPU 拓扑的程序被迫编译 GPU 类型。

---

## 2. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `OsHost` | protocol | [`OsHost.md`](OsHost.md) |
| `Os` | class（静态入口） | [`Os.md`](Os.md) |

---

## 3. 依赖方向

```text
xdk.os.cpu / memory / hardware / storage / gpu /
xdk.os.firewall / container / virt / service
        │ 依赖
        ▼
xdk.os（基础）
        ▲
        │ 聚合
xdk.os.host
```

规则：

- domain 包不得依赖 `xdk.os.host`。
- `xdk.os.host` 可以依赖全部 domain。
- `xdk.os` 基础不得依赖 domain/host。
- core/net 不得依赖 `xdk.os.*`。

---

## 4. 场景

- 应用入口 `import xdk.os.host` 获取 `Os`/`OsHost`。
- 只需要 CPU 拓扑的工具 `import xdk.os.cpu` + `import xdk.os`，不导入 host。
- 测试注入 `OsHost` fake，不需要真实 OS。

## 5. 缺口

- 按需加载 domain：当前 `OsHost` 聚合全部；如果编译期裁剪需要，后续可拆 `OsHost` 为多个小协议。
- 宿主生命周期：调用方 `close()`；无全局。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Override` |
| 处理器 | 编译器内建 |
| 生成物 | OsHost 实现签名；Os 是门面，不套派生注解 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `OsHost` 实现 | `@Override` | 签名校验 |
| `Os` 门面 | — | 门面/装配，保持显式 class |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
