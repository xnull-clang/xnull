# 回执：S2-E4 PROTO-01 codegen 面

- 卡片：PROTO-01 codegen（协议变量强持有 / 只调协议方法 / 实现检查 vtable）
- 提交：`9c336de`（仅 pod/e4-codegen，未 merge main；按纪律）
- 范围：`is`/`as` 已由 E3 完成，本卡不重复。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `static P make(){ C c=new C(); return c }` + `P p=make(); p.f()` | `codegen：协议值调用 *xfront.IdentExpr 未支持` | `7`；源局部释放后协议引用仍有效 |
| 协议字段 `h.p = new C()` / `h.p.f()` | `codegen：协议接收者 *xfront.Member 未支持` | `7`；字段 deinit 释放 |
| 块内赋值 `q=c` 后再调用 | 同上 | `7`（q 强持有 c，块退出不失效） |
| 协议变量调用非协议方法 `p.g()` | codegen 显式错误（sema 已 TY-211） | 保持显式拒绝 |
| 父协议方法未实现 | — | vtable 发射兜底报错（实现检查覆盖父协议） |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1` 全绿。

## 二、实现要点

- `protoValue`：
  - 顶层函数返回协议（`Call` + `Ident`）生成调用表达式，返回值按 +1 持有；
  - 局部/字段/返回统一走强引用：`rt_retain`/`rt_release` 配对（非裸指针别名）。
- `protoRecv`：支持 `*xfront.Member` 协议接收者（`h.p.f()`、`self.p.f()`），
  经字段链取对象指针后走 vtable 槽。
- 只调协议方法：`protoDispatch` 仅按协议签名查找；非协议方法保持显式报错。
- 实现检查：`emitVtables` 递归父协议；缺失/签名不符/扩展实现均显式报错。
- 协议字段 `isProto` 属于引用字段：deinit 释放、赋值 retain/release（前卡既有，
  本卡测试覆盖强持有语义）。

## 三、边界 / E2 接口

- 弱引用语法（若后续引入）需 codegen 新表示；本卡保证协议引用为强持有，不生成
  裸指针别名。
- 协议变量可调方法集合同时由 sema（TY-211）与 codegen 兜底；父协议实现检查
  sema 主责、codegen vtable 兜底。
- 未 merge main（按纪律只提交 pod/e4-codegen）。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2PROTO01' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```
