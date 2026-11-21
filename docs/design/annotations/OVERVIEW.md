# 注解层

| 项 | 值 |
| --- | --- |
| 范围 | `xdk.annotations` 注解元模型/处理器合同/元注解 |
| 层 | 语言/编译期层，位于 core 之前 |
| 依赖 | 仅语言核心标量与容器；不依赖其他 XDK 包 |
| 被依赖 | 各领域注解、编译器、构建调度、IDE/文档工具 |
| 稳定性 | `preview`；设计基线，实现未开始 |
| 文档 | 1 包 / 14 类型 |

---

## 1. 定位

`xdk.annotations` 只做注解系统本身，不做具体领域能力：

- 注解目标、保留策略、常量值树；
- 注解信息/集合/运行时只读注册表；
- 构建期处理器阶段、上下文、诊断、生成结果；
- 元注解与处理器启用规则。

具体领域注解（`@Serializable`、`@Route`、`@Entity` 等）归各领域包，不放进 `xdk.annotations`。

权威设计：

- [`../ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md)
- [`annotations/README.md`](README.md)
- [`../ANNOTATION-PLAN.md`](../ANNOTATION-PLAN.md)

---

## 2. 包与类型

```text
xdk.annotations
  ├─ AnnotationTarget
  ├─ AnnotationRetention
  ├─ AnnotationValueKind
  ├─ AnnotationValue
  ├─ AnnotationInfo
  ├─ AnnotationSet
  ├─ AnnotationRegistry
  ├─ AnnotationElement
  ├─ AnnotationDiagnosticSeverity
  ├─ AnnotationDiagnostic
  ├─ AnnotationProcessorPhase
  ├─ AnnotationProcessorContext
  ├─ AnnotationProcessingResult
  └─ AnnotationProcessor
```

索引与契约见 [`annotations/README.md`](README.md)。

---

## 3. 顺序

```text
P1 annotations
  → P2 runtime/execution
    → P3 core
      → P4 data/encoding
        → P5 network
          → P6 platform/compute
            → P7 application services
              → P8 solutions
```

annotations 先冻结，core 才能引用注解目标/值树/处理器合同；领域包不得反向定义注解语义。

---

## 4. 边界

| 做 | 不做 |
| --- | --- |
| 注解声明/使用语法 | 通用运行时反射 |
| Source/Binary/Runtime 保留 | 类路径扫描/动态代理 |
| 构建期处理器 | 运行期注解处理器 |
| 生成成员/类型/元数据 | 修改已有声明 |
| 只读 `AnnotationRegistry` | 注解类加载/注解实例对象 |
| 领域注解接入矩阵 | 把领域注解塞进 `xdk.annotations` |

---

## 5. 校验

```text
 1 包 / 14 类型
annotations 14/14 类型，14 段
设计链接 0 broken
check_doc_naming PASS
src/xdk 无改动
```
