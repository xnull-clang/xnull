# 验收：M1-ENTRY-01（入口与启动）—— C-10 / C-13 复验

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（C-10 PASS；C-13 部分 PASS，存在声明顺序相关的编译路径缺陷）
> **复验点**：main `d620ea5`（`4a741a6`、`46f36f2` 均已并入）
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| C-10 初始化 fatal 终止（编译 + 解释） | **PASS**（6/6 用例，双路径 rc=134，入口零输出） |
| C-13 非匹配 `main` 重载（入口在前） | **PASS**（`main()` + `main(Int)` 双路径输出 `entry`） |
| C-13 非匹配 `main` 重载（重载在前） | **FAIL**（编译路径报 `重复入口 main`；解释路径正常） |
| C-13 非匹配 `main` 重载可调用（重载在前） | **FAIL**（编译路径 rc=1，`main(41)` 无法调用） |

**总判定：FAIL。** `4a741a6` 修好了 C-10 和 C-13 的“入口在前”形态，但没有消除“非匹配 `main` 声明在入口之前”时的误判：编译路径仍把后出现的入口当成重复入口，违反 §11.2“其余 `main` 重载是普通函数”及顶层函数声明顺序无关的语义。

**d620ea5 复验结论不变**：C-10 仍 6/6 PASS；C-13 顺序缺陷仍在（重载在前的编译路径 rc=1）。

---

## 二、C-10 逐项结果（PASS）

`Int a = <初始化式>` 在入口运行前除零，两条路径都必须是 fatal、exit 134、入口不得执行。

| # | 用例 | 初始化形态 | interp | compiled | 判定 |
|---:|---|---|---|---|---|
| 1 | `c3_init_fatal` | 常量 `1 / 0` | rc=134，无输出 | rc=134，无输出 | PASS |
| 2 | `c7b` | 运行期 `10 / d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 3 | `c7_runtime_divzero` | `d=0; 10/d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 4 | `c7c_runtime_divzero` | 顶层字段在入口声明之后 | rc=134，无输出 | rc=134，无输出 | PASS |
| 5 | `c7d_args_divzero` | 初始化式调用后置函数 | rc=134，无输出 | rc=134，无输出 | PASS |
| 6 | `c7e_runtime_divzero` | `s.length()-1` 得 0 | rc=134，无输出 | rc=134，无输出 | PASS |

补充探针：

| 用例 | interp | compiled | 判定 |
|---|---|---|---|
| `1 % 0` | rc=134，`xnull: fatal: 除零` | rc=134，`xnull: fatal: 除零` | PASS |
| `1 / (1 - 1)`（常量折叠） | rc=134，`xnull: fatal: 除零` | rc=134，`xnull: fatal: 除零` | PASS |

C-10 闭环：原 `c7b` 编译路径 rc=0 打印 `a=0`、`c7e` rc=255 两项均已转绿。

---

## 三、C-13 逐项结果（部分 FAIL）

### 3.1 通过面

用例 `e3_dup_overload.x`（入口在前）：

```x
static Int main() {
    print("entry")
    return 0
}
static Int main(Int x) {
    return x + 1
}
```

| 路径 | rc | stdout | 判定 |
|---|---:|---|---|
| `run --interp` | 0 | `entry` | PASS |
| `run`（编译） | 0 | `entry` | PASS |

入口在前且调用重载（`c13_entry_first_call`）：双路径均输出 `42`，PASS。

### 3.2 失败面

**F1：非匹配 `main` 声明在入口之前，编译路径误报重复入口。**

`c13_call_overload.x`：

```x
static Int main(Int x) { return x + 1 }
static Int main() {
    print(main(41))
    return 0
}
```

| 路径 | rc | stdout | stderr |
|---|---:|---|---|
| `run --interp` | 0 | `42` | — |
| `run`（编译） | 1 | — | `xnull: 代码生成失败：重复入口 main（§11.4）：一个程序只能有一个匹配签名的入口` |

同形态另两例（`c13_call_helper.x`、`c13_two_overloads.x`）编译路径同样 rc=1；解释路径分别输出 `42`、`42`/`x1`。

**F2：声明顺序影响结果，违反顶层函数顺序无关。**

仅调整两个 `main` 的声明顺序，同一程序从 PASS 变为 FAIL：

| 声明顺序 | interp | compiled |
|---|---|---|
| 入口 `main()` 在前 | rc=0 / `entry` 或 `42` | rc=0 / `entry` 或 `42` |
| 重载 `main(Int)` 在前 | rc=0 / 正常 | **rc=1 / `重复入口 main`** |

**F3：`4a741a6` 自带用例未覆盖该顺序。**

`TestEntryMainOverloadIsOrdinary` 的源码固定为“入口在前”，因此该测试在 main 上 PASS，但无法暴露 F1/F2。

### 3.3 根因定位

`impl/internal/codegen/codegen.go:255-267` 的函数签名表遍历按声明顺序执行：

```go
if seenFn[fn.Name] {
    if fn.Name == "main" && entry != nil && fn != entry.fn {
        continue
    }
    if fn.Name == "main" {
        return "", fmt.Errorf("重复入口 main（§11.4）：一个程序只能有一个匹配签名的入口")
    }
    ...
}
```

当非匹配 `main(Int)` 先出现时，`seenFn["main"]` 先被置位；随后遍历到真正的入口 `main()`，`fn == entry.fn` 使上一分支不成立，直接落到报错。该逻辑只对“入口在前”成立。

---

## 四、回归（本轮实测）

| 项 | 命令 | 结果 |
|---|---|---|
| ENTRY 相关 CLI 测试 | `go test ./internal/cli -run 'TestEntry|TestRunEntry|TestRunMain' -count=1 -v` | 18 PASS，0 FAIL |
| cli + interp 全量 | `go test ./internal/cli ./internal/interp -count=1` | 两包 ok |
| `private main`（e10） | 双路径 | `ENTRY-003`，rc=1，PASS |
| 泛型 `main`（e11） | 双路径 | `ENTRY-003`，rc=1，PASS |
| `protected main`（e12） | 双路径 | `ENTRY-003`，rc=1，PASS |
| `public main`（e13） | 双路径 | rc=3，`pub`，PASS |
| 非 void 入口缺 return（e14） | 双路径 | `DA-103`，rc=1，PASS |
| 两个匹配签名入口 | 双路径 | `ENTRY-002`，rc=1，PASS（重复入口仍拒绝） |
| 全仓测试 | `go test ./... -count=1` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与本锚点无关，需另修 golden 或回退状态。 |

---

## 五、证据

- 复验目录：`evidence/M1-ENTRY-01-reverify-d620ea5/`
  - `sha.txt`：main `d620ea5`、修复提交 `4a741a6`、二进制 sha256
  - `command.txt`：复现命令
  - `cases/`：本轮全部用例源码
  - `out/matrix.tsv`：16 个用例 × 双路径的 rc/stderr
  - `out/<case>.<mode>.{out,err}`：原始 stdout/stderr
  - `cli-entry-tests.log`：ENTRY 相关 CLI 测试 18 PASS
- 前一轮（`c5694b3`）：`evidence/M1-ENTRY-01-reverify-2026-11-07/`
- 历史用例：`wt/e5-runtime/evidence/M1-ENTRY-01-qa/cases/`
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §11.2、§11.3、§11.4

---

## 六、放行条件（复验判据）

1. F1/F2：`main(Int)` 声明在入口之前时，编译路径必须与解释路径一致（rc=0，`main(41)` 可调用）。
2. 回归：入口在前形态、C-10 六例、e10–e14 负例不得回退。
3. 建议补充 `TestEntryMainOverloadIsOrdinary` 的顺序变体（重载在前 + 调用重载），避免同类问题再次漏检。

---

## 七、未跑 / 边界

1. 工程清单指定入口文件/入口包（§11.4 清单模式）：工程配置规范未落地。
2. 非默认包 `main`：多包编译未支持（PKG-01 范围）。
3. 默认参数/可变参数入口：语法层无该构造。
4. 变异 / 覆盖率：不属本卡。
