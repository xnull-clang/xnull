# `TestRunner`

| 项 | 值 |
| --- | --- |
| 类型 | `class TestRunner` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Task`、`TaskGroup`、`Test`、`TestSuite`、`TestContext`、`TestResult`、`TestStatus`、`Error`、`DetailedError`、`ErrorKind`、`nowMono`、`isCancellation` |

---

## 1. 定位

顺序测试执行器：运行单个套件、多个套件或按谓词过滤后的测试，返回不可变 `TestResult` 快照。

不做：并行执行、自动发现、全局注册、报告器、失败重试、进程隔离、覆盖率、fixture 生命周期、套件级超时。

`TestRunner` 拥有执行权；`TestSuite` 只提供测试集合。

---

## 2. 设计逻辑

- 无实例字段；`TestRunner` 是无状态对象，可并发调用。
- `run` 先取 `suite.tests()` 快照，再顺序执行。
- 每个测试创建独立的 `TestContext` 与子 `Context`；测试之间不共享日志/取消状态。
- `timeoutMillis == 0`：在当前任务内直接调用 body，无截止。
- `timeoutMillis > 0`：用 `TaskGroup` 运行 body，`Task.joinDeadline` 等待；超时后取消测试 Context、关闭任务组。
- 超时结果固定为 `Failed`，错误来自 `joinDeadline` 的 `ErrorKind.Timeout`。
- body 返回 `Ok(unit)` → `Passed`；返回 `Err` → 按 code/kind 映射。
- runner 以 `Result` 方式“捕获”断言错误：body 返回 `Err` 后按 code 识别，不依赖语言异常。
- 断言失败（code `test.assertion_failed`）与显式失败（code `test.failed`）→ `Failed`。
- 跳过（code `test.skipped`）→ `Skipped`。
- `ErrorKind.Cancelled` → `Skipped`；未开始的测试在取消后不产生结果。
- runner 不捕获 `throw`/panic：XNull 的 `throw` 是 fatal；body 必须用 `Result` 表达失败。
- 每个测试结束后继续下一个，除非父 Context 已取消；无 fail-fast 选项。
- 耗时从测试开始到结果决定（含超时后的 `TaskGroup.close` 等待）。

---

## 3. 表示与不变量

无实例字段。

| 不变量 | 说明 |
| --- | --- |
| 无状态 | 所有运行状态都在局部变量中 |
| 顺序 | 按 suite 顺序与测试插入顺序执行 |
| 隔离 | 每测试独立 `TestContext`/子 `Context` |
| 快照 | 返回 `List<TestResult>`，不返回可变内部状态 |
| 取消 | 父 Context 取消后不再启动新测试 |
| 超时 | 每测试独立；0 表示无截止 |
| 失败不中断 | 默认继续执行后续测试 |

---

## 4. 生命周期

`TestRunner` 构造后长期可用；无 close；无资源。每次 `run` 创建局部任务组并在返回前关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TestRunner()` | 无 | 无状态 | 无 |

`run`/`runAll`/`runFiltered` 的 null 参数是合同错误，panic。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `run` | 运行单个套件 | `Context context, TestSuite suite` | `List<TestResult>` | null → panic |
| `runAll` | 顺序运行多个套件 | `Context context, List<TestSuite> suites` | `List<TestResult>` | null/元素 null → panic |
| `runFiltered` | 运行谓词选中的测试 | `Context context, TestSuite suite, Bool(Test) predicate` | `List<TestResult>` | null → panic |

说明：

- `run` 返回该 suite 中已执行测试的结果；父 Context 已取消时返回空列表，运行中取消时返回部分结果。
- `runAll` 按输入顺序拼接各 suite 结果；任一时刻父 Context 取消后停止，不再启动后续 suite。
- `runFiltered` 先对 `suite.tests()` 快照应用谓词，再顺序运行；谓词按测试插入顺序调用；父 Context 已取消时不调用谓词并返回空列表。
- 结果顺序 = 实际执行顺序；不排序、不聚合。
- 未开始的测试没有 `TestResult`；不存在 `Pending` 状态。
- 超时错误由 `joinDeadline` 提供；`TestResult.error()` 非 null。
- 已完成的任务即使 deadline 已过也返回结果（完成优先）；只有未完成的任务才产生 `Timeout`。
- `TaskGroup.spawn` 失败时先 `close` 清理；结果保留 spawn 错误，清理错误不覆盖它。
- `TestContext.skip` 的 `Err` 在结果中保留为 `Skipped` 的 error；`TestContext.fail` 保留为 `Failed` 的 error。
- body 内的 `throw` 不被捕获，进程终止；这是明确的非目标。
- runner 不记录终端输出；日志只来自 `TestContext.log`/`skip`/`fail`；断言错误不自动写入日志，而是保存在 `TestResult.error()`。

---

## 8. 使用的技术

- 顺序循环；
- 每测试子 Context；
- 结构化并发任务组；
- 单调截止等待；
- 错误 code/kind 映射；
- 不可变结果快照。

---

## 9. 需要的支撑

- 语言：class、List、Bool、Long、String、Result、Unit、函数类型、lambda；
- 运行时：`nowMono`、`Context` 取消可见性、任务调度；
- 接口：`TaskGroup`、`Task`、`TestContext`、`TestResult`、`TestStatus`、`DetailedError`、`isCancellation`。

---

## 10. 依赖的特性/接口/类

`Context`、`Task`、`TaskGroup`、`Test`、`TestSuite`、`TestContext`、`TestResult`、`TestStatus`、`Error`、`DetailedError`、`ErrorKind`、`nowMono`、`isCancellation`。

---

## 11. 所有权与并发

无状态；`TestRunner` 可被多个任务同时使用。每次运行使用独立局部结果、`TestContext` 和任务组。`TestSuite` 不是线程安全容器，调用方不得在运行期间并发修改；`Test` body 捕获的共享状态由调用方负责同步。

---

## 12. 示例与反例

正确：

```xnull
TestRunner runner = new TestRunner()
List<TestResult> results = runner.run(Context.background(), suite)
Int failed = 0
Int index = 0
while index < results.length() {
    if results.get(index).status() == TestStatus.Failed {
        failed = failed + 1
    }
    index = index + 1
}
```

反例：期望 runner 捕获 `throw`；在 body 中无限阻塞且不检查取消；运行期间并发修改 suite；把 `timeoutMillis == 0` 当立即超时；期望失败后自动停止；依赖并行顺序。

---

## 13. 测试/场景义务

单测试通过/失败/跳过；多个测试顺序；`runAll` 拼接；`runFiltered` 谓词与空结果；父 Context 运行前取消/运行中取消；超时触发与超时错误；超时后 body 检查取消；body 返回 `Cancelled`；断言/显式失败 code 映射；任务组关闭错误；耗时非负；并发调用同一 runner；suite 为空。

---

## 14. XNull 伪代码

```xnull
class TestRunner {
    TestRunner() {
    }

    List<TestResult> run(Context context, TestSuite suite) {
        if context == null || suite == null {
            throw "TestRunner.run: null argument"
        }
        return self.runTests(context, suite.tests())
    }

    List<TestResult> runAll(Context context, List<TestSuite> suites) {
        if context == null || suites == null {
            throw "TestRunner.runAll: null argument"
        }
        List<TestResult> results = []
        List<TestSuite> snapshot = suites.copy()
        Int index = 0
        while index < snapshot.length() {
            if context.isCancelled() {
                break
            }
            TestSuite suite = snapshot.get(index)
            if suite == null {
                throw "TestRunner.runAll: null suite"
            }
            results.addAll(self.run(context, suite))
            index = index + 1
        }
        return results
    }

    List<TestResult> runFiltered(Context context, TestSuite suite,
                                 Bool(Test) predicate) {
        if context == null || suite == null || predicate == null {
            throw "TestRunner.runFiltered: null argument"
        }
        if context.isCancelled() {
            return []
        }
        List<Test> selected = []
        List<Test> tests = suite.tests()
        Int index = 0
        while index < tests.length() {
            Test test = tests.get(index)
            if predicate(test) {
                selected.push(test)
            }
            index = index + 1
        }
        return self.runTests(context, selected)
    }

    private List<TestResult> runTests(Context context, List<Test> tests) {
        List<TestResult> results = []
        Int index = 0
        while index < tests.length() {
            if context.isCancelled() {
                break
            }
            Test test = tests.get(index)
            results.push(self.executeOne(context, test))
            index = index + 1
        }
        return results
    }

    private TestResult executeOne(Context context, Test test) {
        Context testRunContext = Context.withCancel(context)
        TestContext testContext = new TestContext(test.name(), testRunContext)
        Result<Unit, Error>(TestContext) body = test.body()
        Long start = nowMono()
        Result<Unit, Error> outcome = Ok(unit)
        if test.timeoutMillis() == 0 {
            outcome = body(testContext)
        } else {
            TaskGroup group = TaskGroup.create(context)
            Result<Task<Unit>, Error> spawned = group.spawn((Context taskContext) -> {
                return body(testContext)
            })
            if spawned.isErr() {
                Result<Unit, Error> closed = group.close()
                outcome = Err(spawned.error())
            } else {
                Task<Unit> task = spawned.value()
                Long deadline = nowMono() + test.timeoutMillis()
                Result<Unit, Error> joined = task.joinDeadline(deadline)
                if joined.isErr() && joined.error().kind() == ErrorKind.Timeout {
                    testRunContext.cancel()
                }
                Result<Unit, Error> closed = group.close()
                outcome = joined
                if joined.isOk() && closed.isErr() {
                    outcome = Err(closed.error())
                }
            }
        }
        Long duration = nowMono() - start
        TestStatus status = TestStatus.Passed
        Error? error = null
        if outcome.isErr() {
            Error failure = outcome.error()
            error = failure
            status = self.statusFor(failure)
        }
        return new TestResult(
            test.name(),
            status,
            duration,
            error,
            testContext.logs()
        )
    }

    private TestStatus statusFor(Error failure) {
        String code = ""
        if failure is DetailedError {
            code = failure.code()
        }
        if code == "test.skipped" {
            return TestStatus.Skipped
        }
        if code == "test.assertion_failed" {
            return TestStatus.Failed
        }
        if code == "test.failed" {
            return TestStatus.Failed
        }
        if isCancellation(failure) {
            return TestStatus.Skipped
        }
        return TestStatus.Failed
    }
}
```
