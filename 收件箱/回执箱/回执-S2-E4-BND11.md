# 回执：S2-E4 BND-11（值复制 / 对象身份 / ABI）

- 卡片：BND-11（`收件箱/门/S2审计-E4.md`）
- 提交：`2758ace`（pod/e4-codegen，合入 main）
- 判据：类身份唯一、结构体复制独立、协议 vtable 仅协议槽、sret 不暴露共享身份。

## 一、红 → 绿

| 用例 | 修前（红） | 修后（绿） |
|---|---|---|
| `C a=new C(); C b=a; a==b / a===b` | `类实例局部初始值只支持 new/调用`；`===` 无指针语义，生成非法 C | `true / true` |
| `C c=new C(); a==c / a===c / a!==c` | 同上 | `false / false / true` |
| `P a=make(1)`（struct 函数返回 / sret） | `结构体值 *xfront.Call 未支持` | `a.x=1`；`b=a; b.x=9` 后 `b.x=9`、`a.x` 仍 `1`、`a.y=2` |
| `pass(a)` 值传参 + 返回 | 同上 | 副本独立，源不变 |
| 协议 vtable 槽位 | —（本次以生成 C 断言锁死） | vtable 仅 `&xn_Cls_C_f`；普通方法 `g` 不进入 vtable |

回归：`go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ -count=1` 全绿。

## 二、实现要点

- `codegen.go` `emitLocalDecl`：类局部 `C b = a` 发 `rt_retain(a)` 并登记释放，
  语义为同一对象身份（§2.8）；`new`/调用仍为 +1 产物。
- `codegen.go` `intExpr`：`===` / `!==` 对类指针、协议类型、数据枚举、句柄、
  Bytes 落 C 指针 `==`/`!=`（S2 §2.8/§5.6）；`types.go` 将 `===`/`!==` 归为 Bool。
- `struct.go` `structValue`：支持顶层函数/自身方法返回 struct；C 结构体按值返回
  （编译器 sret ABI），调用方持有独立副本，不暴露内部地址/共享身份（§3.6）。
- 协议 vtable：全局槽位只来自协议签名；普通类方法/静态方法/构造器/deinit/
  扩展方法不进入 vtable（§5.7）。测试用生成 C 断言。

## 三、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND11' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ -count=1
```

## 四、边界

- struct 可空值字段、struct 进入容器/数组/泛型实参（mangle 未扩）。
- 类身份跨策略（ARC/GC）由 E5 MEM-01/02 覆盖；ABI 稳定槽位跨模块属后续卡。
