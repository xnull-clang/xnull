# 验收（FAIL）：M1-ENTRY-01 入口与启动

> **卡片**：M1-ENTRY-01（台账 `XNull一致性用例台账-v1.0.0.md:31`）
> **被测**：`592e7f775c97419a669b69171c600f1818998f54`（父提交 `81ec33d`，已确认是 `main` 祖先）
> **角色**：CEO3-QA2-差分与变异（独立验收，不写生产代码、不改测试期望）
> **时间**：2026-11-07　**结论**：**FAIL**（不设条件通过）
> **完整报告**：`收件箱/CEO3/验收-M1-ENTRY-01.md`
> **证据目录**：`收件箱/回执箱/CEO3/evidence-M1-ENTRY-01/`（`cases/` 42 份源码、`out/` 双路径输出、`run.sh`/`run2.sh`、`cmd.txt`、`logs/probe.sh`）

---

## 一、五行结论

1. **FAIL**：4 项 §11.2 强制约束未实现或未强制，1 项初始化失败语义在编译路径不成立。
2. **回归 1 项**：`main()` + `main(Int)` 在父提交 interp 可运行（输出 `entry`），本提交报「重复入口」rc=1；违反 §11.2「其他 `main` 重载是普通函数」。
3. **初始化 fatal 不终止**：`Int a = 1/0` 时 interp rc=134 且 main 未运行，compiled **打印 `MAIN-SHOULD-NOT-RUN` 且 rc=0**（§11.3 / §10.4）。
4. **非法入口未拒绝**：`private` / `protected` / 泛型 `main<Int>()` 双路径均 rc=0 正常执行。
5. **通过面**：四形态入口、退出码映射、声明顺序初始化、缺失/同签名重复/非 static/错误返回类型/错误参数类型拒绝、`args` 语义、全量测试 9/9 包绿、示例双路径 10/10 一致。

---

## 二、已跑命令与结果

| # | 命令 | 结果 |
|---|---|---|
| 1 | `git archive 592e7f7 \| tar -x -C $T/src` + `go build -o $T/xnull ./cmd/xnull` | 构建成功；`xnull 0.1.0-dev` |
| 2 | `bash run.sh`（A 四形态 4 + B 退出码 7 + C 初始化 6 + D args 3 + E 负例 11 = 31 用例 × 2 路径） | 64 条结果见 `out/`；失败集：c2/c3/c5/c6/e3/e10/e11（详见 §三） |
| 3 | `bash run2.sh`（c7/c7b/c7c/c7d/c7e/c8/c9/c10/c11 + a5/e12/e13/e14 = 13 用例 × 2 路径） | 新增失败：c7b/c7c（编译路径不终止）、c7e（退出码 255 vs 134）、c8/c9（`str(Bool)` 分歧）、e12（protected 被接受） |
| 4 | `cd $T/src/impl && go vet ./...` | rc=0 |
| 5 | `go test ./... -count=1 -timeout 900s` | 全部 ok：interp 10.155s / cli 93.927s / codegen 112.973s / ffi 41.204s / devtool 12.261s / diag 11.189s / sema 13.748s / xfront 13.987s / xpd 14.885s |
| 6 | 示例双路径：9 个 `examples/*.x` + `examples/multi/main.x` 逐个 `--interp` vs 默认路径 | 10/10 stdout 逐字节一致、退出码均 0 |
| 7 | 父版本对照：`git archive 81ec33d` 构建后跑 e3/c2/c5/c10/c9 | e3 interp rc=0 输出 `entry`（证明 D-04 为回归）；c2/c5/c9 父提交同样有问题（证明这些非本卡引入） |

**关键实测**（原样）

```
c3  interp   rc=134  err=xnull: fatal: 除零
c3  compiled rc=0    out=MAIN-SHOULD-NOT-RUN
c7b interp   rc=134  err=xnull: fatal: 除零
c7b compiled rc=0    out=a=0
c7e interp   rc=134  err=xnull: fatal: 除零
c7e compiled rc=255  out=(空)
e3  interp   rc=1    err=xnull: 重复入口 main（§11.4）
e10 interp/compiled rc=0（private 入口被执行）
e12 interp/compiled rc=3（protected 入口被执行）
e11 interp/compiled rc=0（泛型入口被执行）
```

---

## 三、检查表（台账要点展开）

| # | 检查项 | 条款 | 结果 |
|---|---|---|:-:|
| C-01 | `void main()` 可运行，退出码 0 | §11.2 | PASS |
| C-02 | `Int main()` 返回值即退出码 | §11.2 | PASS |
| C-03 | `void main(final String[] args)` | §11.2 | PASS |
| C-04 | `Int main(final String[] args)`（2 参透传） | §11.2 | PASS |
| C-05 | `final` 可选（无 final 形态） | §11.2 | PASS |
| C-06 | 退出码 0/1/42/255 直通；256→0、300→44、-1→255 | §11.2 | PASS（双路径一致） |
| C-07 | 顶层字段按声明顺序先于入口 | §4.3/§11.3 | PASS |
| C-08 | 初始化式读未初始化字段得零值不报错 | §4.3 | **FAIL**（interp） |
| C-09 | 初始化式可调用其后声明函数 | §4.3 | **FAIL**（interp） |
| C-10 | 初始化 fatal 终止且不调用入口 | §11.3/§10.4 | **FAIL**（compiled） |
| C-11 | 缺失入口拒绝 | §11.4 | PASS |
| C-12 | 同签名重复入口拒绝 | §11.4 | PASS |
| C-13 | 非匹配 `main` 重载是普通函数 | §11.2 | **FAIL**（回归） |
| C-14 | 非 `static` 入口拒绝 | §11.2 | PASS |
| C-15 | 返回 `String`/`Bool` 拒绝 | §11.2 | PASS |
| C-16 | 参数 `Int`/`String`/双参拒绝 | §11.2 | PASS |
| C-17 | `private`/`protected` 入口拒绝 | §11.2 | **FAIL** |
| C-18 | 泛型入口拒绝 | §11.2 | **FAIL** |
| C-19 | `args` 为新数组、不含程序名 | §11.2 | PASS |
| C-20 | 非 void 入口缺 return 拒绝 | §6.1 | PASS（DA-103） |
| C-21 | 示例双路径一致 | M1 门禁 | PASS（10/10） |
| C-22 | interp/cli/codegen 全量 | 回归 | PASS（9/9 包） |

---

## 四、缺陷与归属

| # | 缺陷 | 引入 | 严重度 |
|---|---|---|---|
| D-01 | 初始化除零在编译路径不终止，入口被调用（常量折叠为 0） | **本卡新面** | P1（阻断） |
| D-02 | `private`/`protected` 入口未拒绝 | 既有，本卡校验未覆盖 | P1（阻断） |
| D-03 | 泛型入口未拒绝 | 既有，本卡校验未覆盖 | P1（阻断） |
| D-04 | 非匹配 `main` 重载误判重复入口；相对父提交回归 | **本卡引入** | P1（阻断） |
| D-05 | interp 初始化前向引用/调用函数报「未定义」；双路径分歧 | 既有（父提交同） | P1（归属待裁） |
| D-06 | fatal 退出码双路径 134 vs 255 | 本卡新面（编译侧） | P2 |
| D-07 | `str(Bool)` 输出 `true` vs `1` | 既有（BLD-01 相邻） | P2 |

---

## 五、未跑清单

| 项 | 原因 |
|---|---|
| 工程清单指定入口文件/入口包（§11.4 清单模式） | 工程配置规范未落地，`xnull.project` 解析不在本卡 |
| 非默认包 `main` 不作为入口 | 多包编译未支持（PKG-01 范围） |
| 默认参数/可变参数入口 | 语法层无该构造（`Param` 无默认/可变字段） |
| `args` 修改不影响进程原始参数 | 入口后不可观测，无黑盒判据 |
| 跨文件重复入口 | 跨包 import 不支持；单文件重复已覆盖 |
| 单例/静态字段初始化顺序 | 属 S2，不在 ENTRY-01 |
| 顶层字段 `deinit`/全局析构 | §11.3 明确不保证 |
| 变异分数 / 差分框架化 | 属三司测试基建（G-01/G-02），本卡未要求 |

---

## 六、放行条件（复验判据）

1. D-01：`Int a = 1/0`（常量与运行期两形态）编译路径必须终止，main 零输出。
2. D-02/D-03：`private`/`protected`/泛型入口双路径非 0，诊断点名 §11.2。
3. D-04：`main()` + `main(Int)` 不得报「重复入口」；入口取匹配签名，其余为普通函数。
4. D-05：明确归属（ENTRY-01 或移交锚点），避免「初始化顺序」口径悬空。
5. 复验须从干净归档副本重跑 §二 全部命令，附 commit sha。

D-06/D-07 不阻断本卡，需登记并在对应锚点闭环。

---

## 七、证据路径

- 本目录：`收件箱/回执箱/CEO3/evidence-M1-ENTRY-01/`
  - `cases/`：42 份独立用例源码
  - `out/`：双路径 stdout/stderr/退出码
  - `run.sh` / `run2.sh`：可复跑脚本（`XNULL_RUNTIME` 指向归档副本）
  - `cmd.txt`：本轮全部命令
- 完整报告：`收件箱/CEO3/验收-M1-ENTRY-01.md`
- 被测源码 sha256：`codegen.go 0c3c716f…`、`interp.go b0624497…`
