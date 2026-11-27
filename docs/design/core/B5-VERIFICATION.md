# B5 core 2.x 验证账本

| 项 | 值 |
| --- | --- |
| 批次 | B5.1 foundation 开始时建立；后续 B5.2–B5.4 续填 |
| 口径 | 逐包按 2.x 合同 + `xdk_core`/`xdk2`/`xdk` 场景验证 |
| 当前状态 | **B5.1 进行中**；foundation 5 Verified、2 Partial；B5.2–B5.4 未开始 |
| 权威 | `docs/design/core/STATUS.md`、`src/xdk/xdk2-packages.tsv`、各包合同 |

---

## B5.1 foundation 7 包

| 包 | 1.x 状态 | 2.x 验证结论 | 剩余 |
| --- | --- | --- | --- |
| `xdk.errors` | Verified（mini） | 通过 `xdk_core` / `xdk2` 场景 | 无 |
| `xdk.meta` | Verified（mini） | 通过 | `RuntimeRole` 等新画像类型按合同复核 |
| `xdk.bytes` | Verified（mini） | 通过 | ByteBuffer 等 X 范围不在 2.x |
| `xdk.text` | **Partial** | 基础场景通过；命名/Unicode/Regex 边界未全覆盖 | 补边界场景与合同差异 |
| `xdk.collections` | **Partial** | 基础场景通过；`joinWith`/`Entry`/固定 `Pair` 已整合 | 补 2.x 合同场景；泛型 `Pair` 编译器问题 |
| `xdk.math` | Verified（mini） | 通过；本轮新增 `Complex`/`RoundingMode` | 合同类型数从 4 增至 6，tsv 仍写 4 |
| `xdk.time` | Verified（mini） | 通过；`Instant`/`TimeZone` 已加 | `sleepContext`/layout 已整合 |

### B5.1 出口条件

- 7 包逐类型合同核对记录；
- `text`/`collections` 的 Partial 边界要么补实现/场景，要么登记为 X/waiver；
- `xdk_core.sh`、`xdk2.sh`、`xdk.sh`、`m7_gate.sh` 全绿；
- 更新 `docs/design/core/STATUS.md` 的 2.x 视角。

---

## B5.2–B5.4 待办

| 子批 | 包 | 当前 |
| --- | --- | --- |
| B5.2 | `xdk.io`、`xdk.fs`、`xdk.sys` | 1.x Partial；未做 2.x 逐类型验证 |
| B5.3 | `xdk.log`、`xdk.config`、`xdk.cli` | 1.x Verified；`log.Sampler` 实现名 `LogSampler` 需文档同步 |
| B5.4 | `xdk.runtime`、`xdk.execution` | `execution` 已 implemented；`Once` 方法名 `run`；runtime 8 类型 |

---

## 已知阻塞

- 泛型 `Pair` 与 `Pair<Polynomial,Polynomial>` 冲突，`BigInt` 用 `BigIntPair` 规避；
- 枚举 0 与 null：多个包用 `Unknown` 哨兵；
- `String? == String?` 指针比较、大 Long 负字面量、跨线程 GC 根、计时 flake；
- `xdk2` 时长已接近/超过 900s，B5 增加场景前需先压时长。
