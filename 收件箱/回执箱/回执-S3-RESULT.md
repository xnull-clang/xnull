# 回执：S3-RESULT Result 表达式补口（MEM-07/13 编译路径）

- 卡片：Result 变量复制 / Ok/Err 作字段初始化式与表达式（内联值语义）
- 提交：`cb0dc0c`（仅 pod/e4-codegen）
- 顺序：先红后绿（`evidence/S3-RESULT/red.log` 3 例红；`green.log` 绿）
- 复现输入：`evidence/S3-RESULT/repro-copy.x`、`repro-field.x`
  （`tests/s3/mem07/` 在当前分支尚不存在，QA 后续补入时用等价用例）

## 一、红 → 绿

| 缺口 | 修前（红） | 修后（绿） |
|---|---|---|
| `Result<Int,String> b = a` | 「Result 表达式 *xfront.IdentExpr 未支持（M4.1）」 | 内联结构体整值复制 |
| `class C { Result<Int,String> r = Ok(5) }` | 「Int 表达式 *xfront.Call 未支持（M4.1）」 | 字段初始化式直接生成内联 Result 初值 |
| `c.r.unwrapOr(0)` / `c.e.isErr()` | 字段 receiver 走 Int 表达式报错 | 字段链 receiver 支持 Result 成员 |
| `c.r = Ok(7)` / 构造器内 `self.copy = self.r` | 无路径 | 字段赋值/自字段复制按值语义 |

`go test ./internal/codegen/ -run TestS3_RESULT -count=1 -v`：3/3 PASS。
`tests/s3/run.sh --compiled`：PASS=11 FAIL=0（回归保持）。

## 二、实现要点

- `resultExpr`：
  - `IdentExpr`：局部/顶层字段 Result 复制 → `(变量)`（C 结构体整值复制）；
  - `Member`：字段上的 Result 复制；
  - `Paren` 透传；既有 Ok/Err/函数返回/类方法路径不变。
- `collectAllResults`：补扫类/结构体/枚举/单例的**字段类型**，保证
  `xn_Result_*` typedef 先于类结构体出现（字段 Result 的内联布局）。
- `emitLocalDecl`：Result 声明统一走 `resultExpr`（不再只认 Int/Bool 两种组合），
  保留 `try` 解包路径。
- `emitAssign` / `callArgs` / `fieldInitValue` / `emitFieldAssign`：Result 局部赋值、
  Result 实参、字段初始化式、字段赋值全部走 `resultExpr`。
- `intExpr`：Result 成员（isOk/isErr/value/unwrapOr）支持字段链 receiver。

## 三、语义边界

- Result 仍是内联值结构（`{ int ok; V v; rt_string *err; }`），无堆盒身份、无 GC
  分配；复制即 C 结构体复制，符合 v3.1.0「已内联值结构」口径。
- `Err` 的 message 为 String（现为 GC），复制共享同一指针；内联值语义下不额外计数。
- 顶层字段仍不支持 Result（ENTRY-01 范围）；`Result` 裸类型（无实参）由 sema 拒绝，
  本卡未放宽。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS3_RESULT' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
cd .. && bash tests/s3/run.sh --compiled --bin /tmp/xnull-res2
```

全绿（codegen / codegen-ffi / cli / interp / sema；S3 参考用例 11/11 PASS）。
