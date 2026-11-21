# `ProfileSource`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ProfileSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `CoreProfile`、`Context`、`Error` |

---

## 1. 定位

能力画像来源协议：从配置/环境/测试加载一个完整的 `CoreProfile`。

不做：逐键合并、热更新、权限校验、网络拉取、全局注册。

---

## 2. 设计逻辑

- 一个来源返回**完整画像**，不是零散键；应用/加载器决定来源顺序。
- `load(Context)` 可取消；失败返回 `Result`，不 panic 表达配置错误。
- `name()` 只用于诊断；不参与优先级。
- 来源不修改全局状态；文件/环境由实现关闭或只读。
- 实现必须校验 `CoreProfile.isCoherent()`；不自洽返回 `InvalidArgument`。
- 不提供 `priority()`：画像不是覆盖键值，多个来源由调用方显式选择。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

实现决定；配置文件按需打开/关闭；无全局缓存。

---

## 5. 构造契约

协议无构造；由实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 加载画像 | `Context context` | `Result<CoreProfile, Error>` | `InvalidArgument`/`NotFound`/`Io`/`Cancelled` |
| `name` | 来源名 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 不可变画像；
- Result/Context；
- 配置解析。

---

## 9. 需要的支撑

- 语言：protocol、Result、String；
- 运行时：实现决定；
- 接口：`CoreProfile`、`Context`、`Error`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CoreProfile`、`Context`、`Error`、`BasicError`。

---

## 11. 所有权与并发

来源由调用方持有；并发由实现声明；不得跨任务共享可变解析状态。
相等：协议无值语义；实现身份由具体类决定。

---

## 12. 示例与反例

正确：`ConfigProfileSource` 从 `Config` 读取角色/能力/上限。  
反例：来源直接读全局环境；`load` 返回不完整画像；忽略 `Context`；用 `priority` 隐式覆盖。

---

## 13. 测试/场景义务

成功/缺失角色；非法枚举；非法数字；不自洽画像；取消；文件错误；空来源；
多次 `load` 一致性。

---

## 14. XNull 伪代码

```xnull
protocol ProfileSource {
    Result<CoreProfile, Error> load(Context context);
    String name();
}
```
