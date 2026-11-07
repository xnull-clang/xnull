# INTEG-c3-rd1 集成复核证据摘要

> **只读复核**　**main = `9f5f66c`**　**pod/c3-rd1 = `7c626b5`**　**日期：2026-11-07**
> 结论：**FAIL**（集成门禁全绿；ENTRY-01 初始化顺序在解释路径失败）
> 回执：`收件箱/回执箱/CEO3/验收-INTEG-c3-rd1.md`

---

## 一、门禁结果

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `git merge-base --is-ancestor 7c626b5 9f5f66c` | **exit 0**（是祖先） | `ancestry.txt` |
| 2 | `cd impl && go vet ./...` | **exit 0**，无输出 | `vet.txt` |
| 3 | `cd impl && go test ./... -count=1 -timeout 300s` | **exit 0**，全部包 ok（2 个命令包 no test files），无 FAIL | `gotest.txt` |
| 4 | `bash impl/runtime/build_rt.sh` | **exit 0**，policy/rt/gc/hard/abi/std/资源表全过 | `build_rt.txt` |
| 5 | ENTRY-01 定向测试 | cli 9 项、interp 5 项全 PASS | `entry-cli-tests.txt`、`entry-interp-tests.txt` |

`go test` 耗时（节选）：cli 70.2s、codegen 101.8s、codegen/ffi 39.8s、interp 7.5s；均未触发 300s 超时。

---

## 二、ENTRY-01 CLI 独立用例

二进制：`/tmp/xnull-integ`（由 main 构建）。逐例原始输出在 `cli-runs/<case>/`。

| 用例 | 命令模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| `void main(String[] args)` | compiled | exit 0，`void:2` | exit 0，`void:2` | PASS |
| `void main(String[] args)` | `--interp` | exit 0，`void:2` | exit 0，`void:2` | PASS |
| `Int main(String[] args)` | compiled | exit 7，`int:2` | exit 7，`int:2` | PASS |
| `Int main(String[] args)` | `--interp` | exit 7，`int:2` | exit 7，`int:2` | PASS |
| `void main()` | compiled | exit 0 | exit 0，`void-noargs` | PASS（实现额外接受） |
| `Int main()` | compiled | exit 5 | exit 5，`int-noargs` | PASS（实现额外接受） |
| `return 300` | compiled | 平台截断 44 | exit 44 | PASS |
| `return -1` | compiled | 255 | exit 255 | PASS |
| 顶层字段声明序 | compiled | `a\nb\nmain` | `a\nb\nmain` | PASS |
| 顶层字段声明序 | `--interp` | `a\nb\nmain` | `a\nb\nmain` | PASS |
| 初始化期 fatal | compiled | exit 134，main 不执行 | exit 134，stdout 空 | PASS |
| 初始化期 fatal | `--interp` | exit 134，main 不执行 | exit 134，`fatal: init-boom` | PASS |
| 缺失入口 | compiled | exit 1，`ENTRY-001` | exit 1，`ENTRY-001` | PASS |
| 重复入口 | compiled | exit 1，`ENTRY-002` | exit 1，`ENTRY-002` | PASS |
| 额外参数 | compiled | exit 1，`ENTRY-003` | exit 1，`ENTRY-003` | PASS |
| 返回 String | compiled | exit 1，`ENTRY-003` | exit 1，`ENTRY-003` | PASS |
| 参数 Int[] | compiled | exit 1，`ENTRY-003` | exit 1，`ENTRY-003` | PASS |
| 非 static | compiled | exit 1 | exit 1，提示必须 static | PASS |
| explicit `public` | compiled | exit 0 | exit 0，`public-ok` | PASS |
| explicit `private` | compiled | exit 1，`ENTRY-003` | exit 1，必须是公开的 | PASS |
| args 透传（不含程序名） | compiled | `2\nalpha\nbeta` | 同左 | PASS |
| `--` 后参数透传 | `--interp` | `2\n--verbose\nx` | 同左 | PASS |

---

## 三、失败项

### F1（ENTRY-01 初始化顺序）：前向引用初始化，compiled 与 `--interp` 不一致

用例 `cases/init_forward.x`（符合 S1 §4.3：初始化式读未初始化字段应读零值、不报错）：

```x
Int a = b + 1
Int b = 2
static Int main() {
    print(str(a))
    print(str(b))
    return 0
}
```

| 路径 | 命令 | 退出码 | stdout | stderr |
|---|---|---:|---|---|
| compiled | `/tmp/xnull-integ run cases/init_forward.x` | **0** | `1\n2\n` | 空 |
| interp | `/tmp/xnull-integ run --interp cases/init_forward.x` | **1** | 空 | `xnull: 未定义的名称：b` |

原始文件：`cli-runs/init_forward_comp/{stdout.txt,stderr.txt,exit_code.txt}`、`cli-runs/init_forward_interp/{stdout.txt,stderr.txt,exit_code.txt}`。

期望依据：S1 §3「包内声明顺序不影响可见性；顶层字段可以相互前向引用」、§4.3「所有顶层字段先置零值；初始化式读取尚未初始化的字段时，读到零值，不报错」。compiled 路径符合，interp 路径不符合。

### F1 是否由 c3-rd1 引入：**否**

- c3-rd1 合入 main 的实际代码差异（`git diff 6f77167..f20081b -- impl`）只有 `impl/internal/cli/cli.go`、`impl/internal/cli/cli_test.go`，**未改 interp**（`integration-diff.txt`）。
- 在合并前 `6f77167` 的仓外 clone 复跑同一用例：interp 同样 `exit 1 / 未定义的名称：b`，compiled 同样 `exit 0 / 1\n2`（`premerge-6f77167-*.{out,err,exit}`）。
- 结论：**缺陷为 main 既有问题，c3-rd1 未引入、也未修复。**

### F2（覆盖缺口）：现有测试未覆盖前向引用初始化

`go test ./...` 全绿，但 `TestTopFieldInitOrder`/`TestRunEntryInitOrder`/`TestInitOrderViaCLI` 只测「按声明顺序、后项依赖前项」；没有「前项读后项零值」用例，因此全绿不能证明 §4.3 完整达成。

---

## 四、未跑清单

1. 多文件/包级初始化顺序（§4.3 文件顺序：清单顺序或路径字典序）——单文件 CLI 路径未覆盖。
2. 工程清单模式入口解析（§11.4 `xnull.project` 指定入口文件/入口包）。
3. 其他包中的 `main` 不得作为入口（需工程清单/多包布局）。
4. 泛型 `main`、默认参数/可变参数 `main` 的负例（代码有检查，未逐条跑）。
5. 编译路径的初始化期 panic 栈/诊断质量（只验证了退出码与 main 未执行）。
6. L2/L3 门禁与公开副本同步。

---

## 五、结论与回退建议

- **结论：FAIL**（唯一失败点 F1；其余 ENTRY-01 CLI、两种签名、退出码、声明序初始化、缺失/重复入口全部 PASS）。
- **不建议回退 c3-rd1**：合并只改 `cli.go`/`cli_test.go`，未引入 F1；回退不会修复 F1，反而丢失 ENTRY-01 CLI 改进。
- **建议**：保留 `9f5f66c` 集成；另开 P1 卡修 `impl/internal/interp` 的顶层字段预声明/零值初始化（先声明全部顶层字段为零值，再按序求值），并补「前向引用读零值」双路径用例。修复合入后用新 sha 重验 F1。
