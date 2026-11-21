# `ContainerInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class ContainerInfo` |
| 包 | `xdk.os.container` |
| 稳定性 | `preview` |
| 依赖 | `Namespace`、`Cgroup` |

---

## 1. 定位

容器运行环境只读快照：容器标识、运行时、镜像、是否容器化、namespace 与 cgroup 列表。

不做：容器创建/启动/停止/exec、镜像管理、编排、cgroup 写入、namespace 进入。

---

## 2. 设计逻辑

- 不可变快照；由 `ContainerHost.info(context)` 返回。
- `id` 是容器标识；适配器可截断；不承诺完整、全局唯一或跨重启稳定。
- `runtime` 是稳定小写名，如 `docker`、`podman`、`containerd`、`kubernetes`、`none`；未知运行时可用适配器自定义小写名。
- `image` 是镜像引用；未知时为空串；不写入日志/错误详情。
- 非容器环境：`isContainerized` 为 false，`runtime` 为 `none`，`image` 为空串，两个列表为空；不报错。
- 容器环境：`isContainerized` 为 true，`id`/`runtime` 通常非空；列表可因权限或适配器裁剪而为空。
- 列表返回副本；顺序由适配器决定，不承诺稳定排序。
- 为什么是 class：多字段快照 + 两个列表；不用 enum 因为含开放字符串；不用 struct 以避免大列表值复制语义。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_containerId` | `String` | final | 非 null；可截断/为空 |
| `_runtime` | `String` | final | 非 null；稳定小写名 |
| `_image` | `String` | final | 非 null；可为空 |
| `_isContainerized` | `Bool` | final | 是否容器内 |
| `_namespaces` | `List<Namespace>` | final | 非 null；副本 |
| `_cgroups` | `List<Cgroup>` | final | 非 null；副本 |

不变量：字符串/列表非 null；`isContainerized=false` 时 `runtime="none"`、两个列表为空；
`isContainerized=true` 时 `id`/`runtime` 通常非空；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ContainerInfo(String containerId, String runtime, String image, Bool isContainerized, List<Namespace> namespaces, List<Cgroup> cgroups)` | 6 个字段 | 字符串/列表非 null | null → panic |

构造器主要供适配器/测试使用；业务代码通过 `ContainerHost.info` 获取。
`isContainerized` 与列表的一致性由适配器保证，构造器只检查 null。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `id` | 容器标识 | 无 | `String` | 无 | O(1)；可截断 |
| `runtime` | 运行时名 | 无 | `String` | 无 | O(1)；稳定小写 |
| `image` | 镜像引用 | 无 | `String` | 无 | O(1)；可为空 |
| `isContainerized` | 是否容器内 | 无 | `Bool` | 无 | O(1) |
| `namespaces` | namespace 快照 | 无 | `List<Namespace>` | 无 | O(n) 复制 |
| `cgroups` | cgroup 快照 | 无 | `List<Cgroup>` | 无 | O(n) 复制 |
| `describe` | 单行摘要 | 无 | `String` | 无 | O(n)；仅诊断 |

无 equals/copy：需要比较时逐字段比较；`==` 是引用身份。

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 稳定小写名归一；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、List；
- 运行时/适配器：容器/cgroup/namespace 读取；
- 接口：`Namespace`、`Cgroup`、`ContainerHost`。

---

## 10. 依赖的特性/接口/类

`Namespace`、`Cgroup`、`ContainerHost`、`OsHost`。

---

## 11. 所有权与并发

引用语义；不可变；可跨任务共享；`namespaces`/`cgroups` 返回副本；无资源；无取消点。
相等：`==` 是引用身份；本基线不提供 `equals`；需要比较时逐字段/逐列表比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：先看 `isContainerized()`，再决定是否使用 `id()`/`cgroups()`；日志只写摘要。  
反例：假设 `id` 完整；假设容器一定有 cgroup/namespace；假设列表顺序稳定；把镜像写入日志；
把非容器快照当错误。

---

## 13. 测试/场景义务

容器/非容器；空 namespace/cgroup；`runtime="none"`；ID 截断；未知运行时；镜像为空；
列表副本独立性；null 构造 panic；`describe`；容器内只含可见资源。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class ContainerInfo {
    final String _containerId
    final String _runtime
    final String _image
    final Bool _isContainerized
    final List<Namespace> _namespaces
    final List<Cgroup> _cgroups

    ContainerInfo(String containerId, String runtime, String image,
                  Bool isContainerized, List<Namespace> namespaces,
                  List<Cgroup> cgroups) {
        if containerId == null || runtime == null || image == null {
            throw "ContainerInfo: null field"
        }
        if namespaces == null || cgroups == null {
            throw "ContainerInfo: null list"
        }
        _containerId = containerId
        _runtime = runtime
        _image = image
        _isContainerized = isContainerized
        _namespaces = namespaces.copy()
        _cgroups = cgroups.copy()
    }

    String id() { return _containerId }

    String runtime() { return _runtime }

    String image() { return _image }

    Bool isContainerized() { return _isContainerized }

    List<Namespace> namespaces() { return _namespaces.copy() }

    List<Cgroup> cgroups() { return _cgroups.copy() }

    String describe() {
        return "container runtime=" + _runtime
            + " id=" + _containerId
            + " ns=" + str(_namespaces.length())
            + " cgroups=" + str(_cgroups.length())
    }
}
```
