# 验收回执：INTEG-c3-rd1（集成复核 P1）

> **复核人：CEO3-QA1**　**时间：2026-11-07**　**性质：只读集成复核，未改代码/测试**
> **main：`9f5f66c`（初检）→ `f63fcba`（最终复核）**　**pod/c3-rd1：`7c626b5`**
> **结论：PASS（最终 @ `f63fcba`）；初检 @ `9f5f66c` 为 FAIL，历史见文末追加节**
> 证据：`evidence/INTEG-c3-rd1/`、`evidence/INTEG-final-c3rd1/`

---

## 一、结论

**FAIL。** 集成门禁 4/4 全绿；ENTRY-01 的 CLI、两种 `main` 签名、退出码、声明序初始化、缺失/重复入口全部 PASS；**但 §4.3 的「前向引用初始化读零值」在解释路径失败，compiled 与 `--interp` 结果不一致**。

| 门禁 | 结果 |
|---|---|
| `git merge-base --is-ancestor 7c626b5 9f5f66c` | **exit 0**（是祖先） |
| `cd impl && go vet ./...` | **exit 0** |
| `cd impl && go test ./... -count=1 -timeout 300s` | **exit 0**，全部包 ok，无 FAIL |
| `bash impl/runtime/build_rt.sh` | **exit 0** |

---

## 二、失败命令与原始输出

用例：`evidence/INTEG-c3-rd1/cases/init_forward.x`

```x
Int a = b + 1
Int b = 2
static Int main() {
    print(str(a))
    print(str(b))
    return 0
}
```

**compiled 路径（通过）**

```bash
/tmp/xnull-integ run evidence/INTEG-c3-rd1/cases/init_forward.x
# exit 0
# stdout: 1\n2
# stderr: (空)
```

**解释路径（失败）**

```bash
/tmp/xnull-integ run --interp evidence/INTEG-c3-rd1/cases/init_forward.x
# exit 1
# stdout: (空)
# stderr: xnull: 未定义的名称：b
```

原始证据：
- `evidence/INTEG-c3-rd1/cli-runs/init_forward_comp/{stdout.txt,stderr.txt,exit_code.txt}`
- `evidence/INTEG-c3-rd1/cli-runs/init_forward_interp/{stdout.txt,stderr.txt,exit_code.txt}`

期望依据：S1 §3（顶层字段可前向引用）、§4.3（所有顶层字段先置零值；初始化式读未初始化字段读零值，不报错）。compiled 路径符合，interp 路径不符合。

**覆盖缺口**：`go test ./...` 虽全绿，但现有 `TestTopFieldInitOrder` / `TestRunEntryInitOrder` / `TestInitOrderViaCLI` 只测「按声明顺序、后项依赖前项」，未覆盖「前项读后项零值」，因此全绿不等于 §4.3 完整达成。

---

## 三、是否建议回退

**不建议回退 c3-rd1。**

- c3-rd1 合入 main 的实际代码差异只有 `impl/internal/cli/cli.go` 与 `impl/internal/cli/cli_test.go`（`evidence/INTEG-c3-rd1/integration-diff.txt`），**未改 interp**。
- 在合并前 `6f77167` 的仓外 clone 复跑同一用例，结果相同：interp `exit 1 / 未定义的名称：b`，compiled `exit 0 / 1\n2`（`premerge-6f77167-*.{out,err,exit}`）。**缺陷是 main 既有问题，不是 c3-rd1 引入。**
- 回退不会修复 F1，只会丢失 ENTRY-01 CLI 改进。建议保留 `9f5f66c` 集成，另开 P1 卡修 `impl/internal/interp` 顶层字段预声明/零值初始化，并补双路径用例；修复合入后用新 sha 重验 F1。

---

## 四、已跑与判定（ENTRY-01 摘要）

- 两种签名：`void main(String[] args)`、`Int main(String[] args)`，compiled 与 `--interp` 均 PASS；`void main()`、`Int main()` 亦被接受（实现额外支持）。
- 退出码：`Int main` 返回 7 → 7；`void` → 0；`300` → 44（平台截断）；`-1` → 255；初始化期 fatal → 134 且 main 未执行。
- 初始化顺序：声明序 `a → b → main`，compiled 与 `--interp` 均 PASS；三次复跑输出 sha256 一致。
- 入口校验：缺失 `ENTRY-001`、重复 `ENTRY-002`、非法签名 `ENTRY-003`（额外参数/返回 String/参数 Int[]）、非 static、private 均被拒绝；`public` 可用。
- args 透传：不含程序名；`--` 之后参数原样透传；compiled 与 `--interp` 一致。

---

## 五、未跑清单

1. 多文件/包级初始化顺序（清单顺序或路径字典序）。
2. 工程清单模式入口解析（`xnull.project` 指定入口文件/入口包）。
3. 其他包的 `main` 不得作为入口（需多包布局）。
4. 泛型/默认参数/可变参数 `main` 的完整负例。
5. 初始化期 panic 的栈与诊断质量（仅验证退出码与 main 未执行）。
6. L2/L3 门禁与公开副本同步。

---

## 六、证据路径

`evidence/INTEG-c3-rd1/`

- `ancestry.txt`、`sha.txt`
- `vet.txt`、`gotest.txt`、`build_rt.txt`
- `entry-cli-tests.txt`、`entry-interp-tests.txt`
- `cases/*.x`、`cli-runs/<case>/{command,stdout,stderr,exit_code}.txt`
- `premerge-6f77167-*.{out,err,exit}`
- `integration-diff.txt`
- `summary.md`、`command.txt`

```
结论：FAIL
main：9f5f66c
pod/c3-rd1：7c626b5（是 9f5f66c 的祖先）
失败：ENTRY-01 前向引用初始化，interp 路径 exit 1 / 未定义的名称：b；compiled exit 0 / 1\n2
回退建议：不回退 c3-rd1；另开 P1 修 interp
签名 / 时间：CEO3-QA1 / 2026-11-07
```

---

## 七、最终复核追加（main = `f63fcba`）

> **时间：2026-11-07**　**方式：`git archive f63fcba` 干净树（无 `.git`）**　**结论：PASS**
> 证据：`evidence/INTEG-final-c3rd1/`

### 7.1 门禁

| 项 | 结果 |
|---|---|
| 干净树 `git archive f63fcba` | 成功；`has_git=no`；archive sha256 `360ae782…6114d94` |
| `git merge-base --is-ancestor 7c626b5 f63fcba` | **exit 0** |
| `go test ./internal/interp/ ./internal/cli/ -count=1` | **exit 0**：interp 2.036s、cli 11.166s |

### 7.2 P1-INIT-FWD（关闭）

用例 `Int a = b + 1; Int b = 2`：

| 路径 | 退出码 | stdout | stderr |
|---|---:|---|---|
| compiled | **0** | `1\n2\n`（4 字节） | 空 |
| `--interp` | **0** | `1\n2\n`（4 字节） | 空 |

`cmp` 逐字节一致；`od` 均为 `31 0a 32 0a`。上一轮 F1 已修复。

### 7.3 ENTRY-01 回归

| 用例 | 实测 |
|---|---|
| `void main(String[] args)` compiled / `--interp` | 0，`void:2` |
| `Int main(String[] args)` compiled / `--interp` | 7，`int:2` |
| `Int main()` | 5 |
| `return 300` / `return -1` | 44 / 255（平台截断） |
| 顶层字段声明序 compiled / `--interp` | `a\nb\nmain` |
| 初始化期 fatal | 134，main 不执行 |
| 缺失 / 重复入口 | 1，`ENTRY-001` / `ENTRY-002` |
| `--` 参数透传 | `2\n--verbose\nx` |
| `public` / `private` | 0 / 1（`ENTRY-003`） |

逐例原始输出：`evidence/INTEG-final-c3rd1/entry/<case>/`。

### 7.4 未跑

全仓 `go test ./...`、`go vet ./...`、`build_rt.sh`（本轮未要求）；多文件/工程清单入口；泛型/默认参数/可变参数 `main` 负例；L2/L3。

### 7.5 结论

**PASS。** 干净树 `f63fcba` 上 P1-INIT-FWD 双路径一致、ENTRY-01 签名与退出码回归通过、interp/cli 包测试全绿。**P1-INIT-FWD 可关闭；无回退建议。**

```
最终结论：PASS
main：f63fcba
干净树：git archive f63fcba（无 .git）
P1-INIT-FWD：compiled / --interp 均 1\n2，exit 0
ENTRY-01：两种签名/退出码/声明序初始化/入口拒绝 全部通过
包测试：interp + cli exit 0
签名 / 时间：CEO3-QA1 / 2026-11-07
```
