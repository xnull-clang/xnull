# B2.3 / B2-fix 严格项状态

## B2-fix 四项：PASS

### 1. `xdk.collections` 依赖：已移除

- `src/xdk/annotations/Annotations.x` 不再 `import xdk.collections`。
- 根因是 CGen 为每个 `Map<K,V>` 无条件发射 `entries()` 辅助函数；自定义值类型
  会引用未生成的 `Entry__K_V`。B2-fix 改为只在 `Entry__K_V` 类存在时发射该辅助函数。
- 证据：不导入 `xdk.collections` 的 `annotations_types_*` 场景全部编译运行通过；
  `xdk2.sh` 全绿。

### 2. `Float`：已按 Double 别名支持

- 编译器把 `Float` 纳入已知类型，C 表示与 `Double` 相同（`double`）；
  `Float`/`Double` 赋值与算术互通；`print`/`str` 走 Double 分支。
- `AnnotationValue` 恢复合同签名：`ofFloat(Float)`、`asFloat(): Float?`、
  字段 `Float?`；`AnnotationValueKind.Float` 与 `Float(...)` 描述保留。
- 证据：`annotations_types_values` 覆盖 `Float ratio = 1.25` 与
  `AnnotationValue.ofFloat(ratio)`；B2.3 场景覆盖注解字段 `Float ratio` 生成
  `Float(2.5)`。

### 3. 枚举 null：已从构造契约移除

- XNull 枚举是值类型；0 号成员（`Package`/`Bool`/`Error`/`Resolve`）不是 null。
- 实现删除不可表达的枚举 null 校验，文档构造契约改为“枚举不可为 null”。
- 证据：`annotations_types_diagnostics` 构造 `AnnotationProcessorPhase.Resolve`；
  `annotations_types_registry` 构造 `AnnotationTarget.Package`；
  `annotations_types_values` 构造 `AnnotationValueKind.Bool`；
  诊断场景构造 `AnnotationDiagnosticSeverity.Error`。

### 4. `targetKey` 的 `Annotation` 分支：已统一

- 实现与文档统一为 `annotation:` 前缀。
- 证据：B2.1 注册表场景与 B2.3 生成表场景都用
  `ofTarget(AnnotationTarget.Annotation, "app.Marker")` 命中。

## 剩余限制（不是 B2-fix 四项）

| 项 | 状态 | 证据/影响 |
| --- | --- | --- |
| `Deinit` 源语法 | 已支持 | `class` 的 `deinit()` 解析为 `Deinit` 节点，注册表用 `owner#deinit()`；见 `src/mini/tests/deinit/deinit_registry.x`。 |
| 导入包的注解全限定名 | 限制 | mini 合并 AST 时丢弃被导入文件的 `Package` 节点；B2.3 的生成 `typeName` 对同包声明加当前包前缀，对跨包注解无法恢复其声明包。当前 B1 注解解析也只按简单名解析。 |
| 生成入口的编译期形态 | 说明 | `xdkAnnotationRegistry()` / `xdkAnnotationRegistryVersion()` 是编译器生成的 X/C 入口，不是 14 个元模型类型之一；文档已在 `docs/design/annotations/README.md` §5.1 记录。 |
