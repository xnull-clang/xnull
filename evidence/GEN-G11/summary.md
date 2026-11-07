# G11：List<T> 元素 codegen fatal（容器局部清理早于 return 求值）

## 结论

**已修**：`return box.get(0)`（元素来自函数形参的列表字面量）不再触发
`fatal: 容器下标越界`（exit 134）。修复后两路径输出一致：`4`。

## 复现（非泛型，最小）

```x
static Int f(Int v) { List<Int> box = [v]; return box.get(0) }
static Int main() { print(f(4)); return 0 }
```

- 修复前：`xnull build` 成功，运行 `fatal: 容器下标越界`，exit 134。
- 修复后：运行输出 `4`，exit 0。

## 根因

`internal/codegen/codegen.go` 的标量 return 路径先产出表达式字符串，再执行
`emitCleanup`（本层 defer），最后 `return <表达式>;`。容器局部在声明时注册了
`xn_arr_*_free(&box)`，于是生成：

```c
xn_arr_i box = xn_t1;
xn_arr_i_free(&box);        /* len=0 */
return xn_arr_i_get(&box, 0);  /* 越界 */
```

即清理先于 return 表达式求值。

## 修法

标量 return 先把表达式求值到临时变量，再清理，最后返回临时变量：

```c
int64_t xn_t2 = xn_arr_i_get(&box, 0);
xn_arr_i_free(&box);
return xn_t2;
```

同时补 `internal/codegen/g11_test.go`（Int get / length / String get 三形态）。

## 验证

- `go test ./internal/codegen -run TestG11 -count=1` → ok
- `go test ./... -count=1` → 全绿
- 样例 `g11-forms.x`：`7 / 1 / hi`，exit 0

## 说明

泛型版本 `boxFirst<T>` 在当前分支仍报 `codegen：类型 T 未支持（M4.1 范围）`
——单态化属 B2 语言面，不在本卡；G11 的根因已确认与泛型无关（见
`收件箱/回执箱/CEO1/验收-M1-GEN-01.md`）。
