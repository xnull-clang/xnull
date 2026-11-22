# `ConfigSource`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ConfigSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `ConfigEntry`、`Context`、`Error` |

---

## 1. 定位

配置来源协议：加载一组键值条目；名称/优先级。

不做：合并（Overlay）、类型转换、热更新。

---

## 2. 设计逻辑

- `load(Context)` 返回条目列表；可取消。
- 1.x 无 Context 的 `Config.apply(ConfigSource)` 由 `Config` 的兼容重载用 `Context.background()` 适配；`ConfigSource` 本身仍要求 Context。
- `name()` 诊断用；`priority()` 越大越优先（由 Overlay 使用）。
- 来源不持有全局状态；失败返回 Result。
- 不负责 key 去重；Overlay 负责。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

实现决定；文件源按需打开/关闭。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 加载 | `Context` | `Result<List<ConfigEntry>, Error>` | `Io`/`Cancelled`/`DataCorrupted` |
| `name` | 名称 | 无 | `String` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 条目列表；
- 优先级。

---

## 9. 需要的支撑

- 语言：protocol、List、Int、String、Result；
- 运行时：实现决定；
- 接口：`ConfigEntry`、`Context`、`Error`。

---

## 10. 依赖的特性/接口/类

`ConfigEntry`、`Context`、`Error`。

---

## 11. 所有权与并发

来源由 Loader/调用方持有；并发由实现声明。

---

## 12. 示例与反例

正确：MapSource/FileSource/EnvSource。  
反例：load 改全局；忽略 Context；返回 null。

---

## 13. 测试/场景义务

load 成功/失败；取消；name/priority；空来源。

---

## 14. XNull 伪代码

```xnull
protocol ConfigSource {
    Result<List<ConfigEntry>, Error> load(Context context);
    String name();
    Int priority();
}
```
