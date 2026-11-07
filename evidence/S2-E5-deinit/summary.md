# S2-E5-deinit 验证：E4 deinit 发射契约（运行时侧独立复跑）

## 复签（2026-11-07，beba3f6 重放）——通过

- 被验：`main=beba3f6`（E4 以 main 为基重放；当前 main `ea913dd` 含该提交）
- 复跑环境：干净 worktree `/tmp/e5-deinit-verify` @ `beba3f6`，`/tmp/xnull-beba` 构建
- 结果：**5/5 通过**

| 项 | 结果 | 证据 |
|---|---|---|
| 用户 deinit 体先于字段释放 | PASS | `replay-beba3f6-order.log`（main → outer-deinit → inner-deinit） |
| 类引用字段赋值 retain 新值 / release 旧值 | PASS | `replay-beba3f6-assign-c.txt`（`rt_retain(a1); rt_release(h->a); h->a = a1;`） |
| 成员表达式自赋值 `h.a = h.a` | PASS | 同上（临时 + retain + release + 写回） |
| handle 字段赋值与 deinit 释放 | PASS | `replay-beba3f6-hold-c.txt`（`rt_retain(g); rt_release(h->f); h->f = ...` + deinit `rt_release(o->f)`） |
| Bytes 字段释放（单测口径） | PASS | `replay-beba3f6-tests.log`（`TestS2DeinitReleasesHandleAndBytes`）；端到端仍被 `SEMA-BYTES` 阻断（`bytes-sema-block.log`） |

- 回归：`build_rt.sh` 六套件 exit 0（`replay-beba3f6-build_rt.log`）；E4 的 `TestS2*` 六例全 PASS（含继承/vtable/构造器）。
- 说明：根工作区当时处于 `7b907ba` 的在途合并（`UU` 索引），故用干净 worktree @ `beba3f6` 验证；结论只针对该提交树。

## 首轮（main=f975810）——已由重放覆盖

- 基线：`main=f975810`
- 被验交付：E4 `pod/e4-codegen@70f4385`（声称已落 deinit 契约）；`main` 上的 handoff 为 `a75226a`
- 方法：同一组 XNull 探针分别用 main 与 70f4385 构建运行；检查生成 C 的赋值/释放顺序；不修改 E4 代码
- 结论：**契约在 70f4385 上成立；main 未包含该提交，三项中两项在 main 上不成立**（该缺口已由 `beba3f6` 重放修复）

## 一、逐项结果

| # | 契约点 | main f975810 | 70f4385 | 证据 |
|---|---|---|---|---|
| 1 | 用户 `deinit` 体先执行，字段释放后执行 | **PASS** | **PASS** | `main-order.log`：`main` → `outer-deinit` → `inner-deinit` |
| 2 | 引用字段赋值：retain 新值 → release 旧值 → 写入 | **FAIL** | **PASS** | `main-assign-c.txt`：`h->a = a1;` 裸赋值；`branch-assign-c.txt`：`rt_retain(a1); rt_release(h->a); h->a = a1;` |
| 3 | 字段释放覆盖 `xrt_handle *` / `xrt_bytes_obj *` | **FAIL** | **PASS（handle）** | `main-handle-deinit-c.txt`：Holder deinit 空体；`branch-handle-deinit-c.txt`：`rt_release(o->f);` |
| 3b | Bytes 字段端到端 | N/A（`SEMA-BYTES` 未落，`Bytes` 仍 `RES-101`） | N/A（同上） | 分支单测 `TestS2DeinitReleasesHandleAndBytes` PASS（绕过 sema） |
| 4 | 置 null 提前释放 / alias 安全 | N/A（可空类字段不支持：`可空类型 xn_Cls_Inner * 未支持`） | N/A / **部分** | `branch-selfassign.log`：`h.a = h.a` 被拒（`类引用字段赋值右值 *xfront.Member 未支持`）；Ident 别名可用 |
| 5 | deinit 发布 self 静态检查 | 归 E2（未落） | 归 E2 | 运行时 retain-after-terminate fatal 已在 |

## 二、关键结论

1. **main 未包含 70f4385**：`git merge-base --is-ancestor 70f4385 main` = NO。main 的 deinit 实现来自另一提交 `81e146e`（只做「用户体先执行」，未做字段赋值 retain/release 与 handle/Bytes 字段释放）。
2. **70f4385 的契约符合 E5 回签的五项**，但有两处边界：
   - `h.a = h.a`（成员表达式自赋值）被 codegen 拒绝，不是「安全通过」；Ident 别名（`o.inner = innerVar`）才走 retain 分支。
   - 可空类字段未支持，故「deinit 内置 null」无法端到端验证；`rt_release(NULL)` 安全由运行时保证。
3. **集成冲突**：70f4385 与 main 的 `81e146e` 同改 `classes.go`/`classes_expr.go`/`codegen.go`，且 70f4385 落后 main 32 个提交；直接合入必冲突。需 E4 以 main 为基重放 70f4385 的增量（字段赋值 retain/release + handle/Bytes 字段释放），并带上 E5 的 `c1ffd20`（弱槽修复）。E5 不碰 codegen。
4. 容器字段赋值按 E4 选择显式报错（值结构浅拷贝会双释放），E5 **可接受**，归 B2 引用语义容器；继承/`super.deinit()` 去重同理待继承卡。

## 三、复现（只读）

```bash
# main
cd impl && go build -o /tmp/xnull-main-f975 ./cmd/xnull
XNULL_RUNTIME=<repo>/impl/runtime /tmp/xnull-main-f975 build order.x -o order && ./order
grep -n 'h->a' assign.c            # main：裸赋值
sed -n '/Holder_deinit_hook/,/^}/p' hold.c   # main：空体

# 70f4385
git worktree add --detach /tmp/e4-deinit 70f4385
cd /tmp/e4-deinit/impl && go build -o /tmp/xnull-e4deinit ./cmd/xnull
go test ./internal/codegen/ -run 'TestS2Deinit|TestS2FieldAssign' -count=1 -v   # 3 例 PASS
```

探针源码（`order.x` / `assign.x` / `hold.x`）见 `evidence/S2-E5-deinit/probes/`。

## 四、日志

| 文件 | 内容 |
|---|---|
| `main-order.log` | main：用户体→字段释放顺序 |
| `main-assign-c.txt` | main：裸赋值（无 retain/release） |
| `main-handle-deinit-c.txt` | main：Holder deinit 空体 |
| `branch-assign-c.txt` | 70f4385：retain 新值 / release 旧值 |
| `branch-handle-deinit-c.txt` | 70f4385：`rt_release(o->f)` |
| `branch-selfassign.log` | 70f4385：成员自赋值被拒 |
| `branch-tests.log` | E4 三个单测 PASS |
