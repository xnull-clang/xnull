# 回执：S2-E4 构造器/deinit 体（第一卡）

- 卡片：S2 对象面 codegen 第一卡（`收件箱/门/S2审计-E4.md` P0 最高两项）
- 提交：`81e146e`（main）
- 范围：构造器体 + 用户 deinit 体不再静默丢弃；单继承布局（父类子对象/vtable 槽）
- 基线审计：`收件箱/门/S2审计-E4.md`（main=91c89c0）

## 一、红 → 绿

| 用例 | 修前实测（红） | 修后实测（绿） |
|---|---|---|
| `class C { Int x; C() { x = 7 } }` + `new C()` | `0`（体未执行，无诊断） | `7` |
| `class C { Int x; C(Int v) { x = v } }` + `new C(7)` | `codegen：类 C 带参构造暂未支持` | `7` |
| `class Worker(final Int id) {}` + `new Worker(5)` | 同上 | `5` |
| `void deinit() { print("bye") }` | 无 `bye`（体被跳过，无诊断） | 打印 `bye` |
| `deinit() { self.s = null }` | `codegen：String 表达式 *xfront.NullLit 未支持` | 正常清空，无重复释放 |
| `class D : Base` + 继承字段/方法 | `codegen：继承暂未支持` | `1 / 2 / 11 / 13`，deinit 链触发 |
| `class One implements V`（类内静态调用） | `codegen：协议实现暂未支持` | 编译运行 `1`；布局含 `void **__vtable;` |

回归：`go test ./internal/codegen/... -count=1` 全绿；全仓仅既有 `internal/devtool`
`TestBuildLedgerRepoGoldenScale` 红（status.tsv PASS 数与 golden 失配，非本卡）。

## 二、实现要点

- `classes.go::collectClass`：读 `Primary`/`Ctors`/`Base`/`Protocols`；父类字段前置
  （逻辑父类子对象），父类方法经 `methodOf` 链式可见；`vptr = 本类或祖先实现协议`。
- `classes.go::emitClassCtor`：分配清零 → 合并字段初值（声明顺序）→ 主构造器参数绑定
  → 构造器体；无显式构造器仍生成隐式无参构造。`new C(args)` 按实参个数选构造器
  （`classInfo::ctorByArity`）。
- `classes.go::emitClassStruct`：类型 deinit 钩子先执行本类用户 `deinit`，再沿父类链
  执行父类用户 `deinit`，最后释放仍非空的引用字段；`rt_release` 对 NULL 幂等。
- `codegen.go` `scope.self`：方法/构造器/deinit 内裸字段名（含私有 `_name`）与裸方法
  调用按 §5.8 解析到 `self`/`o`；局部/参数仍遮蔽字段。
- `classes_expr.go::methodCall`：继承方法按父类指针转型，扁平布局保证偏移一致。
- `emitFieldAssign`：`self.s = null` 走 release + NULL，不再落入 String 表达式生成。

## 三、未纳入本卡（保持审计缺口）

- 协议动态派发/槽位填充/协议类型接收者（当前仅有 vtable 槽布局）。
- `super.m()`/`super.f`、父类带参构造链、字段初始化的完整 §6.5 顺序。
- 派生类显式 `deinit` 覆写当前被 sema 以 TY-203 拒绝（§6.4 允许 deinit 链）——E2 侧。
- 结构体、枚举、静态成员、factory/singleton/extension 等（见审计 13 项）。

## 四、验证命令

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2' -count=1 -v
go test ./internal/codegen/... -count=1
```
