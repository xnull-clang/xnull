# S3-08：诊断 / 选项 / 指标（分配统计、GC 指标、--mem、--stats）

- 卡片：S3-08（S3 §21/§23）
- 基线：`main=ba1b5c2`；上一卡 `d433715`（S3-07）
- 结论：运行期分配统计与 GC 指标可开关；构建选项 `--mem=auto|arc|gc` 与 `--stats` 落地

## 先红

新增 3 例（策略覆盖、统计发射、统计运行）在未接线时失败：

```
FAIL TestS3_08MemPolicyOverride  --mem=arc 下环类应为 ARC
FAIL TestS3_08StatsEmission      --stats 生成代码缺少 "xrt_stats_reset"
FAIL TestS3_08StatsRun           stderr 缺少统计报告
```

原始输出：`red.log`。

## 实现

**运行时（`rt.h`/`rt.c`/`rt_gc.c`/`xrt.h`/`xrt_abi.c`）**

```c
typedef struct xrt_stats {
    uint64_t allocs, frees, bytes, gc_collections, gc_freed;
} xrt_stats;
void xrt_stats_reset(void);
void xrt_stats_get(xrt_stats *out);
void xrt_stats_set_enabled(int on);
int  xrt_stats_enabled(void);
void xrt_stats_report(void); /* 单行 stderr：allocs/frees/live/bytes/gc_collections/gc_freed */
```

- 计数点：`rt_alloc` / `rt_gc_new`（allocs/bytes）、隔离区与 sweep（frees）、`rt_gc_collect`（gc_collections/gc_freed）。
- 默认关闭（`xrt_stats_set_enabled(0)`），关闭时计数零开销。

**codegen（`Options` + 主函数）**

```go
type Options struct {
    LinkArgs  []string
    MemPolicy string // ""/auto：按 §15.1；arc/gc：强制全部类
    Stats     bool   // 打开统计并输出报告
}
```

- `EmitCWithBuildOptions`：`auto` 用策略表；`arc/gc` 覆盖 `Kind=="class"` 的 Policy（枚举/单例仍按规范 GC）。
- `--stats`：主包装在调用 `xn_main` 前 `xrt_stats_reset/set_enabled(1)`，收尾
  `rt_gc_collect → rt_quarantine_flush → xrt_stats_set_enabled(0) → xrt_stats_report()`。
- CLI：`xnull build file.x --mem=arc|gc|auto --stats -o out`（flag 需在 `.x` 之后）。

**测试**：`mem_s308_test.go`（策略覆盖/发射/运行）；`test_std.c::test_stats`（allocs/frees/bytes/gc 指标）。

## 后绿

- `green-tests.log`：3 例 PASS。
- `green-build_rt.log`：六套件 exit 0。
- `cli-mem-arc.log`：`--mem=arc` 环类 `rt_arc_new`，统计 `live=2 gc_freed=0`（ARC 环泄漏，符合强制 ARC 语义）。
- `cli-mem-gc.log`：`--mem=gc` 非环类 `rt_gc_new`，统计 `live=0 gc_freed=1`。
- `go test ./internal/codegen/...`、`./internal/cli/` 全绿。

## 边界

| 项 | 状态 |
|---|---|
| `--mem` 适用范围 | 只覆盖类；数据枚举/单例按 S3 §3/§8 固定 GC（不随选项改变） |
| 逃逸分析转储（§23） | 未做（Escape 仍 `n/a`，见 S3 盘点 P0-5） |
| 统计精度 | allocs/frees 为对象数；bytes 为累计分配（含头），释放不扣减；live=allocs-frees |
| 关闭时开销 | 计数分支判断，无额外原子操作 |

## 复现

```bash
cd impl && go test ./internal/codegen/ -run TestS3_08 -count=1 -v
cd impl/runtime && sh build_rt.sh
xnull build prog.x --mem=gc --stats -o prog && ./prog
```
