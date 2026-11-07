# S7-01 sema 接口交接（E2 → E4）

E2 已提供 FFI 调用点的 sema 面；E4 在 `sema.Analyze` 前注入 `.xfb` 投影即可。

## 1. 布局登记（layout(c)）

```go
err := sema.RegisterExternalLayout(name string, fields []sema.FFIField, cSize int)
// FFIField{Name, Type}; Type 限 S7 标量或已登记嵌套 layout
// cSize = C 侧 sizeof；sema 按 C 自然对齐计算，不一致返回 error（构建失败）
size, ok := sema.LayoutSize(name)
```

- 标量宽度：Int/UInt/Int64/Float/Double=8；Int32/UInt32/Float32/Char=4；Int16=2；Int8/Bool=1。
- 字段含 String/Bytes/Text/引用/可选/容器/数组 → error（S7 §3.3）。
- 登记后 layout 名自动加入 sema 外部类型可见集。

## 2. FFI 入口登记（调用点类型检查）

```go
err := sema.RegisterFFIEntries(
  sema.FFIEntry{
    Name: "ffiOpen",
    Params: []sema.FFIParam{
      {Name: "path", Type: "Bytes", Lease: "borrow"},
      {Name: "out",  Type: "File?", Lease: "transfer", Out: true},
    },
    Ret: "Int32",
  },
)
```

- `Type`：`Text`/`Float`/`Char`/`UInt`/`Int[]`/layout 名/`Bytes`/句柄名（句柄经 `sema.RegisterExternalTypes`）。
- `Lease`：`""`/`borrow`/`transfer`/`reclaim`；其他值登记即 error。
- `Out: true`（句柄 out 形态）：调用点实参必须是变量。
- `transfer`/`reclaim` 参数（含 Bytes）：调用点实参必须是变量（禁止临时值），所有权明确。
- `.transfer` 句柄 out 的返回类型按 E4 包装约定写 `Handle?`；sema 按普通可空类型检查。

## 3. 映射建议（.xfb → sema）

| `.xfb` | sema Type |
|---|---|
| `Text` | `Text` |
| `Bytes` | `Bytes` |
| `Float` / `Float64` / `Float32` | 同名 |
| `Char` / `UInt` / 定宽整型 | 同名 |
| `T[]`（元素标量/layout） | `T[]` |
| `layout(c) S` | `S`（先 RegisterExternalLayout） |
| `handle H` | `H`（先 RegisterExternalTypes） |

E4 仍需完成 `ffiSupported`/`ffiParamXType`/`ffiRetXType`/`ffiCallLines` 的发射；sema 不生成 C。
