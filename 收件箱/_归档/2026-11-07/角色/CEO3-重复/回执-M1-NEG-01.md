# 回执 · M1-NEG-01

> **锚点：NEG-01**　**主责：CEO3-RD3-测试基建**　**分支：`pod/c3-rd3`**　**被测 commit：见 `evidence/M1-NEG-01/sha.txt`（merge main@2c00cf5 → `2ac4b1cb4f18d0df2a00ad4137f3813d544e5de3`）**
> **时间：2026-11-07 03:5x（T+0:2x）**　**性质：执行侧回执，不是 L1 签字**

## 状态：BLOCKED

**merge main@2c00cf5 后复跑：50/60；剩 10 项，根因全在 `xfront`/`sema`，仍无人认领。**

| 需要支援的域 | 剩余用例 | 需要做的事 | 归口 |
|---|---:|---|---|
| `impl/internal/sema/**` | 9 | §1.3 标识符/类型名合法性：`async/await/yield/unsafe/extern/macro` 不得作标识符（`xfront.Reserved` 已定义、无消费者）；`true/false/null` 不得作声明名；`Array` 不得作类型名；类型名必须可解析（`type Foo = Int` 现被当顶层字段静默收下） | 一司 CEO1-RD2 |
| `impl/internal/xfront/**` | 1 | §3.2 包别名：`import P as Q` 在单文件路径也必须拒绝（PKG-01 的 RES-107 只在多文件导入分析里，单文件 `sema.Analyze` 仍 0 诊断） | 一司 CEO1-RD1 |

本轮变化（merge `main@2c00cf5`，含 ERR-01/DET/TYPE-01/GEN-01-interp）：

| 时点 | 分支/提交 | PASS/60 | 变化 |
|---|---|---:|---|
| 红件首交 | `pod/c3-rd3@4cc813b` | 47 | — |
| 跨分支复核 | `pod/c1-rd2@1562da0` | 50 | +3：`neg-10.4-01/02/03`（defer 体限制） |
| **本次（已合入）** | `pod/c3-rd3@2ac4b1c` | **50** | defer 3 项转绿；TYPE-01 可选提升修复（P0 附加发现已关闭） |
| 剩余 | — | **10** | sema 9 + xfront 1，均无在途分支覆盖 |

> 其余全绿：`go vet ./...`=0；`go test ./...` 唯一失败包 = `Tests`（本锚点红项）；9 示例 + multi 双路径 10/10 MATCH。
> 派单后对方改完，我 5 分钟内复跑出绿；测试与期望值自 `4cc813b` 起未改动。

**五行**

1. **完成**：NEG-01 检查表 60 项 + 32 组矩阵已建（台账要点逐项：S1 §0.6 三十行 / §1.3 / §3.2 / §10.4 / §2.11 / §6.1），表驱动测试 `impl/Tests/neg_test.go` 已落，含 `TestDiagMatrixS1`（负例 60 子测试）与 `TestDiagMatrixS1Alternatives`（替代方案正例 9 条）。
2. **完成**：红件早于 T+1 留证（`before/`，47/60）；merge `main@2c00cf5` 后复跑 **50/60**（`after-merge/`），defer 三项转绿，剩余 **10 项**。
3. **阻塞（BLOCKED）**：10 项红的根因全部在 `impl/internal/xfront/**`、`impl/internal/sema/**`（一司域），按卡面「不许跨域改文件」停手。
4. **请求**：CEO2 按 v1.7.1 §4.3 立即派单——**sema 侧 9 项**（保留名×6、字面量名、`Array` 类型名、未知类型名）归 CEO1-RD2；**xfront 侧 1 项**（包别名，单文件路径）归 CEO1-RD1；合计约 1.7h。
5. **P0 附加发现已关闭**：初始化式可选提升（`String? s = "x"`）已在 `main@2c00cf5` 修复（实测 exit 0、0 诊断）。

> **命令口径**：《M1 整改台账》§三 N3 写作 `go test ./internal/... -run TestDiagMatrixS1`；本锚点载体按台账表头「用例文件（相对 `impl/Tests/`）」落在 `impl/Tests/`，等价命令为 `go test ./Tests/ -run '^TestDiagMatrixS1$'`。`./internal/...` 下无该测试（未越域新建包）。

---

## 交付物

| 项 | 路径 | 结果 |
|---|---|---|
| 负例测试 | `impl/Tests/neg_test.go` | 60 子测试（表驱动）+ 9 正例 |
| 检查表 | `evidence/M1-NEG-01/checklist.md` | 60 项逐条 + N1–N5 对照 + 根因表 |
| 32 组矩阵 | `evidence/M1-NEG-01/diag-matrix.tsv` | 列：item/group/cases/code/line/col/status |
| 红输出 | `evidence/M1-NEG-01/before/go-test-diagnatrix-s1.out` | exit 1，47/60 |
| 正例对照 | `evidence/M1-NEG-01/results/go-test-alternatives.out` | exit 0，9/9 |
| 双路径 | `evidence/M1-NEG-01/results/dualpath/result.txt` | 10/10 MATCH（9 示例 + multi） |
| 七件套 | `evidence/M1-NEG-01/` | command/stdout/stderr/exit_code/sha/artifact.sha256/acceptance |

---

## 逐项打勾（60 项）

状态取自 `go test ./Tests/ -run '^TestDiagMatrixS1$' -v`。

### §0.6 不支持语法（43 项）

| # | 用例 | 项 | 勾 |
|---|---|---|---|
| 1 | neg-0.6-01 | 命名实参 | ✅ |
| 2 | neg-0.6-02 | 默认参数 | ✅ |
| 3 | neg-0.6-03 | 可变参数 | ✅ |
| 4 | neg-0.6-04 | 展开实参 | ✅ |
| 5 | neg-0.6-05 | C 风格 for | ✅ |
| 6 | neg-0.6-06 | catch | ✅ |
| 7 | neg-0.6-07 | finally | ✅ |
| 8 | neg-0.6-08 | 运算符重载 | ✅ |
| 9 | neg-0.6-09 | 指针类型 `T*` | ✅ |
| 10 | neg-0.6-10 | 地址符 `&` | ✅ |
| 11 | neg-0.6-11 | `@arc` 注解 | ✅ |
| 12 | neg-0.6-12 | `@gc` 注解 | ✅ |
| 13 | neg-0.6-13 | 自定义访问器 | ✅ |
| 14 | neg-0.6-14 | 用户定义索引器 | ✅ |
| 15 | neg-0.6-15 | if 表达式 | ✅ |
| 16 | neg-0.6-16 | 块表达式 | ✅ |
| 17 | neg-0.6-17 | 独立 `{}` 语句块 | ✅ |
| 18 | neg-0.6-18 | match | ✅ |
| 19 | neg-0.6-19 | 元组解构 | ✅ |
| 20 | neg-0.6-20 | `??=` | ✅ |
| 21 | neg-0.6-21 | `?.()` | ✅ |
| 22 | neg-0.6-22 | 函数类型箭头 | ✅ |
| 23 | neg-0.6-23 | async 函数 | ✅ |
| 24 | neg-0.6-24 | await | ✅ |
| 25 | neg-0.6-25 | yield | ✅ |
| 26 | neg-0.6-26 | unsafe 块 | ✅ |
| 27 | neg-0.6-27 | macro | ✅ |
| 28 | neg-0.6-28 | 显式 export 列表 | ✅ |
| 29 | neg-0.6-29 | 嵌套类型 | ✅ |
| 30 | neg-0.6-30 | 静态初始化块 | ✅ |
| 31 | neg-0.6-31 | 多继承 | ✅ |
| 32 | neg-0.6-32 | 类方法覆写（TY-203） | ✅ |
| 33 | neg-0.6-33 | 抽象方法 | ✅ |
| 34 | neg-0.6-34 | 单例实现协议（SYN-110） | ✅ |
| 35 | neg-0.6-35 | 结构体实例引用字段（TY-204） | ✅ |
| 36 | neg-0.6-36 | 协议字段 | ✅ |
| 37 | neg-0.6-37 | 协议方法体 | ✅ |
| 38 | neg-0.6-38 | 泛型协议 | ✅ |
| 39 | neg-0.6-39 | 泛型约束 `where` | ✅ |
| 40 | neg-0.6-40 | 包级私有 `internal` | ✅ |
| 41 | neg-0.6-41 | **类型别名 `type Foo = Int`** | ❌ |
| 42 | neg-0.6-42 | 隐式数值提升 | ✅ |
| 43 | neg-0.6-43 | Bool 与整数互转 | ✅ |

### §1.3 标识符与类型名（9 项）

| # | 用例 | 项 | 勾 |
|---|---|---|---|
| 44 | neg-1.3-01 | **保留名 `async`** | ❌ |
| 45 | neg-1.3-02 | **保留名 `await`** | ❌ |
| 46 | neg-1.3-03 | **保留名 `yield`** | ❌ |
| 47 | neg-1.3-04 | **保留名 `unsafe`** | ❌ |
| 48 | neg-1.3-05 | **保留名 `extern`** | ❌ |
| 49 | neg-1.3-06 | **保留名 `macro`** | ❌ |
| 50 | neg-1.3-07 | 预定义类型名遮蔽（RES-102） | ✅ |
| 51 | neg-1.3-08 | **`Array` 作类型名** | ❌ |
| 52 | neg-1.3-09 | **`true` 作声明名** | ❌ |

### §3.2 导入（2 项）

| # | 用例 | 项 | 勾 |
|---|---|---|---|
| 53 | neg-3.2-01 | 通配符导入 | ✅ |
| 54 | neg-3.2-02 | **包别名 `import P as Q`** | ❌ |

### §10.4 defer 清理体（3 项）

| # | 用例 | 项 | 勾 |
|---|---|---|---|
| 55 | neg-10.4-01 | defer 内 return | ✅ |
| 56 | neg-10.4-02 | defer 内 try | ✅ |
| 57 | neg-10.4-03 | defer 内 throw | ✅ |

### §2.11 / §6.1（3 项）

| # | 用例 | 项 | 勾 |
|---|---|---|---|
| 58 | neg-2.11-01 | 单元素元组 | ✅ |
| 59 | neg-2.11-02 | 零元元组 | ✅ |
| 60 | neg-6-01 | `i++` 作表达式 | ✅ |

**合计：50/60 勾；10 项待跨域修复。**

---

## 32 组矩阵（`diag-matrix.tsv`）

| 结果 | 组数 | 说明 |
|---|---:|---|
| PASS | 29 | 诊断码 + line/col 齐全 |
| FAIL | 1 | 第 30 组「类型别名 / newtype」（`neg-0.6-41`，0 诊断） |
| N-A | 2 | 第 8 组「事件」、第 18 组「条件编译/反射」——规范未给语法，无法写负例，不冒充绿 |

> 注：13 条 FAIL 用例分布在 6 个根因上；矩阵 32 组按台账分组，组内多用例时以首条为码/位样本。

---

## 剩余 10 项红的根因与派单建议

| 归类 | 用例 | 根因位置（只读定位，未改） | 归口 | 估时 |
|---|---|---|---:|---:|
| 保留名 6 项 | neg-1.3-01…06 | `impl/internal/xfront/token.go:122-126` 的 `Reserved` 无消费者（`grep -rn "xfront.Reserved" impl/internal/sema` = 0）；sema 声明注册处（`sema.go` 局部/参数/顶层）无名称合法性检查 | CEO1-RD2 | 0.5h |
| 字面量名 1 项 | neg-1.3-09 | 同上（`true/false/null` 非关键字，词法按标识符返回） | CEO1-RD2 | 0.2h |
| `Array` 类型名 1 项 | neg-1.3-08 | 类型名黑名单未含 `Array`（`impl/internal/sema/typedecl.go`） | CEO1-RD2 | 0.2h |
| 未知类型名 1 项 | neg-0.6-41 | sema 不校验类型名可解析性；`type Foo = Int` 被当作顶层字段静默收下 | CEO1-RD2 | 0.5h |
| 包别名 1 项 | neg-3.2-02 | `impl/internal/xfront/unit.go` 的 `parseImportDecl`：任意路径后接 `as` 均接受；§3.2 要求别名仅用于符号导入（路径 ≥2 段） | CEO1-RD1 | 0.3h |

> 合计约 1.7h；均为 sema/xfront 局部检查。修完我 5 分钟内复跑出绿并交 L1。
> 已转绿：`neg-10.4-01/02/03`（defer 清理体禁止 return/try/throw，ERR-01 落地）。

## 未测项

1. 不崩溃只在解析+语义层验证（`recover()`），未做 CLI 子进程级 panic 检测。
2. 导入类用例只看「是否被拒绝」，未验跨文件 `LoadUnits`；`import P.S as A` 合法场景属 PKG-01。
3. §0.6 无语法载体的 2 组（事件、条件编译/反射）按 N-A 处理，未计入绿。
4. S2 深层语义只判「被拒绝」，未逐码核对（归属 S2 锚点）。
5. 变异 / 10 次连续跑不属 NEG-01 判据（属 DET-01 / G-05）。

## 附加发现

1. ~~初始化式不做可选提升（TYPE-01 假绿）~~ —— **已在 `main@2c00cf5` 修复**，实测 `String? s = "x"` 0 诊断 exit 0。
2. `static Int f(Bogus b)`：sema 0 诊断；codegen 才报 `类型 Bogus 未支持（M4.1 范围）`，无位置、无诊断码。
3. `Int true = 1` 声明被静默丢弃（`print(true)` 输出字面量 `true`）。

## 自查

- 只写 `impl/Tests/neg_test.go`、`evidence/M1-NEG-01/**`、本文件；未改生产代码、未改既有测试与期望、未删测试、未手改台账状态。
- 未 push、未合并 `main`、未碰他人文件。
- 七件套：`command.txt` / `stdout.txt` / `stderr.txt` / `exit_code.txt` / `sha.txt` / `artifact.sha256` / `acceptance.md`。
