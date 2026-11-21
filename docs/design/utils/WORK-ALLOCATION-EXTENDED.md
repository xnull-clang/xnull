# `xdk.utils` X 扩展工作分配

| 项 | 值 |
| --- | --- |
| 目的 | 一次并行补齐 X：event/reflect/graph、compression 扩展、yaml/toml/xml（已完成） |
| 方法 | 盘点 → 冲突分析 → 不相交工作流 → 并行执行 → 统一集成 |
| 约束 | 只写设计文档；不改 `src/xdk`；共享 README 只由集成者修改 |

---

## 1. 盘点

| 包/位置 | 类型数 | 类型 |
| --- | ---: | --- |
| `xdk.event` | 3 | `Event`、`EventSubscription`、`EventBus` |
| `xdk.reflect` | 4 | `ReflectKind`、`MemberInfo`、`TypeInfo`、`Reflect` |
| `xdk.graph` | 2 | `GraphEdge`、`Graph` |
| `xdk.compress` 扩展 | 3 | `Zstd`、`Lz4`、`Brotli` |
| `xdk.yaml` | 5 | `Yaml`、`YamlOptions`、`YamlDocument`、`YamlPropertySource`、`YamlVersion` |
| `xdk.toml` | 2 | `Toml`、`TomlOptions` |
| `xdk.xml` | 3 | `Xml`、`XmlElement`、`XmlOptions` |

新增 6 个包、22 个类型。完成后 utils：

```text
24 个包
158 个类型文件
```

health 仍不建包，复用 `xdk.runtime`。

---

## 2. 冲突分析

- 新增包目录互不相交。
- `xdk.compress` 是既有包，只有 W10 可以修改其 README 与新增 3 个类型文件；其他流不得进入。
- 共享文件由集成者修改：
  - `docs/design/OVERVIEW.md`
  - `docs/design/README.md`
  - `docs/design/PLAN.md`
  - `docs/design/WORK-ALLOCATION-EXTENDED.md`
- `xdk.codec` 不扩展；YAML/TOML/XML 独立包，避免 codec 变成格式大杂烩。
- `xdk.event` 不复用 `xdk.runtime`/log；`xdk.reflect` 不依赖 graph；`xdk.graph` 不依赖 event。
- `xdk.compress.Zstd/Lz4/Brotli` 复用 `CompressionLevel`，不新建级别枚举。

---

## 3. 工作流

| 流 | 范围 | 产物 | 状态 |
| --- | --- | --- | --- |
| W7 | Event | 3 类型 + `event/README.md` | 已完成 |
| W8 | Reflect | 4 类型 + `reflect/README.md` | 已完成 |
| W9 | Graph | 2 类型 + `graph/README.md` | 已完成 |
| W10 | Compress 扩展 | 3 类型 + 更新 `compress/README.md` | 已完成 |
| W11 | YAML + TOML | 4 类型 + 两个 README | 已完成 |
| W12 | XML | 3 类型 + `xml/README.md` | 已完成 |

并行规则：

- 每个流只写自己负责的目录/文件；
- W10 独占 `utils/compress`；
- 不修改 `docs/design/OVERVIEW.md`、`utils/README.md`、`PLAN.md`、本文件；
- 类型名/字段/方法与盘点表一致；
- 每个类型 14 段；README 只留索引/规则/场景/缺口；
- 伪代码必须 XNull 形态。

---

## 4. 每类型 14 段

1. 定位
2. 设计逻辑
3. 表示与不变量
4. 生命周期
5. 构造契约
6. 字段表
7. 方法总表 / 详表
8. 使用的技术
9. 需要的支撑
10. 依赖的特性/接口/类
11. 所有权与并发
12. 示例与反例
13. 测试/场景义务
14. XNull 伪代码

禁止：`Void`、空参数 `Ok()`、`Result<void>`、`self._`、`self(...)`、`new T()`、`// ...`、小写辅助文件。

---

## 5. 集成校验

1. 新增 22 个类型文件；
2. README 索引与文件一致；
3. 每个类型 14 段；
4. 相对链接 0 broken；
5. `check_doc_naming.py` PASS；
6. 扫描非 XNull 写法；
7. 更新  总览/PLAN/utils README；
8. `src/xdk` 无改动。

---

## 6. 验收

```text
24 个包
158 个类型文件
24 个包 README
158/158 14 段
0 broken links
0 banned pseudo-code patterns
src/xdk 未改动
```
