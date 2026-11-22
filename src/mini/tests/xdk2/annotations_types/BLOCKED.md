# B2.1/B2.2 严格项 BLOCKED 证据

范围：`src/xdk/annotations/Annotations.x` 的 14 类型 + 只读注册表。
约束：本批不改 `src/mini/main.x`，不做 B2.3 编译器元数据发射。

以下差异不是设计选择，而是当前 mini 编译器能力/入口限制；实现用最小改动绕过，
其余契约继续交付。

## 1. `Float` 不是 mini 的通用类型

合同要求 `AnnotationValue.ofFloat(Float)` / `asFloat(): Float?`，字段 `_floatValue: Float?`。
mini 只在 FFI ABI 名称里识别 `Float`；普通声明报未知类型。

证据：

```text
$ cat /tmp/float_probe.x
static Float twice(Float v) { return v * 2.0 }
$ ./src/cli/xnull --bootstrap --engine=mini run /tmp/float_probe.x
...:1:1: [SEM-005] unknown type: Float
```

处置：`AnnotationValueKind.Float` 保留；`ofFloat` 接收 `Double`，`asFloat()` 返回
`Double?`，负载语义按 IEEE 浮点值处理。其余 11 个标签不受影响。

影响：Float 访问器签名与合同字面不一致；类型标签、工厂、describe、值树行为一致。

## 2. 自定义值类型的 `Map<K,V>` 需要 `xdk.collections` 的泛型 `Entry`

`Map<String, AnnotationValue>` 等自定义值映射会生成
`xn_Cls_Entry__String_AnnotationValue_new` 调用；若没有加载 `xdk.collections` 的泛型
`Entry<K,V>`，C 链接失败。

证据（不导入 `xdk.collections`）：

```text
error: call to undeclared function 'xn_Cls_Entry__String_Val_new'
xnull-build: cc link failed
```

处置：`Annotations.x` 增加 `import xdk.collections`（该包自身无 import，无环）。
这违反包 README 的“无其他 XDK 包”上游依赖表述；没有修改 `xdk.collections`。

## 3. `import xdk.annotations` 未注册到 mini 的 `xdkFile`

`src/mini/main.x` 的 `xdkFile` 没有 `xdk.annotations` 分支；本批禁止修改 `main.x`
（属于编译器/B2.3 边界）。因此场景不能写 `import xdk.annotations`。

处置：测试目录使用
`src/mini/tests/xdk2/annotations_types/annotations -> ../../../../xdk/annotations`
的符号链接，并写 `import annotations.Annotations`，确保测试加载真实实现文件，
不是副本。

影响：场景入口不是最终公开导入形态；等编译器注册包映射后可直接改为
`import xdk.annotations`。

## 4. 枚举没有 null 值，null 校验不可表达

XNull 枚举是值类型；`AnnotationTarget.Package`、`AnnotationValueKind.Bool`、
`AnnotationDiagnosticSeverity.Error`、`AnnotationProcessorPhase.Resolve` 的序号都是 0。
合同中的 `target == null` / `severity == null` / `phase == null` / `kind == null`
校验在 mini 中会把 0 号成员误判为 null（实测 `new AnnotationDiagnostic(Error, ...)`
触发 “null severity”）。

处置：删除这些枚举 null 校验；枚举本身不可为 null，构造契约的其余校验保留。
String/class 引用/容器仍保留 null 校验与 panic。

## 5. mini 限制导致的内部写法（不改变公开语义）

- 泛型 `Map.get` 在 mini 中不识别；内部统一使用 `has` + `getOr`。
- 类静态方法/后置类的调用缺少前向声明；渲染、键拼装、排序改为包内顶层辅助函数
  `annotations*`（不是 14 个公开类型之一）。
- 字段直接赋 `[:]` / `[]` 字面量不支持；构造器内先建局部容器再赋值。
- class 方法内引用后置枚举常量或后置类静态方法会生成未声明标识符；测试处理器
  通过顶层辅助函数调用，保持协议场景可运行。

## 6. 规范冲突的落地选择

`AnnotationRegistry` 合同伪代码的 `targetKey` 没有 `Annotation` 分支（会落入
`enum_item:`）；同文件的不变量/ARCHITECTURE §7 明确 11 个目标包含 `Annotation`。
实现采用 `annotation:` 前缀，保证 `ofTarget(Annotation, "app.Marker")` 可命中，
并与 11 目标表一致。
