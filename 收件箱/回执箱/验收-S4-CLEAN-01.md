# 验收：S4-CLEAN-01（清理与错误路径）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（E3 `73a14ef` 临时实参顺序 + report 格式修复后复签；双路径一致）
> **复验点**：main `0352059`（含 E3 `73a14ef`、E2 `fcd1512`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-clean2`，sha256 `6ee31de081bc09f00767ce31c359c6b3e7ebdbfdeadee06a6b909c1793f1bc6d`
> **证据**：`evidence/S4-QA/CLEAN-01b/`
> **依据**：S4 §8、CLEAN-01；本轮裁定：临时实参 deinit 顺序以 compiled `err:x/dR` 为准
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `errdefer` 补偿 LIFO | **PASS**：`close:b` → `close:a` |
| Ok 路径不执行补偿 | **PASS**：`ok(a)` 输出 `1` |
| 补偿失败不覆盖原错误 | **PASS**：`comp:comp-fail` → `err:orig` |
| 部分完成状态回滚 | **PASS**：`0` / `fail` |
| `try` 逐层触发各层 `errdefer` | **PASS**：`inner-e` → `outer-e` → `true` |
| 临时实参 deinit 顺序 | **PASS**：compiled `err:x` / `dR`；interp 已对齐 |
| 补偿失败 + 临时参数组合 | **PASS**：`comp:comp-fail` / `err:orig` / `dR`（双路径一致） |
| 主 CLEAN 序列双路径 | **PASS**：stdout/stderr diff 全 0 |
| `TestS4CLEAN01*` | **PASS**：interp + codegen |

**判定：PASS。** 上一轮的参数所有权顺序差异已按 compiled 口径统一；四个 CLEAN 夹具双路径 stdout/stderr 逐字节一致。

---

## 二、逐项实测

### 2.1 主 CLEAN 序列

interp = compiled：

```text
work
close:b
close:a
err:boom
1
0
fail
inner-e
outer-e
true
```

### 2.2 参数所有权（compiled 为准）

`g(new R())`：

```text
err:x
dR
```

`f(new Comp(), new R())`：

```text
comp:comp-fail
err:orig
dR
```

interp 输出与 compiled 完全一致（outdiff=0、errdiff=0）。

### 2.3 部分完成

`tx(s)` 两步 `inc` + `errdefer dec` → `Err("fail")`：双路径 `0` / `fail`。

---

## 三、残余项（不影响 CLEAN-01）

| 项 | 状态 | 归属 |
|---|---|---|
| `mapErr` 转换函数签名（OBS-01） | E2 `fcd1512` 后仍见 `(E2)->E2` 期望与 E4 `(E1)->E2` 用例不一致 | OBS-01/E2，另行处理 |

CLEAN-01 本身无未闭合失败项。

---

## 四、证据

- `evidence/S4-QA/CLEAN-01b/matrix.tsv`
- `clean.x` / `clean.{interp,compiled}.{out,err}` / `clean.*diff.exit`
- `clean2.x`、`clean-param.x`、`clean-partial.x` 同上
- `gotest-interp.out`、`gotest-codegen.out`
- 原始红→绿：`evidence/S4-CLEAN/`、`evidence/S4-QA/CLEAN-01/`（历史 FAIL 证据保留）
