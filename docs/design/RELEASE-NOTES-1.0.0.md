# XNull mini 1.0.0 发布说明

| 项 | 值 |
| --- | --- |
| 版本 | mini **1.0.0** / XDK **1.0.0** |
| 语言规范 | **3.4.0**（不变） |
| 运行时 ABI | **v1**（不变） |
| Tag | `mini-1.0.0`（annotated） |
| 基线 | `core-evidence@a48a50f4`，分支 `release/1.0` |
| 日期 | 2026-11-22 |

本版本是 mini-only 的 1.0.0 发布：mini 是唯一编译器，XDK 14 个 T0 包随
源码交付，运行时保持稳定 ABI v1。发布物是可重现的 source-only tarball，
不携带宿主平台二进制。

## 1. 安装与自检

解包后从源码构建 mini（`mini.c` 是已提交的 seed，macOS 与 Linux x86_64
使用同一条 C11/POSIX 构建路径）：

```sh
tar -xzf xnull-1.0.0.tar.gz
cd xnull-1.0.0
./src/mini/build.sh
./src/cli/xnull doctor
./src/mini/bin/mini --version
./src/cli/xnull run src/examples/hello.x
```

预期版本输出为 `mini 1.0.0`；`doctor` 退出码 0；hello 输出
`hello, XNull` / `1 + 2 = 3`。

## 2. 已知问题与发布豁免

以下事项是 1.0.0 的**明确记录**，不是已通过项。发布说明不把未完成的工作
写成完成。

### 2.1 U5：owner waiver，真人 trial 转 post-1.0

U5 非作者试用**未通过**。现有证据只是 agent proxy：独立子代理仅凭 README
与 T0 包文档完成了 `xnull check` / `build` / `run`，并据此修正了文档与
路径解析缺口；这不是真人试用，也不冒充真人 PASS。

- 结论：owner 对本项给予 waiver。
- 后续：真人 trial 转入 post-1.0，完成前不得在后续发布中宣称 U5 通过。
- 证据：`docs/design/t0/C1-U0-U5-EVIDENCE.md` §U5。

### 2.2 官方 0.3.0 升级证据：blocked，接受 substitute artifact

`mini-v0.3.0` tag（commit `a36d123b`）没有随包 bootstrap 产物：
`src/bootstrap/bin/xn-s4` 不存在，官方 `./src/mini/build.sh` 以 exit 2
失败，`xn-s4` 尝试卡死后已停止。因此**官方 0.3.0 构建在本机 blocked**。

U3 的升级证据使用替代路径：以 1.0 mini 为 seed，从 0.3.0 tag 自己的
`src/mini/main.x` 构建最小 substitute artifact，并链接该 tag 的运行时。

```text
artifact: /tmp/u3/xnull-0.3.0.tar.gz
sha256:   45f2897d4e739c06e1eee3f3b816d89fc393d1d5c8643f0a8373d0039023f19b
installed version: mini 0.3.0
```

- 结论：U3 状态为 **PASS with substitute artifact**；官方 0.3.0 路径仍为
  blocked，缺失的 bootstrap 不隐藏、不补造。
- 证据：`docs/design/t0/C1-U0-U5-EVIDENCE.md` §U3。

### 2.3 三个 deferred：random / TimeZone / codec 不进入 1.0

以下三项保持 `Deferred candidate`，1.0.0 **不包含**、不提供 stub、不以
空壳 API 冒充支持：

| 项 | 1.0 现状 | post-1.0 方向 A |
| --- | --- | --- |
| random | 无 `xdk.random` 公开面；原始 xorshift64* 桥未作为 XDK 证据 | T1 `xdk.random`：显式 seed、`nextLong`、有界 `nextInt`、`nextDouble`、`nextBool`、`shuffle<T>`；明确确定性、非密码学 |
| TimeZone | UTC-only；`toUTC`/`toLocal` 为恒等操作，无 `TimeZone` 源文件 | 固定偏移子集：`FixedOffset` + `toZone` + `offsetSeconds`；不做 IANA/DST |
| codec | 只有 `key=value` 的 `FileSource`，无 JSON/TOML/YAML codec | JSON codec：`Codec` 协议 + `JsonCodec`，对象标量映射，数组/嵌套按规则拒绝或展平 |

- 决定：三项均按方向 A 转 post-1.0；1.0 不引入半成品符号。
- 证据：`docs/design/t0/R4-EVIDENCE.md` §4（C1–C3）与 §7。

## 3. 发布决策（P1=B / P10=B）

### 3.1 P1=B：macOS + Linux x86_64

- 1.0.0 的目标平台为 **macOS** 与 **Linux x86_64**。
- 本批次在 `Darwin 25.5.0 x86_64`（Apple clang 17.0.0）上完成构建、门禁、
  tarball 重现与安装自检。
- tarball 为 source-only，不携带 macOS 二进制；Linux x86_64 使用同一
  `src/mini/bin/mini.c` seed、同一 C11/POSIX 源码与构建脚本。本批次没有
  在 Linux 机器上单独运行门禁，因此不宣称 Linux 逐项门禁已实跑。

### 3.2 P10=B：中文入库 + 英文翻译

- 设计与规范中文原件入库，作为事实源；英文翻译随发布材料提供，不以英文
  译文替代中文原件。
- 本发布说明保留中文正文，并在文末附英文摘要，便于外部读者核对同一组
  已知问题与决策。

## 4. 不作为 1.0 承诺的能力

- 没有包管理器、依赖 reactor 或 formatter；相关 CLI 命令保持不可用。
- `xdk.tasks`、`xdk.sync` 是语言/运行时内置能力（P9=B），不是 1.0 的
  XDK 包；1.0 包数量为 14。
- 反射不可表达；不以运行期探测替代源码 + 规范可判定的设计。

## 5. 验证记录

发布前门禁全部 PASS：

```text
src/mini/tests/r4_evidence.sh
src/mini/tests/ref.sh
src/mini/tests/xdk.sh
src/mini/tests/xdk_core.sh
python3 src/toolchain/check_layers.py --release 1.0.0
src/runtime/build_rt.sh
src/mini/tests/selfhost.sh
```

`src/toolchain/release.sh` 连续运行两次，tarball sha256 一致：

```text
5964d6dade77971e8aa60bc2c03ddbaae4c2bfc6db35b54af694ea44dafd0d6b  xnull-1.0.0.tar.gz
```

解包到临时前缀后，`./src/mini/build.sh`、`doctor`（exit 0）、hello 与
`mini --version`（`mini 1.0.0`）均通过。提交与 tag 记录见本批次汇报；
发布物校验以 `dist/xnull-1.0.0.tar.gz.sha256` 为准。

## 6. 升级

从 0.2.0 / 0.3.0 源码升级请按
[`t0/MIGRATION-0.x-to-1.0.md`](t0/MIGRATION-0.x-to-1.0.md) 执行。注意
2.2 节：官方 0.3.0 bootstrap 在本机不可用，0.3.0 升级证据来自 substitute
artifact，不代表官方 0.3.0 构建已通过。

---

## English summary

**XNull mini 1.0.0** ships the mini-only compiler, the 14-package T0 XDK at
version **1.0.0**, language **3.4.0**, and runtime ABI **v1**. The release is a
deterministic source-only tarball; build with `./src/mini/build.sh`, then run
`./src/cli/xnull doctor` and `./src/mini/bin/mini --version` (expect
`mini 1.0.0`).

Known issues, recorded as open rather than claimed as passing:

1. **U5 owner waiver.** The non-author trial did not pass. There is only an
   agent-proxy run, not a human PASS. The owner grants a waiver; the human
   trial moves post-1.0.
2. **Official 0.3.0 is blocked.** Tag `mini-v0.3.0` (`a36d123b`) has no
   `src/bootstrap/bin/xn-s4`; the official build exits 2 and the `xn-s4`
   attempt hung and was stopped. U3 uses an accepted substitute artifact built
   from the tag's own `main.x` with the 1.0 seed. It is not evidence that the
   official 0.3.0 build passed.
3. **Three deferred items.** `random`, `TimeZone`, and `codec` are not in 1.0
   and have no stub surface. Post-1.0 direction A is: a T1 `xdk.random` over
   the existing xorshift64* bridge, fixed-offset time zones, and a JSON codec.

**P1=B:** macOS and Linux x86_64. Verification ran on Darwin 25.5.0 x86_64;
the tarball is source-only and uses the same C11/POSIX path on Linux, but no
separate Linux gate run is claimed here.

**P10=B:** Chinese originals are the source of record, with English
translations provided alongside them; translations do not replace the Chinese
originals.
