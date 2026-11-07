# 回执：S3-EXPR codegen 表达式补口（MEM-05/06 编译路径）

- 卡片：三处精确缺口（QA 判 MEM-05/06 编译路径红）
- 提交：`077b20c`（仅 pod/e4-codegen）
- 顺序：先红后绿（`evidence/S3-EXPR/red.log` 3 例红；`green.log` 绿）

## 一、红 → 绿

| 缺口 | 修前（红） | 修后（绿） |
|---|---|---|
| 1. 类实例实参 | `take(h.v)` → 「类实例实参只支持变量/new/调用」 | 成员表达式按字段借用直传 |
| 2. 类成员接收者 | `xs.get(0).x` → 「类成员接收者 *xfront.Call 未支持」 | 调用产物绑定临时变量后取字段（容器 get 借用，不误释放） |
| 3. Int 表达式 | `m.get("a") + m.get("b")` → 「Int 表达式 *xfront.Call 未支持」 | `Map.get` 的 `V?` 参与算术/比较时取 `.v` |

QA 复现用例（编译路径）：

```
mem05/other     6
mem06/gc_elem   5
mem06/mapset    6
```

`tests/s3/run.sh --compiled`：**PASS=11 FAIL=0**（含 mem03/mem05/mem06 全部用例）。

## 二、实现要点

- `callArgs`（codegen.go）：类类型实参新增 `*xfront.Member` 分支——用 `intExpr`
  取得字段指针，按借用直传（字段所有权仍在持有者），不新增临时释放。
- `recvCName`（classes_expr.go）：新增 `*xfront.Call` 接收者——`exprType` 判类引用，
  `classCallExpr` 求值后绑定 `t *tmp = expr;`；`owns=true` 时按 ARC/GC 策略登记释放
  （容器 `get` 为借用不释放），返回临时名继续字段链。
- `intExpr`（codegen.go）：容器 `Map.get` 在算术语境返回 `map_get(recv, key).v`
  （`V?` 的存在键取值，与解释路径一致）。

## 三、边界

- `Map.get` 的 `.v` 取值不检查缺失键（`V?` 的 null 分支）；需要缺失语义请用 `getOr`
  或先 `has`。本卡只补 QA 复现的算术/比较路径。
- 调用结果作成员接收者仅支持类引用返回；struct/元组返回的成员链仍按原范围。
- 未改动运行时与根/安全点机制（S3-02/S3-04cg 路径不受影响）。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS3_EXPR' -count=1 -v
go test ./internal/codegen/... ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
cd ..
bash tests/s3/run.sh --compiled --bin /tmp/xnull-expr
```

全绿：codegen / codegen-ffi / cli / interp / sema；S3 参考用例 11/11 PASS。
