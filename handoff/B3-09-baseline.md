# B3-09 前置基线：全仓库 `.x` 的 Go emit-c vs xnullc

> 只读基线，不改 xnullc / Go oracle。
> 机器可读：`handoff/B3-09-baseline.tsv`
> 基线时间：2026-11-09；oracle 二进制由 `main` 现场构建；xnullc =
> `impl/lib/b3/xnullc.x`（解释执行）。
> 判定：**raw unified diff 行数**（含 `---/+++/@@`），不做归一化。

## 1. 范围与方法

- 输入集合：`git ls-files '*.x'` 排除 `evidence/`、`archive/`（历史证据/归档快照，
  非产品/测试当前源），共 **241** 个文件。
- 每个文件按“能否作为入口”分组：
  - `go build --emit-c` 成功 → 入口（单文件/多文件按 `--emit-ast-bundle` 文件数）；
  - 失败 → 非入口/负例（不计 C diff，记录首条诊断）。
- xnullc 调用：
  - 单文件：`xnullc <path> <xnast --ast> <xfb-projection>`；
  - 多文件：追加 `--emit-ast-bundle` JSON 作为第 4 参数（沿用现有 B3 脚本口径）。
- 多文件 import 解析与 `LoadUnits` 一致（依赖后序）；xnullc 仍以 **argv** 接收
  bundle/AST，超大入口会触发 `ARG_MAX`（见 §5）。

## 2. 总量

| 组 | 文件数 | Go 入口 | xnullc 成功 | diff=0 | diff>0 | 中位 diff | 最大 diff | diff 行合计 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| difftest | 89 | 33 | 33 | 11 | 22 | 14 | 1414 | 2292 |
| examples | 12 | 10 | 10 | 2 | 8 | 51 | 1365 | 2695 |
| impl | 12 | 3 | 2 | 0 | 2 | 7373.5 | 7892 | 14747 |
| tests | 128 | 97 | 97 | 70 | 27 | 0 | 1483 | 11284 |
| **合计** | **241** | **143** | **142** | **83** | **59** | **0** | **7892** | **31018** |

- 单文件入口 118；多文件入口 25；非入口/负例 98。
- 多文件中 xnullc 失败 1：`impl/lib/b2/xparser.x`（bundle/AST 超过 argv 上限，
  `Errno 7 Argument list too long`），不是语义 diff。
- `tests` 组 70/97 已 0 diff；`examples` 仅 hello/containers 0 diff；
  `impl` 的 xlex/xnfmt 是两个最大差异源。

## 3. 多文件入口（25）

0 diff：`difftest/s2/bnd01/xpkg/main.x`、`tests/b3/fixtures/bundle_{collections,sync,tasks}/app.x`、
`tests/b3/fixtures/xdk/{exit,runtime}.x`、`tests/s6/xdk06_{exit,runtime}.x`。

有差异：

| diff 行 | 入口 | 首因（见 §4） |
|---:|---|---|
| 6855 | `impl/lib/b2/xlex.x` | temp/root/缩进 + 容器 typedef |
| ARG_MAX | `impl/lib/b2/xparser.x` | argv 通道限制 |
| 1483 | `tests/{b2/corpus/,}tests/s6/xdk07/collections_basic.x` | 函数指针 typedef 缺失 |
| 1461 | `.../collections_nonnull.x` | 同上 |
| 1414 | `difftest/anchors/cases/pkg/f2.x` | Map typedef 缺失 |
| 614 | `tests/b3/fixtures/bundle/app.x` | 容器 typedef 缺失 |
| 526 | `tests/{b2/corpus/,}tests/b0-07c-numeric/cases/t04_bytes_surface/case.x` | Bytes/临时释放顺序 |
| 518 | `tests/b3/fixtures/bundle_text/app.x` | 非 ASCII 字符串丢失 + temp/root |
| 176 | `tests/{b2/corpus/,}tests/s6/xdk05/sync_basic.x` | `Result<Int,CancelledError>` typedef 缺失 |
| 34 | `examples/multi/main.x`、`tests/b2/corpus/examples/multi/main.x` | temp/root |
| 27 | `tests/.../t00_sanity_text/case.x` | temp/root |

## 4. 已知不支持/不一致特性（按首条 diff 归类）

> TSV `known` 列按**首条 diff**归类，可能低估“同一文件多因”；分类计数：
> temp/root 次数 29、void 返回 17、temp/编号/缩进 8、非 ASCII 4、容器 typedef 1。
> 另有若干文件首因是 typedef，但被首个 temp 差异抢占分类。

| 编号 | 特性 | xnullc 现状 | 代表入口 | 首条 diff 证据 |
|---|---|---|---|---|
| K-01 | **`void` 返回类型** | 生成 `int64_t` 而非 `void`（签名/定义一起错） | `examples/parser-seed.x` | `-static void xn_show(...)` / `+static int64_t xn_show(...)` |
| K-02 | **容器 typedef** | 部分 `xn_map_*`/`xn_arr_*` typedef 缺失或顺序不同 | `examples/classes.x`（map_s_i）、`difftest/.../f2.x`（map_s_s）、`tests/b3/fixtures/bundle/app.x`（arr_u16） | Go 有 `typedef struct { rt_header ... } xn_map_s_i;`，xnullc 无 |
| K-03 | **函数指针 typedef** | `xn_fn_*` typedef 缺失 | `tests/.../collections_basic.x` | `-typedef int (*xn_fn_int_int64_t_int64_t)(...)` |
| K-04 | **非 ASCII 字符串** | 中文字符被丢弃/替换 | `tests/b3/fixtures/bundle_text/app.x` | `-"Regex.compile: 暂不支持该 ERE 构造"` → `+"Regex.compile:  ERE "` |
| K-05 | **Result 错误类型 typedef** | `Result<_,CancelledError>` 等 typedef 缺失 | `tests/.../sync_basic.x` | `-typedef struct { int ok; ... xrt_error_kind err; } xn_Result_Int_CancelledError;` |
| K-06 | **temp 编号/root 次数/缩进** | 编号复用、rootTempDecls 层数、while(1) 降级/缩进不一致 | `impl/lib/b2/xlex.x`、`examples/lexer-seed.x`、bundle_text | 见 `handoff/B3-08c`/`B3-regexmatchat-diff.md` |
| K-07 | **bundle argv 上限** | 大 AST/bundle 只能走 argv，超过 `ARG_MAX` | `impl/lib/b2/xparser.x` | `Errno 7 Argument list too long` |
| K-08 | **Bytes 临时释放顺序** | `rt_release(ch)` 位置/数量不同 | `.../t04_bytes_surface/case.x` | 首条 diff 为 `-            rt_release(ch);` |

补充观察：
- `impl/xnfmt/xnfmt.x`（7892）与 `impl/lib/b2/xlex.x`（6855）是最大单点；两者都同时
  命中 K-02/K-06，且文件规模放大 temp 编号差。
- `tests` 组 70/97 已 0 diff，说明 B3 基础面主体已对齐；剩余集中在上述 8 类。
- 原始 diff 行数会随 temp 号整体平移而变化（一个早期编号差会让后续所有行变红），
  **B3-09 验收应同时看“首因类别”和归一化 diff**，不能只看 raw 行数。

## 5. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang
(cd impl && go build -o /tmp/xnull-orc ./cmd/xnull && go build -o /tmp/xnast-orc ./cmd/xnast)
# 单文件
/tmp/xnull-orc build --emit-c examples/hello.x > /tmp/go.c
/tmp/xnull-orc run --interp impl/lib/b3/xnullc.x -- examples/hello.x \
  "$(/tmp/xnast-orc --ast examples/hello.x)" \
  "$(python3 tests/b3/xfb-projection.py examples)" > /tmp/xn.c
diff -u /tmp/go.c /tmp/xn.c | wc -l
# 多文件：第 4 参数为 --emit-ast-bundle JSON
```

TSV 字段：`path group kind files go xn diff note known`。
`kind` ∈ 单文件/多文件/非入口·负例；`xn` ∈ OK/FAIL/skip；`diff` 为 raw unified
diff 行数（`MAYBE` 表示 xnullc 失败，无 C 可比）。
