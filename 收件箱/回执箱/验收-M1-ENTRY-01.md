# 验收：M1-ENTRY-01（入口与启动）—— C-10 / C-13 复验

> **验收人**：QA1（独立质量线）
> **结论：PASS**（C-10 6/6；C-13 重载在前已修复）
> **复验点**：main `91c89c0`（`bf03f5f` 已并入）
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| C-10 初始化 fatal 终止（编译 + 解释） | **PASS 6/6**：双路径 `rc=134`，入口零输出 |
| C-13 非匹配 `main` 重载（入口在前） | **PASS**：`main()` + `main(Int)` 双路径输出 `entry` |
| C-13 非匹配 `main` 重载（**重载在前**） | **PASS**：双路径 `rc=0`，`main(41)` 输出 `42` |
| C-13 从其他函数调用重载（重载在前） | **PASS**：双路径 `rc=0`，输出 `42` |
| 回归：e10/e11/e12 负例、e13/e14、重复入口 | **PASS** |

**判定：PASS。** `bf03f5f` 消除了声明顺序依赖：非匹配 `main` 无论声明在入口之前还是之后，都分配独立 C 名，不再误报 `重复入口 main`。

---

## 二、C-10 逐项（PASS）

| # | 用例 | 初始化形态 | interp | compiled | 判定 |
|---:|---|---|---|---|---|
| 1 | `c3_init_fatal` | 常量 `1 / 0` | rc=134，无输出 | rc=134，无输出 | PASS |
| 2 | `c7b` | 运行期 `10 / d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 3 | `c7_runtime_divzero` | `d=0; 10/d` | rc=134，无输出 | rc=134，无输出 | PASS |
| 4 | `c7c_runtime_divzero` | 顶层字段在入口声明之后 | rc=134，无输出 | rc=134，无输出 | PASS |
| 5 | `c7d_args_divzero` | 初始化式调用后置函数 | rc=134，无输出 | rc=134，无输出 | PASS |
| 6 | `c7e_runtime_divzero` | `s.length()-1` 得 0 | rc=134，无输出 | rc=134，无输出 | PASS |

stderr 均为 `xnull: fatal: 除零`。

---

## 三、C-13 逐项（PASS）

### 3.1 入口在前

`e3_dup_overload.x`：`main()` 在前、`main(Int)` 在后。

| 路径 | rc | stdout | 判定 |
|---|---:|---|---|
| `run --interp` | 0 | `entry` | PASS |
| `run`（编译） | 0 | `entry` | PASS |

### 3.2 重载在前（本轮修复点）

`c13_call_overload.x`：

```x
static Int main(Int x) { return x + 1 }
static Int main() {
    print(main(41))
    return 0
}
```

| 路径 | rc | stdout | 判定 |
|---|---:|---|---|
| `run --interp` | 0 | `42` | PASS |
| `run`（编译） | 0 | `42` | PASS |

同形态 `c13_call_helper.x`（从另一个函数调用重载）：双路径均 `42`，PASS。  
`c13_entry_first_call.x`（入口在前并调用重载）：双路径均 `42`，PASS。

### 3.3 负例回归

| 用例 | 双路径实测 | 判定 |
|---|---|---|
| `e10_private_main` | `ENTRY-003`，rc=1 | PASS |
| `e11_generic_main` | `ENTRY-003`，rc=1 | PASS |
| `e12_protected_main` | `ENTRY-003`，rc=1 | PASS |
| `e13_public_main` | rc=3，`pub` | PASS |
| `e14_int_args_noreturn` | `DA-103`，rc=1 | PASS |
| 两个匹配签名入口 | `ENTRY-002`，rc=1 | PASS |

---

## 四、边界（不阻断本条）

1. **同参数个数的多个非匹配重载**：`main(Int)` + `main(String)` 同时存在时，编译路径按参数个数分派会选错 C 名，C 编译报类型不匹配。该能力属 §4.4/§8.2 一般重载（M4.5+），不在 C-13“重载在前”本条；本轮已记录，未计入 PASS 依据。
2. 工程清单指定入口文件/入口包（§11.4 清单模式）：工程配置规范未落地。
3. 非默认包 `main`：多包编译未支持（PKG-01 范围）。
4. 默认参数/可变参数入口：语法层无该构造。

---

## 五、回归

| 项 | 命令 | 结果 |
|---|---|---|
| C-10/C-13 新增用例 | `go test ./internal/cli -run 'TestEntryMainOverloadIsOrdinary|TestEntryInitDivZeroFatal' -count=1 -v` | `TestEntryMainOverloadIsOrdinary`（入口在前/重载在前）与 `TestEntryInitDivZeroFatal`（常量/运行期）全 PASS |
| `go vet ./...` | — | exit 0 |
| `go test ./...` | — | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与本锚点无关。 |

---

## 六、证据

- 复验目录：`evidence/M1-ENTRY-01-reverify-91c89c0/`
  - `sha.txt`：main `91c89c0`、`bf03f5f`、二进制工具链
  - `command.txt`
  - `cases/`、`cases.txt`：16 例源码
  - `out/matrix.tsv`：逐例双路径 rc/stdout/stderr
  - `out/<case>.<mode>.{out,err}`
  - `cli-entry-tests.log`：新增 Go 用例
  - `full-test.log`
- 前一轮（`d620ea5`，FAIL）：`evidence/M1-ENTRY-01-reverify-d620ea5/`
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §11.2、§11.3、§11.4
