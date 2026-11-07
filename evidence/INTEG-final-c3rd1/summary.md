# INTEG-final-c3rd1 最终复核摘要

> **只读复核**　**main = `f63fcba`**　**c3-rd1 = `7c626b5`**
> **干净树：`git archive f63fcba`**（无 `.git`；archive sha256 `360ae782…6114d94`）
> **结论：PASS**
> 回执：`收件箱/回执箱/CEO3/验收-INTEG-c3-rd1.md`（追加节）

---

## 一、门禁

| 项 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 干净树 | `git archive f63fcba \| tar -x -C <tmp>` | 成功；`has_git=no` | `tree.txt` |
| 祖先 | `git merge-base --is-ancestor 7c626b5 f63fcba` | **exit 0** | `tree.txt` |
| 构建 | `cd impl && go build -o xnull ./cmd/xnull` | exit 0 | 本文 |
| 包测试 | `cd impl && go test ./internal/interp/ ./internal/cli/ -count=1` | **exit 0**：interp 2.036s、cli 11.166s | `tests/interp-cli.txt` |

---

## 二、P1-INIT-FWD 双路径

用例 `cases/forward.x`：

```x
Int a = b + 1
Int b = 2
static Int main() {
    print(str(a))
    print(str(b))
    return 0
}
```

| 路径 | 退出码 | stdout | stderr | 证据 |
|---|---:|---|---|---|
| compiled | **0** | `1\n2\n`（4 字节） | 空 | `p1/compiled.{out,err,exit}` |
| `--interp` | **0** | `1\n2\n`（4 字节） | 空 | `p1/interp.{out,err,exit}` |

- `cmp`：stdout **逐字节一致**，stderr 一致；`od` 均为 `31 0a 32 0a`（`p1/cmp.txt`）。
- **P1-INIT-FWD 关闭。**

---

## 三、ENTRY-01 回归

| 用例 | 模式 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| `void main(String[] args)` | compiled / `--interp` | 0，`void:2` | 0，`void:2` | PASS |
| `Int main(String[] args)` | compiled / `--interp` | 7，`int:2` | 7，`int:2` | PASS |
| `Int main()` | compiled | 5 | 5 | PASS |
| `return 300` | compiled | 44（平台截断） | 44 | PASS |
| `return -1` | compiled | 255 | 255 | PASS |
| 顶层字段声明序 | compiled / `--interp` | `a\nb\nmain` | `a\nb\nmain` | PASS |
| 初始化期 fatal | compiled / `--interp` | 134，main 不执行 | 134，stdout 空 | PASS |
| 缺失入口 | compiled | 1，`ENTRY-001` | 1，`ENTRY-001` | PASS |
| 重复入口 | compiled | 1，`ENTRY-002` | 1，`ENTRY-002` | PASS |
| `--` 参数透传 | `--interp` | `2\n--verbose\nx` | 同左 | PASS |
| explicit `public` | compiled | 0 | 0，`public-ok` | PASS |
| explicit `private` | compiled | 1，`ENTRY-003` | 1，`ENTRY-003` | PASS |

逐例原始输出：`entry/<case>/{command,stdout,stderr,exit_code}.txt`。

---

## 四、未跑清单

1. 全仓 `go test ./...`、`go vet ./...`、`build_rt.sh`：本轮任务未要求，未跑（上一轮 `9f5f66c` 已跑，不可直接外推到 `f63fcba`）。
2. 多文件/包级初始化顺序、工程清单模式入口、其他包 `main` 负例。
3. 泛型/默认参数/可变参数 `main` 负例。
4. 初始化期 panic 的栈与诊断质量（仅验证退出码与 main 未执行）。
5. L2/L3 门禁与公开副本同步。

---

## 五、结论

**PASS。** 干净树 `f63fcba` 上，P1-INIT-FWD 双路径逐字节一致，ENTRY-01 两种签名与退出码回归通过，interp/cli 包测试全绿。上一轮 `9f5f66c` 的 FAIL 项已修复并可关闭。
