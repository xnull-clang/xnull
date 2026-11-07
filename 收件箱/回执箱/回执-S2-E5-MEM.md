# 回执：S2-E5-MEM（MEM-01 / MEM-02 / BND-10）

- 执行位：运行时线 E5
- 基线：`main=fa6d821`；只提交到 `pod/e5-runtime`，**未自行合并 main**
- 卡 1：`9e90d4e`（MEM-01 生命周期 + MEM-02 混合引用图）
- 卡 2：`bbeca42`（BND-10 策略 → 运行时行为）
- 证据：`evidence/S2-E5-MEM01/`、`evidence/S2-E5-BND10/`
- 接力棒：`handoff/S2-E5-MEM01.md`、`handoff/S2-E5-BND10.md`

## 卡 1（9e90d4e）：MEM-01 / MEM-02

**先红**：GC 清扫顺序原为 scan 释放 ARC 引用 → deinit，deinit 内字段已失效；
`test_gc.c` 断言 `rt_refcount(字段)==2` 失败（exit 134，`red-sweep-order.log`）。

**修复**：清扫顺序改为 terminated → 清弱槽 → **deinit** → scan(release ARC) → free。

**后绿**：`build_rt.sh` 六套件 exit 0；`TestS2MEM*` 4 例 PASS。

| 锚点 | 结果 | 说明 |
|---|---|---|
| MEM-01 deinit 顺序 | PASS | 父类链 deinit 生效（`main` → `base-deinit`）；派生类自定义 deinit 被 sema `TY-203` 拒绝 → E2 |
| MEM-01 stack 提升 | 判定就绪 / 未分配栈 | 纯值类 `stackEligible=true`，deinit 类 false；实际栈分配未做（§2.7 许可优化） |
| MEM-01 struct 不进 ARC/GC | PASS（拒绝面） | sema 拒引用字段；codegen 对 `StructDecl` 显式报错不分配；struct 端到端未实现 → E4 |
| MEM-02 GC 持 ARC | PASS | deinit 时字段有效，sweep 恰好释放一次 |
| MEM-02 ARC 持 GC 为根 | PASS | 扫描链 + 根双路可达（`test_gc` 3/5 段） |
| MEM-02 弱引用清除 | PASS | ARC/GC 两链均在 deinit 前清（`test_hard` + 上一卡 UAF 修复） |
| MEM-02 环回收 | PASS | 无根环一轮回收；有根环存活（`test_gc` 1/2 段） |
| MEM-02 全 ARC 环规避 | PASS（判定） | 直接字段环 → `policy=gc`；实际分配见卡 2 |

## 卡 2（bbeca42）：BND-10

**先红**：同一 `cycle.x` 在卡 1 提交上仍 `rt_arc_new`，ARC 环泄漏，退出只输出
`main`（`S2-E5-BND10-red.log`）。

**实现**：`sema.AnalyzeWith → Strategies → EmitCWithStrategies`；GC 类
`rt_gc_new` + `scan` 钩子；GC 引用不计数（局部/字段/返回/实参均不
retain/release）；GC 类 deinit 跳过类引用释放（sweep 的 scan 负责）；主程序
收尾 `rt_gc_collect()`；容器元素为 GC 类型显式拒绝。

**后绿**：

- `cycle.x`：`main` / `node-deinit` ×2（环被回收）；
- `mixed.x`：`node-deinit helper` ×2 + `helper-deinit` ×2（deinit 时 ARC 字段有效，
  之后 sweep 释放）；
- 分配面：`rt_gc_new(&RT_TYPE_XN_Node)` + `xn_Cls_Node_scan`；非环 `Plain`
  保持 `rt_arc_new`；
- `TestBND10*` + `TestS2MEM*` 9 例 PASS；运行时六套件 exit 0。

`混合引用图 §15.6`：ARC 持 GC 为根（运行时 + 策略上指向环的类同判 GC）、
GC 持 ARC 由 sweep 释放、弱槽先清、环由 GC 回收；容器中介环未覆盖（见缺口）。

## 未做 / 转出

| 项 | 归属 |
|---|---|
| 中途收集、`xrt_safepoint`、全局根登记（SINGLE-01/ENUM-01 前置） | E5 后续卡 |
| 容器中介的引用环判定（`List<Node>` 自引用） | E2（`classRefCycle`） |
| 派生类自定义 deinit（§6.4） | E2（`TY-203`） |
| 容器元素为 GC 的扫描/释放（B2） | E4 |
| struct 端到端 codegen | E4 |
| stack 实际分配 | 后续（许可优化） |

## 复现

```bash
cd impl/runtime && sh build_rt.sh
cd impl && go test ./internal/codegen/ -run 'TestBND10|TestS2MEM' -count=1 -v
cd impl && go build -o /tmp/xnull-mem ./cmd/xnull
XNULL_RUNTIME=impl/runtime /tmp/xnull-mem build <cycle.x> -o /tmp/cycle && /tmp/cycle
```
