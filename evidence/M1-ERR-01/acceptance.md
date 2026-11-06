# ERR-01 验收记录（M1 小时制）

> 锚点：ERR-01（S1 §10）　主责：CEO1-RD2　会签：CEO1-QA1
> 基线：`pod/c1-rd2` @ `81ec33d`　被测文件：`impl/internal/sema/{error.go,ty.go,typedecl.go,err01_test.go}`
> 口径：先红后绿；未改既有测试期望、未删测试、未改台账/`status.tsv`、未跨域改文件。

## 一、逐项检查表（12/12）

| # | 台账要点 | 结论 | 新增/既有证据 |
|---|---|---|---|
| ERR01-01 | `Result` 构造 | **绿** | `TestERR01ResultConstructionPositive/Negative`：Ok/Err 目标类型、Ok() 仅 void、E≠void、无目标报 ERR-202 |
| ERR01-02 | `Result` 成员 | **绿** | `TestERR01ResultMembersPositive/Negative`：isOk/isErr/value/error 无参、unwrapOr 一参、void 成员、未知成员 |
| ERR01-03 | `@mustUse` | **绿** | `TestERR01MustUse`：裸变量/裸调用/裸 Ok/defer 内未处理 → ERR-201；赋值/返回/容器/成员调用合法 |
| ERR01-04 | `try` 传播 | **绿** | `TestERR01TryPositive/Negative`、`TestERR01LambdaTry`：仅 Result、外层 Result、E→E2、void 语句、嵌套、main/ctor/deinit/defer 禁用、闭包目标 |
| ERR01-05 | 错误类型检查 | **绿**（含边界） | `TestERR01ErrorTypeVoid`、构造/`try` 负例：两个实参、E≠void、Ok/Err 实参匹配、E→E2 同型/Object/Any |
| ERR01-06 | `defer`/`errdefer` LIFO | **绿**（既有） | `internal/interp/hard_test.go`：`TestErrReturnRunsDeferAndErrdeferLIFO`、`TestOkReturnSkipsErrdefer`、`TestThrowSkipsDefer`；interp 包全量通过 |
| ERR01-07 | 触发条件 | **绿** | 既有 LIFO/Ok/错误路径用例；新增 `TestERR01ErrdeferContext`：非 Result 函数/构造器 `errdefer` → ERR-206 |
| ERR01-08 | 清理体限制 | **绿** | `TestERR01CleanupRestrictions`：return/break/continue/goto/try/throw/嵌套 defer/errdefer/闭包/单条局部声明 → ERR-205；合法清理体零诊断 |
| ERR01-09 | `isOk` 正确使用 | **绿** | 既有 `TestResultTry` 正向；新增成员 arity/返回 Bool 用例 |
| ERR01-10 | `isErr` 正确使用 | **绿** | 同上 |
| ERR01-11 | `value` 正确使用 | **绿**（含未测项） | 正向既有 `TestResultTry`；新增 `Result<void,E>` 禁用 + arity；运行期 Err→value panic 探针 `after/illegal-value.*`（exit 134） |
| ERR01-12 | `error` 正确使用 | **绿**（含未测项） | 同上；运行期 Ok→error panic 探针 `after/illegal-error.*`（exit 134） |

## 二、红→绿证据

| 阶段 | 命令 | 结果 | 文件 |
|---|---|---|---|
| 红 | `cd impl && go test ./internal/sema -run TestERR01 -count=1 -v` | **FAIL**：8 个测试函数、43 个子用例失败；3 个正向用例当时已通过 | `before/test.log`、`before/exit_code.txt` |
| 绿 | 同命令 | **PASS**：8/8 测试函数、全部子用例 | `after/sema-err01.log`、`after/sema-err01.exit` |

## 三、回归与双路径

| 项 | 命令 | 结果 | 文件 |
|---|---|---|---|
| sema 全量 | `go test ./internal/sema -count=1` | ok（既有 34 + 新增 11 个测试函数） | `after/sema-full.log` |
| 解释器全量（ERR-01 运行期面） | `go test ./internal/interp -count=1` | ok | `after/interp.log` |
| 示例双路径（9/9） | `go test ./internal/codegen -run 'TestExamplesCompileMatchesInterp\|TestCompileDeferSemantics\|TestMultiFileExampleCompileMatchesInterp' -count=1 -v` | PASS（含 `result-try.x`、`defer-cleanup.x`） | `after/codegen-examples.log` |
| 全仓测试 | `go test ./... -count=1 -timeout 300s` | ok（全部包） | `after/go-all.log` |
| 静态检查 | `go vet ./...`；`gofmt -l .` | exit 0；无未格式化文件 | `after/vet.log`、`after/gofmt.log` |
| 确定性 | ERR-01 用例两次运行，去掉耗时字段后 diff | 归一化 diff 为空 | `after/determinism.diff`、`after/determinism.exit` |

## 四、未测项与边界（不隐瞒）

1. **interp 层非法成员访问的单元测试未入库**：`Err.value()` / `Ok.error()` 的运行期 panic 属二司 `internal/interp/**` 文件，本卡禁止跨域改文件。已用 `xnull run --interp` 探针证明 exit 134 与诊断文案（`after/illegal-*`）；**建议 CEO2-QA1 补一条 `internal/interp` 负向用例**。
2. **`E → E2` 的类/协议子类型可赋值未覆盖**：`assignableError` 当前支持同型、`Any`、`Object` 根；类继承/协议实现的可赋值依赖 TYPE-01 子类型规则（尚未实现），因此 `Result<Int, SubError>` 的 `try` 赋给 `Result<Int, BaseError>` 会保守报错。已登记为 ERR-01 边界，不阻塞本锚点（本锚点用 String/Object 验证）。
3. **无目标类型的闭包内 `try`**：仅当闭包被赋给函数类型目标时检查其函数体；`var f = () -> { ... }` 无目标类型的闭包体仍不遍历（既有边界，未扩大改动面）。
4. **类字段 `Result` 初始化式**：实现已检查（`walkClassBodies`），但未新增专项用例；正向由 `defer-cleanup.x` 双路径间接覆盖。
5. **未改**：`status.tsv`、台账状态、既有测试期望、`internal/interp/**`、`xfront/**`、`codegen/**`。

## 五、诊断码

| 码 | 含义 | 触发用例 |
|---|---|---|
| `ERR-201` | Result 作为裸表达式语句丢弃（@mustUse） | `TestERR01MustUse` |
| `ERR-202` | Result 构造/类型实参错误（Ok/Err 形参、E=void、无目标类型） | `TestERR01ResultConstructionNegative`、`TestERR01ErrorTypeVoid` |
| `ERR-203` | Result 成员误用（未知成员/arity/void/未调用） | `TestERR01ResultMembersNegative` |
| `ERR-204` | try 上下文或错误类型不合法 | `TestERR01TryNegative`、`TestERR01LambdaTry` |
| `ERR-205` | defer/errdefer 清理体限制 | `TestERR01CleanupRestrictions` |
| `ERR-206` | errdefer 不在返回 Result 的函数/闭包 | `TestERR01ErrdeferContext` |
