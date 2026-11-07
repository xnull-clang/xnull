# S2-E5-BND10：策略 → 运行时行为（BND-10）

- 卡片：BND-10（§15.1 判定表决定分配；混合引用图 §15.6）
- 依据：S2 §2.7/§15.1/§15.6；S3 §8/§15.6/§188；`impl/docs/runtime-contract.md` P-09
- 基线：`main=fa6d821`；上一卡（MEM-01/02）`9e90d4e`
- 结论：**引用环类按策略分配为 GC，退出时收集；非环类保持 ARC；混合图 deinit/释放顺序正确**

## 先红（BND-10 前）

同一 `cycle.x`（`Node { Node next }` 自引用环 + deinit 打印）在卡 1 提交
`9e90d4e` 上构建：策略已判定 `gc`，但 codegen 仍 `rt_arc_new`，ARC 环永不
归零 → 退出时 deinit 不执行，环泄漏：

```
main
exit=0
```

生成 C：`xn_Cls_Node *o = rt_arc_new(&RT_TYPE_XN_Node);`（`red-cycle.log`）。

## 实现（`impl/internal/codegen`）

1. `build.go`：`sema.AnalyzeWith` 取 `Result`，把 `Strategies(u)` 传给新入口
   `EmitCWithStrategies`；`EmitCWithFFI` 保持兼容（策略为空 = 全 ARC）。
2. `classes.go`：
   - `classInfo.isGC = policy[Name]=="gc"`；`classField.isGC`（字段类型为 GC 类）。
   - 分配：GC 类 `rt_gc_new`，其余 `rt_arc_new`。
   - 描述符 `scan`：GC 类访问全部类引用字段（sweep 释放 ARC 引用 / 标记 GC 引用）；
     ARC 类只访问其中的 GC 引用（作为 GC 根）。
   - `deinit_hook`：GC 类不再 `rt_release` 类引用字段（ARC 引用由 sweep 的 scan 释放）；
     String/handle/Bytes 与容器仍在此释放；ARC 类跳过 GC 类引用字段。
3. 所有权：GC 类局部不登记 release；局部/字段/返回值/实参对 GC 引用不做
   `rt_retain`/`rt_release`（GC 引用不计数的合同，§15.6.1）。
4. 主程序收尾：`rt_gc_collect()` 后 `rt_quarantine_flush()`。
5. 显式拒绝：容器元素为 GC 类型（`List/Set/Map`）报错，不静默生成错代码。

## 后绿

```
# cycle.x
main
node-deinit
node-deinit
exit=0

# mixed.x（GC 持 ARC：Node 环 + Helper）
main
node-deinit helper
helper-deinit
node-deinit helper
helper-deinit
exit=0
```

- 分配面：`rt_gc_new(&RT_TYPE_XN_Node)` + `xn_Cls_Node_scan`；
  非环 `Plain` 保持 `rt_arc_new`（`green-generated-c.txt`）。
- `TestBND10*` + `TestS2MEM*` 共 9 例 PASS（`tests.log`）。
- 运行时六套件 exit 0（`build_rt.log`）。

## 边界与未做

| 项 | 状态 | 说明 |
|---|---|---|
| 中途收集 / 安全点 | **未做** | 生成程序只在退出时收集；无 `xrt_safepoint` 调用点，因此不会误回收活跃对象 |
| 全局根登记 | **未做** | 无 GC 顶层/单例；`xrt_register_root` 仍无调用者（SINGLE-01 前置） |
| 容器元素为 GC | **显式拒绝** | 值结构容器需元素级扫描/释放策略，归 B2 引用语义容器 |
| ARC→GC（ARC 持有 GC） | **策略上不出现** | 指向环的类本身也被判定 GC；ARC→GC 仅在容器/全局面出现（未支持） |
| stack 分配 | **未做** | stack-eligible 仍 ARC（§2.7 许可优化，语义不变） |
| 继承链 GC | **按类各自策略** | 派生类扫描/释放含父类字段；混合策略（父 ARC/子 GC）按字段类型逐项处理 |

## 复现

```bash
cd impl && go build -o /tmp/xnull-mem ./cmd/xnull
XNULL_RUNTIME=impl/runtime /tmp/xnull-mem build cycle.x -o cycle && ./cycle
cd impl && go test ./internal/codegen/ -run 'TestBND10|TestS2MEM' -count=1 -v
```
