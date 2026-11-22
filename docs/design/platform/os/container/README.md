# `xdk.os.container` 容器/cgroup/namespace

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.container` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `Container` |
| 稳定性 | `preview` |

---

## 1. 定位

容器运行环境只读快照：容器标识、运行时、镜像、cgroup、namespace，以及当前进程是否在容器内。

不做：创建/启动/停止/销毁容器、exec/attach、镜像管理、编排、网络插件、cgroup 写入/冻结/杀进程、
namespace 进入。控制面属于 X 或 ecosystem。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读基线 | 只查询容器/cgroup/namespace；写控制 X |
| 不透明 | `ContainerHost` 持有 `Long` 句柄；不暴露 fd/指针/路径句柄 |
| 最小可见 | 只返回当前上下文可见的 cgroup/namespace；容器内不承诺宿主全部 |
| 权限显式 | 特权读取返回 `PermissionDenied`；不自动提权、不重试 |
| 平台显式 | 基线只覆盖 Linux 容器语义；非 Linux 返回 `Unsupported` |
| 脱敏 | 容器 ID 可截断；镜像/挂载/环境不写日志 |
| 快照 | 构造后不可变；列表返回副本；不自动刷新 |
| 无全局 | 由 `OsHost` 返回控制器；不提供全局单例 |

---

## 3. 类型索引

| 类型 | 种类 | 职责 | 文件 |
| --- | --- | --- | --- |
| `NamespaceKind` | enum | namespace 分类 | [`NamespaceKind.md`](NamespaceKind.md) |
| `Namespace` | class | 单个 namespace 条目 | [`Namespace.md`](Namespace.md) |
| `Cgroup` | class | 单个 cgroup 条目 | [`Cgroup.md`](Cgroup.md) |
| `ContainerInfo` | class | 容器快照 | [`ContainerInfo.md`](ContainerInfo.md) |
| `ContainerHost` | class | 只读查询控制器 | [`ContainerHost.md`](ContainerHost.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.Container)`，再调用 `OsHost.containers(context)`；缺失能力返回 `Unsupported`。
- `ContainerHost` 是唯一入口；`ContainerInfo`/`Namespace`/`Cgroup` 由适配器构造，业务代码不直接构造。
- `ContainerInfo.namespaces()` 的元素是 `Namespace`；`ContainerInfo.cgroups()` 的元素是 `Cgroup`；
  两个列表均为副本，顺序由适配器决定。
- `Namespace.kind()` 是 `NamespaceKind`；`Namespace.id()` 是 OS 标识字符串，可能不透明、不连续，
  不承诺跨重启稳定。
- 非容器环境：`ContainerInfo.isContainerized()` 为 false，`runtime()` 为 `"none"`，namespace/cgroup 列表为空；
  不报错。
- 非 Linux：容器查询返回 `Unsupported`；`ContainerHost.isContainerized()` 返回 false，不抛异常。
- 特权读取（其他容器的 cgroup/namespace、受限 `/proc`）返回 `PermissionDenied`；不重试、不提权。
- 只读：不提供创建/启动/停止/exec/attach、cgroup 写入/冻结/杀进程、namespace 进入；
  这些是 X/ecosystem。
- `ContainerHost` 由调用方 `close()`；`close()` 幂等；关闭后 `info`/`cgroups`/`namespaces` 返回
  `Unavailable`；`isContainerized` 是进程级探测，不依赖句柄。
- 容器内只报告可见资源；不得把当前容器的 cgroup/namespace 解释为宿主全部。
- `ContainerHost.isContainerized()`、`ContainerInfo.isContainerized()` 与 `OsInfo.isContainerized()`
  对同一时刻应一致；跨调用不保证原子。
- `Cgroup.memoryLimitBytes()` 的 `0` 表示未设置限制/不可读；`cpuWeight()` 的 `0` 表示未设置/未知；
  不承诺 cgroup v1/v2 数值语义等价。

---

## 5. 场景

- 服务器启动：检测容器/cgroup 限额，调整 worker/内存池。
- 监控 Agent：上报容器 ID/镜像/cgroup 摘要；不写控制面。
- 桌面/开发机：通常 `Unsupported` 或非容器空快照。
- CI：在容器内运行测试，读取 namespace/cgroup 以诊断隔离边界。

---

## 6. 缺口

- cgroup 写入/冻结/杀进程：X，需权限与审计。
- 容器创建/启动/停止/删除/exec：ecosystem（Docker/Podman/containerd API）。
- 镜像/层/仓库管理：ecosystem。
- Kubernetes/编排 API：ecosystem。
- namespace 进入/创建：X。
- 非 Linux 容器（Windows Job Object/其他隔离机制）：平台适配器后续；基线不承诺。
- cgroup v1/v2 统一视图：适配器负责；基线只暴露稳定字段。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | 标准 A8 |
| 生成物 | 命名空间/Cgroup/容器信息值语义 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Namespace`/`Cgroup`/`ContainerInfo` | `@Value` | 值语义成员 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
