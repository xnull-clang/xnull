# B5 core 2.x 验证账本

| 项 | 值 |
| --- | --- |
| 批次 | B5.1 foundation 开始时建立；后续 B5.2–B5.4 续填 |
| 口径 | 逐包按 2.x 合同 + `xdk_core`/`xdk2`/`xdk` 场景验证 |
| 当前状态 | **B5.2 进行中（场景通过 ≠ 批完成）**；步级清单见下 |
| 粒度 | **批 = 多个步的容器**；步 = 一个可独立验收的任务。批末才允许标完成 |
| 权威 | `docs/design/core/STATUS.md`、`src/xdk/xdk2-packages.tsv`、各包合同 |

---

## B5.1 foundation 7 包

| 包 | 1.x 状态 | 2.x 验证结论 | 剩余 |
| --- | --- | --- | --- |
| `xdk.errors` | Verified（mini） | 通过 `xdk_core` / `xdk2` 场景 | 无 |
| `xdk.meta` | Verified（mini） | 通过 | `RuntimeRole` 等新画像类型按合同复核 |
| `xdk.bytes` | Verified（mini） | 通过 | ByteBuffer 等 X 范围不在 2.x |
| `xdk.text` | **Partial** | `xdk_core` 覆盖 Unicode code point、POSIX ERE 子集、printf Format；边界场景 PASS | Unicode 规范化/完整 PCRE 归 X；命名差异记录 |
| `xdk.collections` | **Partial** | `xdk_core` 覆盖 joinWith/groupBy/Entry/OrderedMap/BTreeMap/Set；场景 PASS | 泛型 `Pair` 编译器冲突用 `BigIntPair` 规避，登记为编译器债 |
| `xdk.math` | Verified（mini） | 通过；本轮新增 `Complex`/`RoundingMode` | 合同类型数从 4 增至 6，tsv 仍写 4 |
| `xdk.time` | Verified（mini） | 通过；`Instant`/`TimeZone` 已加 | `sleepContext`/layout 已整合 |

### B5.1 出口结论（2026-11-27）

- 7 包均有 2.x 场景：`xdk_core` 的 text/collections 段 + `xdk2`/`xdk` 回归；
- `text`：Unicode code point、POSIX ERE 子集、printf 已覆盖；完整 Unicode 规范化/PCRE 为 X；
- `collections`：joinWith/groupBy/Entry/OrderedMap/BTreeMap/Set 已覆盖；泛型 `Pair` 冲突为编译器债；
- 门禁：`xdk_core.sh`、`xdk2.sh`、`xdk.sh`、`m7_gate.sh` 全绿；
- 结论：**B5.1 场景级完成**；逐类型核对表留在 `core/STATUS.md` 维护。

---

## B5.2 步级清单（批未完成）

批 B5.2 = io/fs/sys 三包，不等于“跑过 xdk_core”就完成。必须逐步过：

| 步 | 任务 | 出口 | 状态 |
| --- | --- | --- | --- |
| B5.2-S1 | `xdk.io` 逐类型合同核对 | 15 有实现 / 7 缺失，见 [`B5-IO-MATRIX.md`](B5-IO-MATRIX.md) | 进行中（7 已补，7 待补） |
| B5.2-S2 | `xdk.fs` 逐类型合同核对 | Path/OpenOptions/Permissions/Metadata/DirEntry/File/Dir/Temp/TempDir/FileSystem/PathMatcher/FileLock | 未开始 |
| B5.2-S3 | `xdk.sys` 逐类型合同核对 | Signal/ProcessBuilder/Process/ProcessResult/Env/Platform/Resource/SystemInfo | 未开始 |
| B5.2-S4 | 批出口 | 三包矩阵 + waiver + 门禁 | 未开始 |

当前仅有 `xdk_core` 的 fs/sys 场景证据；**不能据此关闭 B5.2**。

---

## B5.2 当前证据（不是出口）

- `xdk_core` 已有 fs/sys 场景：File/Dir/Path、Long offset、atomic/temp、walk/glob、
  metadata/permissions/links、copy/rename；sys env/stdio/signal/resource；
- 这些只能证明“场景可用”，不能替代 io/fs/sys 的逐类型合同矩阵；
- 门禁：`xdk_core.sh` / `xdk2.sh` / `xdk.sh` 全绿。

## B5.3–B5.4 待办

| 子批 | 包 | 当前 |
| --- | --- | --- |
| B5.2 | `xdk.io`、`xdk.fs`、`xdk.sys` | **进行中**：场景通过；逐类型矩阵未完成（S1 进行中） |
| B5.3 | `xdk.log`、`xdk.config`、`xdk.cli` | 未开始（B5.2 未闭批） |
| B5.4 | `xdk.runtime`、`xdk.execution` | `execution` 已 implemented；`Once` 方法名 `run`；runtime 8 类型 |

---

## 已知阻塞

- 泛型 `Pair` 与 `Pair<Polynomial,Polynomial>` 冲突，`BigInt` 用 `BigIntPair` 规避；
- 枚举 0 与 null：多个包用 `Unknown` 哨兵；
- `String? == String?` 指针比较、大 Long 负字面量、跨线程 GC 根、计时 flake；
- `xdk2` 时长已接近/超过 900s，B5 增加场景前需先压时长。
