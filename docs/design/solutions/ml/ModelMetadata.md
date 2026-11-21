# `ModelMetadata`

| 项 | 值 |
| --- | --- |
| 类型 | `class ModelMetadata` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `MlTask`、`Map`、`String` |

---

## 1. 定位

模型描述快照：名称、版本、生产者、说明、领域、任务、许可证和自定义键值。

只描述模型“是什么”，不包含权重、图结构、输入输出形状、执行提供者或运行时句柄。元数据不参与推理调度。

不做：模型身份认证、签名校验、下载、缓存、版本比较、许可证合规判断、训练超参数、Tensor 形状。

---

## 2. 设计逻辑

- 用 `class` 而不是 `enum`：字段是开放的文本/映射，且需要复制映射、校验键值。
- 不可变值对象：构造后字段只读；`customMetadata()` 返回副本。
- `name` 必填且非空；其余文本字段允许空串，空串表示“未提供”，不表示 `null`。
- `task` 必填；未知任务用 `MlTask.Other`，不把任务猜成文本分类。
- 自定义元数据是 `Map<String,String>` 快照；键非空，值非 null；不承诺顺序。
- 不包含 `ModelFormat`：格式属于 [`Model`](Model.md)，同一元数据可对应不同容器。
- 不读取文件/网络；由调用方从模型包或配置构造。
- 不提供 `equals`：文本元数据比较成本低但无稳定哈希合同；需要时逐字段比较。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空模型名 |
| `_version` | `String` | final | 非 null；空串表示未提供 |
| `_producer` | `String` | final | 非 null；空串表示未提供 |
| `_description` | `String` | final | 非 null；可空串 |
| `_domain` | `String` | final | 非 null；可空串 |
| `_task` | `MlTask` | final | 非 null |
| `_license` | `String` | final | 非 null；可空串 |
| `_customMetadata` | `Map<String,String>` | final | 私有快照；键非空；值非 null |

不变量：所有字段非 null；`_name` 非空；`_task` 合法；映射键非空；映射值非 null；构造后不可变；映射返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无外部资源；可跨任务共享；GC 管理内存。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ModelMetadata(String name, String version, String producer, String description, String domain, MlTask mlTask, String license, Map<String,String> customMetadata)` | 名称、版本、生产者、说明、领域、任务、许可证、自定义元数据 | 全部非 null；`name` 非空；`mlTask` 合法；映射键非空、值非 null | 违约 → panic |

构造器复制 `customMetadata`；调用方之后修改原映射不影响元数据。

---

## 6. 字段表

见 §3；字段私有。不暴露可变映射、文件路径或运行时对象。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 模型名 | 无 | `String` | 无 | O(1) |
| `version` | 版本 | 无 | `String` | 无 | 空串表示未提供 |
| `producer` | 生产者 | 无 | `String` | 无 | 空串表示未提供 |
| `description` | 说明 | 无 | `String` | 无 | 可空串 |
| `domain` | 领域 | 无 | `String` | 无 | 可空串 |
| `mlTask` | 任务 | 无 | `MlTask` | 无 | 非 null |
| `license` | 许可证 | 无 | `String` | 无 | 可空串 |
| `customMetadata` | 自定义元数据副本 | 无 | `Map<String,String>` | 无 | O(n) 复制 |
| `customValue` | 按 key 读自定义值 | `String key` | `String?` | null key → panic | 缺失 → null |
| `describe` | 单行描述 | 无 | `String` | 无 | 不包含权重 |
| `copy` | 复制 | 无 | `ModelMetadata` | 无 | 新快照 |

说明：

- `customValue` 的 key 必须非空；空串或缺省返回 `null`；不区分大小写折叠。
- `describe` 形如 `metadata name=demo task=text-classification version=1.0`；不输出自定义映射的全部内容，避免泄露敏感配置。
- `copy` 与构造器共享语义：新对象、映射副本；文本字符串不可变可共享。
- 不提供 `withName`/`withVersion` 等修改器；需要变更时用构造器创建新元数据。

---

## 8. 使用的技术

- 不可变值对象；
- 映射复制；
- 文本字段归一（空串表示未提供）；
- 稳定单行描述；
- 与格式/运行时解耦。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Map、Bool；
- 运行时：映射复制、字符串拼接；
- 接口：[`MlTask`](MlTask.md)、[`Model`](Model.md)。

---

## 10. 依赖的特性/接口/类

[`MlTask`](MlTask.md)、[`Model`](Model.md)、[`ModelFormat`](ModelFormat.md)。

不依赖 `xdk.config`、`xdk.io`、`xdk.fs` 或任何模型运行时类型。

---

## 11. 所有权与并发

不可变；可共享；`customMetadata()` 返回副本；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；需要比较时逐字段/逐映射比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new ModelMetadata("resnet50", "1.0", "acme", "图像分类", "vision", MlTask.ImageClassification, "Apache-2.0", ["source":"registry"])`；用 `MlTask.Other` 表示未知任务；用自定义键记录数据来源但不放密钥。  
反例：把许可证字段当法律结论；把空串当“字段不存在”并据此拒绝模型；在自定义元数据里放 token/密码；构造后修改传入映射并期望元数据变化；用名称猜测 `MlTask`。

---

## 13. 测试/场景义务

名称空串 panic；其余文本 null panic；`task` null panic；映射键空串 panic；映射值 null panic；映射复制独立性；`customValue` 命中/缺失/null key；`copy` 独立；`describe` 稳定；空版本/空许可证可接受；不泄露映射内容。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class ModelMetadata {
    final String _name
    final String _version
    final String _producer
    final String _description
    final String _domain
    final MlTask _task
    final String _license
    final Map<String, String> _customMetadata

    ModelMetadata(String name, String version, String producer,
                  String description, String domain, MlTask mlTask,
                  String license, Map<String, String> customMetadata) {
        if name == null || version == null || producer == null {
            throw "ModelMetadata: null text field"
        }
        if description == null || domain == null || license == null {
            throw "ModelMetadata: null text field"
        }
        if mlTask == null || customMetadata == null {
            throw "ModelMetadata: null task or metadata"
        }
        if name == "" {
            throw "ModelMetadata: empty name"
        }
        Map<String, String> copiedMetadata = [:]
        List<String> keys = customMetadata.keys()
        Int keyIndex = 0
        while keyIndex < keys.length() {
            String key = keys.get(keyIndex)
            String metadataValue = customMetadata.get(key)
            if key == null || key == "" {
                throw "ModelMetadata: empty metadata key"
            }
            if metadataValue == null {
                throw "ModelMetadata: null metadata value"
            }
            copiedMetadata.put(key, metadataValue)
            keyIndex = keyIndex + 1
        }
        _name = name
        _version = version
        _producer = producer
        _description = description
        _domain = domain
        _task = mlTask
        _license = license
        _customMetadata = copiedMetadata
    }

    String name() { return _name }
    String version() { return _version }
    String producer() { return _producer }
    String description() { return _description }
    String domain() { return _domain }
    MlTask mlTask() { return _task }
    String license() { return _license }
    Map<String, String> customMetadata() { return _customMetadata.copy() }

    String? customValue(String key) {
        if key == null { throw "ModelMetadata.customValue: null key" }
        if key == "" { return null }
        return _customMetadata.get(key)
    }

    String describe() {
        return "metadata name=" + _name
            + " task=" + mlTaskName(_task)
            + " version=" + _version
    }

    ModelMetadata copy() {
        return new ModelMetadata(_name, _version, _producer, _description,
            _domain, _task, _license, _customMetadata)
    }
}
```
