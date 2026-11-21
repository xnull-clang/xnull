# `AnnotationProcessingResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationProcessingResult` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationDiagnostic`、`AnnotationDiagnosticSeverity`、`List`、`Map`、`String`、`Bool` |

---

## 1. 定位

单次处理器调用的不可变结果：诊断列表与生成源码映射。

不做：不做构建调度、不做文件写入、不做增量缓存、不做源码合并、不做错误恢复。

---

## 2. 设计逻辑

- 处理器通过返回本对象表达“诊断 + 生成物”；不通过异常/全局状态传递。
- 诊断顺序保留处理器产生顺序；构建系统可再聚合。
- 生成源码键是相对输出路径/逻辑名，值是完整源码文本；构建系统负责落盘与来源标记。
- 生成源码映射非 null、键非空、值非空；空结果用 `empty()`。
- `success()` 只在没有 `Error` 诊断时为 true；`Warning`/`Note` 不阻止成功。
- 构造时复制诊断列表和源码映射；读取时再复制；结果不可变。
- 生成失败不得返回半成品；处理器要么不生成，要么返回完整源码；诊断与生成物可以同时存在，由构建系统按 `success()` 决定是否采用。
- 处理器不得在本对象中放文件句柄、网络响应或可变缓冲区。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_diagnostics` | `List<AnnotationDiagnostic>` | 诊断快照；内部副本 |
| `_generatedSources` | `Map<String, String>` | 生成源码；键为逻辑路径，值为源码文本 |

不变量：

- `diagnostics` 非 null；元素非 null；保持输入顺序。
- `generatedSources` 非 null；键非空、值非空；键唯一。
- 构造后不可变；`diagnostics()` 与 `generatedSources()` 返回副本。
- `success()` 为 true 当且仅当没有 `Error` 级别诊断。
- 生成源码不包含绝对路径/目录穿越；路径合法性由构建系统最终校验。
- 不持有资源；无 close。

---

## 4. 生命周期

由处理器在构建期创建并返回；调度器读取后聚合；无 close；无资源；构建结束后回收；不进入运行时注册表。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationProcessingResult(List<AnnotationDiagnostic> diagnostics, Map<String, String> generatedSources)` | 全部 | diagnostics 非 null、元素非 null；generatedSources 非 null、键非空、值非空 | null/含 null/空键/空源码 → panic |
| `empty` | 无 | 无 | 无 |

说明：

- 诊断列表在构造时逐项复制；调用方之后修改原列表不影响结果。
- 生成源码映射在构造时逐项复制；调用方之后修改原映射不影响结果。
- 生成源码值去除首尾空白后不能为空；不要用空白文件占位。
- 不校验生成源码的语法；语法错误由后续编译轮次诊断。
- 不校验键的扩展名/目录；构建系统负责布局与安全。

---

## 6. 字段表

见 §3；字段私有、`final`。两个容器都保存内部副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `empty` | 空结果 | 无 | `AnnotationProcessingResult` | 无 |
| `diagnostics` | 诊断快照 | 无 | `List<AnnotationDiagnostic>` | 无 |
| `generatedSources` | 生成源码快照 | 无 | `Map<String, String>` | 无 |
| `success` | 是否无 Error | 无 | `Bool` | 无 |

说明：

- `diagnostics()` 每次返回新列表；顺序与构造输入一致。
- `generatedSources()` 每次返回新映射；键顺序不承诺。
- `success()` 不缓存；每次线性扫描诊断。
- 不提供 `errorCount`/`warningCount`；需要统计时调用方遍历诊断。
- 不提供 `merge`；多处理器结果由构建调度器聚合，避免把调度策略塞进结果对象。

---

## 8. 使用的技术

- 不可变结果对象；
- 防御性复制；
- 诊断聚合；
- 生成源码映射；
- 显式成功判定。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Map、String、Bool、String.trim；
- 编译器/构建系统：源码落盘、来源标记、聚合、缓存；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`AnnotationDiagnostic`、`AnnotationDiagnosticSeverity`、`List`、`Map`、`String`、`Bool`。

由 `AnnotationProcessor.process` 返回。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- 读取方法返回副本；生成源码字符串不可变。
- 不持有文件/网络/编译器句柄。
- 相等：没有值相等实现；`==` 是引用身份。

---

## 12. 示例与反例

正确：

```xnull
AnnotationProcessingResult result = new AnnotationProcessingResult(
    [
        new AnnotationDiagnostic(
            AnnotationDiagnosticSeverity.Warning,
            "ANN010",
            "optional field omitted",
            "app.Device#name"
        )
    ],
    [
        "app/generated/DeviceData.x": "class DeviceData { }"
    ]
)
Bool ok = result.success()
List<AnnotationDiagnostic> diagnostics = result.diagnostics()
Map<String, String> sources = result.generatedSources()
```

反例：用 `Error` 诊断却返回 `success() == true`；把 `Warning` 当失败；修改 `diagnostics()` 返回值期望改变结果；生成空源码占位；生成绝对路径；返回半成品源码并依赖构建系统清理；在结果里放文件句柄；运行时保存处理结果。

---

## 13. 测试/场景义务

- 空结果 `success()`；
- 仅 Warning/Note 的 `success()`；
- 含 Error 的 `success()`；
- 多级别混合；
- 诊断顺序；
- 生成源码键/值非空校验；
- 诊断列表与源码映射副本独立性；
- 生成源码多文件；
- 半成品拒绝策略；
- 不可变/并发只读。

---

## 14. XNull 伪代码

```xnull
class AnnotationProcessingResult {
    final List<AnnotationDiagnostic> _diagnostics
    final Map<String, String> _generatedSources

    AnnotationProcessingResult(List<AnnotationDiagnostic> diagnostics,
                               Map<String, String> generatedSources) {
        if diagnostics == null {
            throw "AnnotationProcessingResult: null diagnostics"
        }
        if generatedSources == null {
            throw "AnnotationProcessingResult: null generated sources"
        }
        _diagnostics = []
        Int diagnosticIndex = 0
        while diagnosticIndex < diagnostics.length() {
            AnnotationDiagnostic diagnostic = diagnostics.get(diagnosticIndex)
            if diagnostic == null {
                throw "AnnotationProcessingResult: null diagnostic"
            }
            _diagnostics.push(diagnostic)
            diagnosticIndex = diagnosticIndex + 1
        }
        _generatedSources = [:]
        List<String> names = generatedSources.keys()
        Int sourceIndex = 0
        while sourceIndex < names.length() {
            String name = names.get(sourceIndex)
            if name == null || trim(name) == "" {
                throw "AnnotationProcessingResult: empty source name"
            }
            String source = generatedSources.get(name)
            if source == null || trim(source) == "" {
                throw "AnnotationProcessingResult: empty source"
            }
            _generatedSources.put(name, source)
            sourceIndex = sourceIndex + 1
        }
    }

    static AnnotationProcessingResult empty() {
        return new AnnotationProcessingResult([], [:])
    }

    List<AnnotationDiagnostic> diagnostics() {
        return _diagnostics.copy()
    }

    Map<String, String> generatedSources() {
        Map<String, String> result = [:]
        List<String> names = _generatedSources.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, _generatedSources.get(name))
            index = index + 1
        }
        return result
    }

    Bool success() {
        Int index = 0
        while index < _diagnostics.length() {
            if _diagnostics.get(index).severity() == AnnotationDiagnosticSeverity.Error {
                return false
            }
            index = index + 1
        }
        return true
    }
}
```
