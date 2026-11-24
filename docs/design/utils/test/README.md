# `xdk.test` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.test` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.core`（`errors`、`execution`、`time`、`text`）、`xdk.collections` |
| 被依赖 | 应用自测、CI 任务、库的单元测试 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |
| 实现状态 | M11.1：`TestStatus`/`TestContext`/`Test`/`TestSuite`/`TestResult`/`TestRunner`/`Assert` implemented；断言 code 为 `test.assertion_failed`；`TestStatus` 内部 Unknown 占 0 号。M11.2：`@TestCase`/`@Before`/`@After`/`@Benchmark` 生成显式 Suite/Benchmarks；仅位置参数；方法支持 `void` 或 `Result<Unit, Error>`；Benchmark 不做统计/预热 |

---

## 1. 包定位

`xdk.test` 是进程内最小测试框架，只覆盖“定义测试、组织测试、顺序执行、得到快照”四件事：

- `Assert`：纯静态断言，成功 `Ok(unit)`，失败返回固定 `Err`；
- `Test`：不可变测试定义（名称、标签、超时、body）；
- `TestSuite`：命名的有序测试集合，不执行、不保存结果；
- `TestRunner`：顺序执行，处理取消与超时，返回结果快照；
- `TestResult`：单个测试的不可变结果快照；
- `TestStatus`：`Passed` / `Failed` / `Skipped`；
- `TestContext`：单个测试的日志、跳过、失败与取消视图。

不做终端输出、颜色、进度条、i18n 文案、全局测试注册表或自动发现。

---

## 2. 非目标

| 非目标 | 说明 |
| --- | --- |
| 全局注册表/自动发现 | 测试必须显式构造 `Test` 并加入 `TestSuite` |
| 并行执行 | `TestRunner` 顺序运行；并发由调用方在多个 Context 上自行组织 |
| 进程隔离 | body 在当前进程内运行；崩溃/`throw` 会终止进程 |
| mock/fixture/生命周期钩子 | 由调用方用普通变量、`defer`、`TaskGroup` 组织 |
| 快照/黄金文件/基准测试 | 不属于本包 |
| 覆盖率/重试/不稳定测试 | 由外部工具或调用方处理 |
| 报告器/i18n | 只返回 `TestResult` 与纯文本 `describe` |
| 异步测试 body | body 是同步函数值，返回 `Result<Unit, Error>` |
| 自定义断言错误类型 | 不新增第 8 个公开类型；用 `BasicError` + 固定 code |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Assert` | class（静态命名空间） | 13 组静态断言（含数值重载） | [`Assert.md`](Assert.md) |
| `Test` | class | 不可变测试定义 | [`Test.md`](Test.md) |
| `TestSuite` | class | 命名有序测试集合 | [`TestSuite.md`](TestSuite.md) |
| `TestRunner` | class | 顺序执行/取消/超时 | [`TestRunner.md`](TestRunner.md) |
| `TestResult` | class | 不可变结果快照 | [`TestResult.md`](TestResult.md) |
| `TestStatus` | enum | Passed/Failed/Skipped | [`TestStatus.md`](TestStatus.md) |
| `TestContext` | class | 日志/跳过/失败/取消 | [`TestContext.md`](TestContext.md) |

X：测试发现、并行执行、报告器、fixture 生命周期、覆盖率、远程执行。

---

## 4. 顶层函数

无。断言是 `Assert` 的静态方法；本包不提供全局 `assert` 函数、全局注册函数或隐式入口。

---

## 5. 技术/支撑/依赖

- 技术：`Result` 断言、不可变快照、有序集合、顺序执行、`TaskGroup` 截止等待、单调时钟、错误 code 判别。
- 支撑：`BasicError`、`ErrorKind`、`DetailedError`、`Context`、`TaskGroup`、`Task`、`nowMono`、`isCancellation`、`trim`、`replace`。
- 依赖：`xdk.core`（errors/execution/time/text）、`xdk.collections`；不依赖 terminal、i18n、log、metrics。

断言错误固定为：

| 项 | 值 |
| --- | --- |
| 类型 | `BasicError` |
| kind | `ErrorKind.Internal` |
| code | `test.assertion_failed` |
| describe | `[test.assertion_failed] Internal: <message>` |

`TestRunner` 以 `code` 判别断言失败，不以 `kind` 判别。`skip` 与 `fail` 也使用固定 code：`test.skipped`、`test.failed`。

---

## 6. 场景

### S2：最小测试

```xnull
Test test = new Test("adds", ["unit"], 0, (TestContext context) -> {
    Result<Unit, Error> checked = Assert.equals(2, 1 + 1, "")
    if checked.isErr() { return Err(checked.error()) }
    context.log("1 + 1 = 2")
    return Ok(unit)
})
TestSuite suite = new TestSuite("math")
suite.add(test)
TestRunner runner = new TestRunner()
List<TestResult> results = runner.run(Context.background(), suite)
```

### S3：按标签过滤

```xnull
TestSuite fast = suite.filter("fast")
List<TestResult> results = runner.runFiltered(
    Context.background(),
    fast,
    (Test test) -> test.timeoutMillis() == 0
)
```

### S4：超时与取消

测试 body 检查 `context.isCancelled()`；`TestRunner` 在 `timeoutMillis` 到达后取消并标记 `Failed`，错误为 `ErrorKind.Timeout`。取消是协作式的，不保证强行终止 body。

### S5：跳过与显式失败

```xnull
Test skipped = new Test("later", [], 0, (TestContext context) -> {
    return context.skip("not supported on this target")
})
Test failed = new Test("broken", [], 0, (TestContext context) -> {
    return context.fail("known defect")
})
```

### S5：多套件

```xnull
List<TestSuite> suites = [suite, fast]
List<TestResult> results = runner.runAll(Context.background(), suites)
```

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 断言失败通道 | XNull 的 `throw` 是 fatal/不可捕获；`Assert` 返回 `Err(BasicError(code=test.assertion_failed))`，`TestRunner` 映射为 `Failed`。文档语义上的“throw assertion error”由该 `Err` 表达 |
| 断言错误类型 | 不新增第 8 个公开类型；固定 `BasicError` + code，消费者匹配 code |
| 断言 `ErrorKind` | `ErrorKind` 没有 `AssertionFailed`；使用 `Internal` 仅作粗分类，固定 code 才是判别依据 |
| `skip`/`fail` | 不抛异常；返回 `Result<Unit, Error>` 的 `Err`，body 必须传播 |
| `throwsError` 命名 | XNull 无异常；断言一个 `Result` 操作返回 `Err`，并把该 `Error` 作为成功值返回 |
| `TestSuite` 执行 | 不执行；`TestRunner` 拥有执行权，返回 `List<TestResult>` 快照 |
| 结果聚合 | 不新增 `TestReport`；调用方聚合 `List<TestResult>` |
| 取消状态 | `TestStatus` 无 `Cancelled`；未开始测试不产生结果，运行中取消映射为 `Skipped` |
| 超时 | 协作取消；body 忽略取消时 `run` 可能超过 `timeoutMillis` 才返回 |
| 并发 | 只做顺序执行；`TestRunner` 无状态，可并发调用，但 `TestSuite` 不保证并发修改安全 |
| fail-fast | 不做；默认运行完所有测试，除非父 Context 取消 |
| 相等语义 | `Assert.equals` 使用 `==`；引用类型默认按身份，内容比较需调用方提供布尔判断 |
| 数值比较 | `lessThan`/`greaterThan` 提供 `Int`/`Long`/`Double` 重载 |
| 全局状态 | 禁止全局注册表、全局当前测试、全局日志缓冲 |
| 终端/i18n | 不做；`TestResult.describe` 只返回单行纯文本 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@TestCase`、`@Before`、`@After`、`@Benchmark` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | test_processor（Generate，构建期显式代码） |
| 生成物 | 测试清单、生命周期/基准元数据 |
| 状态 | `@TestCase`/`@Before`/`@After`/`@Benchmark` implemented (M11.2)；仅位置参数；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 测试方法 | `@TestCase` | 测试清单 |
| 前置/后置方法 | `@Before`/`@After` | 生命周期表 |
| 基准方法 | `@Benchmark` | 基准清单 |
| `TestResult`/`TestContext` | `@Value`/`@Builder` | 值语义/上下文 |

### 声明

```x
@Target(Method)
@Retention(Runtime)
@annotation TestCase {
    final String name = ""
}

@Target(Method)
@Retention(Runtime)
@annotation Before {
}

@Target(Method)
@Retention(Runtime)
@annotation After {
}

@Target(Method)
@Retention(Runtime)
@annotation Benchmark {
    final String name = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserTests {
    @Before void setUp() {
        // ...
    }

    @TestCase("find missing")
    void findMissing() {
        // ...
    }

    @After void tearDown() {
        // ...
    }
}
```

### 生成规则（M11.2）

对每个含 `@TestCase` 的类生成：

```x
TestSuite <Class>Suite(<Class> target)
```

对每个含 `@Benchmark` 的类生成：

```x
List<Test> <Class>Benchmarks(<Class> target)
```

- 测试/基准方法必须无参数且非静态；支持 `void` 或 `Result<Unit, Error>`，其他返回类型报 `AN2202`；
- 每个 case 生成独立的 `Result<Unit, Error>(TestContext)` body，固定顺序 `@Before` → 测试方法 → `@After`；
- `@Before` 失败：测试失败、不执行测试方法，`@After` 仍执行；`@After` 失败：测试方法成功时返回 After 错误，测试方法失败时保留测试方法错误；
- 每个类最多一个 `@Before` 和一个 `@After`，多个报 `AN2203`；
- 类只有 `@Before`/`@After` 而无 `@TestCase` 报 `AN2204` warning；
- 名称取注解位置参数，空串回退方法名；case 按声明顺序生成；
- `@Benchmark` 只生成可交给 `TestRunner` 的 `Test`，不做预热、统计或报告。

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
