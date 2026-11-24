# `TestStatus`

| 项 | 值 |
| --- | --- |
| 类型 | `enum TestStatus` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

单个测试结果的封闭状态：通过、失败、跳过。

不做：取消状态、执行中状态、错误分类、重试状态、进度状态、统计聚合。

---

## 2. 设计逻辑

- `Passed`：body 返回 `Ok(unit)`。
- `Failed`：body 返回非跳过类 `Err`，或超时。
- `Skipped`：body 通过 `TestContext.skip` 返回跳过信号；运行器取消时也可映射为 `Skipped`。
- 没有 `Cancelled` 状态；取消由 `TestContext`/`Context` 表达，结果层面映射为 `Skipped` 或不产生结果。
- 没有 `Running`/`Pending`；未开始的测试不生成 `TestResult`。
- 枚举值语义；无行为、无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Passed` | 测试成功 |
| `Failed` | 测试失败（断言、显式失败、超时、其他错误） |
| `Skipped` | 测试被跳过 |

不变量：成员固定为三项；实现内部以 `Unknown` 占 0 号，避免 0/null 哨兵；不提供整数码/序号持久化。

---

## 4. 生命周期

值类型；无 close；无资源；可作 Map 键、可比较、可跨任务复制。

---

## 5. 构造契约

枚举成员直接使用；不提供 `fromCode`/`fromName` 转换；需要文本时由 `TestResult` 的 `describe` 输出稳定英文名。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法。状态文本由 `TestResult.describe` 输出：`Passed`、`Failed`、`Skipped`。

说明：

- 不提供 `isSuccess` 等便捷方法；调用方直接比较枚举。
- 不提供数字序号；避免把持久化格式绑定到声明顺序。

---

## 8. 使用的技术

- 简单枚举；
- 值语义；
- 显式状态分类。

---

## 9. 需要的支撑

- 语言：enum、Bool、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可跨任务共享；线程安全。

---

## 12. 示例与反例

正确：`if result.status() == TestStatus.Failed { ... }`。  
反例：增加 `Cancelled` 表示超时；用整数保存状态；把 `Skipped` 当 `Passed`；期望枚举携带错误文本。

---

## 13. 测试/场景义务

三个成员；`describe` 文本；比较与 Map 键；跳过/失败/通过映射；取消映射为 `Skipped`；无未开始结果。

---

## 14. XNull 伪代码

```xnull
enum TestStatus {
    Passed,
    Failed,
    Skipped,
}
```
