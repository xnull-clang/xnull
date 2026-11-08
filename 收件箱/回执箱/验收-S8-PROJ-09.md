# 验收：S8-PROJ-09（可复现）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `e1cdf78`（含 S8-09；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-09/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 两次构建 `.xmeta`/产物摘要一致 | **PASS**：两次 sha256 完全相同 |
| 同锁写入字节稳定、坐标升序 | **PASS**：`TestLockBytesStable` |
| 输入摘要穷举且稳定 | **PASS**：`TestInputsDigest`（source/toolchain/platform/profiles/lock 变化均改变） |
| 构建摘要比对 | **PASS**：`TestBuildSummaryCompare` |
| `target/` 外无写入（write-jail） | **PASS**：构建前后 target 外文件 sha 清单 `diff` 为空 |
| `.xmeta` 解析/字段校验 | **PASS**：`internal/xmeta` 5 例 |

**判定：PASS。** 同输入两次构建产物与 `.xmeta` 字节一致；锁/输入摘要稳定；构建仅写 `target/`；write-jail 通过。

---

## 二、实测

### 2.1 双构建

```text
build1 rc=0
h1 = eab86644… 47d02429…
build2 rc=0
h2 = eab86644… 47d02429…
REPRO=OK
```

`digests.txt` 记录 `.xmeta` 与产物（`app-1.2.3`）的 sha256。

### 2.2 write-jail

构建前后对 `target/` 外全部文件取 sha256 清单：

```bash
find . -not -path './target/*' -type f -exec shasum -a 256 {} \; | sort
```

`outside-before.txt` 与 `outside-after.txt` 的 `diff` 为空（`write_jail_diff_rc=0`）。

### 2.3 官方用例

`TestLockBytesStable`、`TestInputsDigest`、`TestBuildSummaryCompare`、`TestCheckWritesOutsideTarget` 全 PASS；`internal/xmeta` 5 例 PASS。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-09/repro-tests.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-09/digests.txt`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-09/outside-before.txt`、`outside-after.txt`、`outside-target.diff`
- 断言依据：S8 §5.3/§10 PROJ-09；`收件箱/门/S8验收计划-QA.md`
