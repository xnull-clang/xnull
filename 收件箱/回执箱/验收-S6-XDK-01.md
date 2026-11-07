# 验收：S6-XDK-01（包结构与依赖）

> **验收人**：QA1（独立质量线）
> **结论：FAIL（依赖矩阵违约 + collections 语义未实现）**
> **复验点**：main 含 S6-03/04/05 合并（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/xdk01-imports.log`、`sema-s6.log`、`codegen-s6.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 8 个 `impl/lib/xdk/*.x` 文件存在 | **PASS**：errors/tasks/sync/runtime/collections/text/sys/net |
| 依赖矩阵仅允许 `errors→runtime` | **FAIL**：`text.x` 依赖 `xdk.errors`，`TestXdkPackageSkeletons` 失败 |
| 8 包 import 后语义通过 | **FAIL**：`xdk.collections` 导入触发 `TY-229`（`RingBuffer.isFull/isEmpty` 等未实现） |
| loader 按 import 装载 | **PASS**：`TestXdkLoaderByImport` |
| 包名与 S4/S5/S7 引用一致 | **PASS**：骨架命名齐 |

**判定：FAIL。** 8 个骨架文件存在且 loader 可用；但依赖方向违约（text→errors），且 `collections.x` 的成员未实现导致 8 包导入无法通过语义检查。按计划口径不能记 PASS。

---

## 二、实测

### 2.1 单包 import

`xdk.errors`、`tasks`、`sync`、`runtime`、`text`、`sys`、`net` 单包 import 均 rc=0；`xdk.collections` rc=1：

```text
one.x:83:16: error[TY-229]: XDK 类型 `RingBuffer` 的成员 `isFull` 尚未支持（S6-01）
one.x:91:16: error[TY-229]: XDK 类型 `RingBuffer` 的成员 `isEmpty` 尚未支持（S6-01）
...
```

8 包全量 import 同样 rc=1。

### 2.2 依赖矩阵

`TestXdkPackageSkeletons`：

```text
xdk_skeleton_test.go:49: text.x 依赖 xdk.errors 不在依赖矩阵允许集（[]）
--- FAIL: TestXdkPackageSkeletons
```

`allowed` 仅配置 `errors→runtime`；`text.x:8 import xdk.errors` 违反规则。

### 2.3 loader

`TestXdkLoaderByImport` PASS：`xdk.errors` 的 `ErrorKind/Error/report` 声明可装载。

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| 01-1 | `text.x` 依赖 `xdk.errors` 不在依赖矩阵 | `codegen-s6.log` `TestXdkPackageSkeletons` | E2/E6 依赖矩阵 |
| 01-2 | `collections.x` 成员未实现（`TY-229`） | `xdk01-imports.log` | E2/E4/E5 collections |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/xdk01-imports.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/codegen-s6.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/sema-s6.log`
- 断言依据：S6 §1.4.3、§10 XDK-01；`收件箱/门/S6验收计划-E2.md`
