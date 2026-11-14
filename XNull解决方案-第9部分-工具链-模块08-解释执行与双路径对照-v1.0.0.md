# XNull 解决方案 第 9 部分：工具链（模块 08：解释执行与双路径对照）

> 本文是第 9 部分模块 08，只落实第 1、2、4 部分已定义的源码可观察语义；解释器不模拟正式运行时内存时序；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 9 部分（T9） |
| 模块 | 08 解释执行与双路径对照 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 9 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 1、2、4 部分 |
| 组件 | tree-walking 解释执行：值模型、作用域、控制流、对象/容器/闭包、与编译路径的对照 |
| 上游输入 | `xfront.CompilationUnit`、命令行参数、语义检查结果（由 CLI 先执行） |
| 下游输出 | stdout、退出码、运行期错误 |
| 明确不含 | 编译器（模块 01）、C 运行时（模块 03）、FFI 合同层（模块 05）、工程构建（模块 06）、诊断渲染（模块 07） |
| 配套文档 | 第 9 部分总览；模块 01、02、07 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。定义解释器值模型、控制流、对象/容器语义与双路径对照边界。 |

---

## 0. 定位与边界

### 0.1 定位

解释器是 `xnull run --interp` 的执行路径，也是编译路径的**对照 oracle**：

- 与编译器共享 `xfront` AST 与 `sema` 检查；
- 直接执行 AST，不生成 C；
- 用于快速调试、行为对照、错误定位；
- 不模拟 ARC/GC 时序，不承担正式运行时职责。

```
.x 源文件
  → LoadUnits
  → sema.Analyze（CLI 先执行）
  → interp.Run（tree-walking）
  → stdout + 退出码
```

### 0.2 边界

| 属于解释器 | 不属于解释器 |
| --- | --- |
| AST 求值、作用域、控制流 | 词法/语法/语义检查（前端/语义） |
| `Result`/`try`/`defer`/`errdefer` 执行 | ARC/GC 时序、终结链 |
| 对象/容器/闭包运行值 | 正式运行时对象布局/FFI ABI |
| 调试输出与退出码 | 工程构建/产物 |

### 0.3 与编译路径的关系

- 输入同一 `CompilationUnit`；
- 语义检查由同一 `sema` 完成；
- 对照合同：同一程序 stdout 与退出码逐字节一致；
- 不对内存时序、对象地址、终结时机做对照；
- 解释器更宽松的运行时分支不能替代语义检查。

---

## 1. 值模型

### 1.1 值种类

```go
type valKind int

const (
    vNull
    vBool
    vInt
    vFloat
    vChar
    vStr
    vResult
    vArr
    vList
    vMap
    vSet
    vTuple
    vClosure
    vObj
)
```

### 1.2 `Value`

```go
type Value struct {
    K   valKind
    B   bool
    I   int64
    F   float64
    C   rune
    S   string
    R   *resv
    A   []*Value
    M   *mapv
    Clo *clov
    O   *objv
}
```

- 统一值结构，按 `K` 解释字段；
- 标量/字符串直接存；
- 容器/元组用 `A` 切片；
- Map 用 `mapv`；
- 闭包用 `clov`；
- 对象用 `objv`。

### 1.3 Result 值

```go
type resv struct {
    ok bool
    v  *Value
    e  *Value
}
```

- `ok=true` 表示 `Ok`；
- `ok=false` 表示 `Err`；
- `E` 的完整类型检查在语义层；
- 运行期不暴露盒身份。

### 1.4 打印格式

`format(v)` 是 `print` 与字符串插值共用的确定性格式：

- `null`、`true`/`false`、整数、浮点、字符、字符串；
- 数组/List/Set/Map/元组按固定格式；
- Map 按规范化键排序；
- 不依赖 Go map 遍历顺序。

---

## 2. 作用域

### 2.1 `scope`

```go
type scope struct {
    parent *scope
    vars   map[string]*Value
}
```

操作：

- `lookup`：沿父链查找；
- `define`：当前作用域定义；
- `assign`：沿父链赋值。

### 2.2 作用域层级

- 全局作用域：顶层字段、函数/类登记；
- 函数作用域：参数、局部变量；
- 块作用域：if/while/for/switch/defer 体；
- 闭包环境：创建时捕获的作用域。

### 2.3 顶层初始化

`Run`：

1. 登记顶层函数（支持重载）；
2. 登记类；
3. 按声明顺序初始化顶层字段（零值或初值）；
4. 查找 `main`；
5. 校验入口签名；
6. 调用 `main`。

入口形态：

- `static void main()`；
- `static Int main()`；
- `static void main(String[])` / `static Int main(String[])`（目标态）。

退出码：

| 情形 | 退出码 |
| --- | --- |
| `void main` 正常返回 | 0 |
| `Int main` 返回 | 返回值原样 |
| `throw`/fatal | 134 |
| 解释器不支持/运行错误 | 1 |
| 无 `main`/重复 `main`/签名错误 | 1 |

---

## 3. 控制流

### 3.1 信号

解释器用 panic/recover 传递控制信号：

| 信号 | 含义 |
| --- | --- |
| `ctrlReturn` | 函数返回 |
| `ctrlErr` | `try` 传播错误 |
| `ctrlBreak` | break（可带标签） |
| `ctrlContinue` | continue（可带标签） |
| `fatal` | `throw`/致命错误 |
| `runtimeErr` | 解释器运行错误 |

### 3.2 语句

| 语句 | 行为 |
| --- | --- |
| 空语句 | 无操作 |
| 表达式语句 | 求值 |
| 局部声明 | 零值/初值 + 定义 |
| 赋值 | `=` 或复合赋值 |
| 自增/自减 | 读 → 加减 1 → 写 |
| return | 求值 → `ctrlReturn` |
| throw | 求值 → `fatal` |
| if/else | 条件 + 块作用域 |
| while/do-while | 条件循环 + 标签 |
| for-in | 区间或容器 |
| switch | 首个匹配 case，无隐式贯穿 |
| defer/errdefer | 注册清理项 |
| break/continue | 信号，标签匹配 |
| labeled | 设置当前标签 |
| goto | **当前不支持**；报运行错误 |
| block | 新作用域 + 块级 defer |

### 3.3 `for-in`

支持：

- 区间 `a..<b` / `a...b`；
- `T[]`、`List<T>`、`Set<T>`；
- Map 不能直接遍历，必须先取 `keys()`/`values()`。

### 3.4 `switch`

- 按源码顺序求值 case；
- 首个匹配执行；
- 无隐式贯穿；
- `break` 退出 switch；
- `default` 最后；
- 子句独立作用域。

### 3.5 标签

- `labeled` 设置当前循环标签；
- `break`/`continue` 匹配最近层或同名标签；
- 不匹配的信号继续向上传播；
- 标签只属于紧随其后的循环层。

---

## 4. `Result` / `try` / 清理

### 4.1 `Ok` / `Err`

- `Ok(v)` → `Result{ok:true, v}`；
- `Err(e)` → `Result{ok:false, e}`；
- 类型/参数检查由语义层完成。

### 4.2 `try`

```
try expr:
  求值 expr
  必须是 Result
  ok → 返回 value
  err → ctrlErr 传播
```

- `ctrlErr` 到函数边界 → 返回 `Err`；
- `try` 只作用于 `Result`；
- 传播路径执行 `defer` 与 `errdefer`。

### 4.3 `defer` / `errdefer`

- 每个块维护 `defers` 栈；
- 注册项 `{fn, errdef}`；
- 块退出时逆序执行（LIFO）；
- `errdefer` 仅在错误路径执行；
- 返回 `Err` / `try` 传播 → 错误路径；
- 普通块退出/正常返回 → 只执行 `defer`；
- `fatal`/运行错误 → 不执行任何清理；
- 清理体内禁止 `return`/`break`/`continue`/`try`，运行期检测到即报错。

### 4.4 `throw`

- 求值消息；
- `fatal` 信号；
- 不执行 defer/errdefer；
- 退出码 134。

---

## 5. 对象

### 5.1 `objv`

```go
type objv struct {
    cls    *xfront.ClassDecl
    fields map[string]*Value
    order  []string
}
```

- 字段按声明序保存，保证输出确定性；
- 类声明指向 AST；
- 对象由 Go GC 托管；
- **不模拟 ARC/GC 时序**；
- `deinit` 不自动触发；
- 双路径只对照 stdout/退出码。

### 5.2 构造

`evalNew`：

1. 查找类；
2. 按基类到子类登记字段，零值；
3. 主构造器参数绑定同名字段；
4. 按声明序求字段初值；
5. 主构造器已绑定字段以参数为准；
6. 无带参构造器时传参报错。

### 5.3 方法/字段

- `findMethod` 沿基类链查找；
- `findField` 查字段声明；
- 方法调用绑定 `self`；
- 协议分派按对象实际类的方法名解析；
- 继承按基类链查找；
- `self` 在实例作用域可见。

### 5.4 限制

- 字段查找的完整继承边界以语义/运行期实现为准；
- 对象生命周期不模拟 ARC；
- 不执行用户 `deinit`；
- 协议 vtable 不是解释器关注点；
- 对象地址/身份不暴露给源码。

---

## 6. 容器

### 6.1 数组/List/Set

- `T[]` 固定长度数组；
- `List<T>` 与数组共享 `vArr` 表示；
- `Set<T>` 用 `vArr` 去重；
- 元素按插入顺序；
- 容量/扩容是实现细节。

### 6.2 Map

```go
type mapv struct {
    keys []string
    vals map[string]*Value
    disp map[string]*Value
}
```

- 键规范化为带类型前缀的字符串；
- `keys` 保持升序（DET-01）；
- `keys()`/`values()`/打印按排序；
- 只允许 Int/String 键（简单枚举目标态）；
- Map 不能直接 for-in。

### 6.3 元组

- `vTuple` + `A` 切片；
- 值语义：复制切片，引用元素仍共享句柄；
- 位置访问 `t.0`/`t.1`；
- 越界报错。

### 6.4 容器成员

解释器支持内建容器/String/Result 的成员方法：

- 数组/List：`length/get/set/push/remove/clear` 等；
- Set：`add/has/remove/at/length/clear`；
- Map：`get/getOr/has/put/remove/clear/length/keys/values`；
- String：`length/indexOf/substring/trim/replace/toUpper/toLower/split/startsWith/endsWith`；
- Result：`isOk/isErr/value/error/unwrapOr`。

具体方法面以语义检查后的调用为准；未定义成员报运行错误。

---

## 7. 函数与闭包

### 7.1 顶层函数

- `Interp.funcs` 按名称保存重载列表；
- `selectFunc` 按参数个数/类型选择；
- 无匹配 → 运行错误；
- 顶层函数可作值传递（包装为闭包）。

### 7.2 Lambda

- 捕获创建时作用域；
- 参数类型显式；
- 支持块体/表达式体；
- 调用时新建作用域，参数绑定；
- 返回 `ctrlReturn` 恢复。

### 7.3 具名函数作为值

`IdentExpr` 引用顶层函数时包装为 `clov{top: name}`；调用时走顶层函数选择逻辑。

---

## 8. 内建与类型运算

### 8.1 内建

| 名称 | 行为 |
| --- | --- |
| `print(x)` | 按静态/运行类型格式化并输出换行 |
| `str(x)` | 格式化为字符串 |
| `Ok`/`Err` | 语言构造器，不是普通函数 |

### 8.2 `is` / `as` / `as?`

- `is`：类型匹配返回 Bool；
- `as`：失败 fatal；
- `as?`：失败返回 null；
- 类型匹配按 `typeMatches` 检查标量/数组/对象/Result 等。

### 8.3 算术/比较

- 整数/浮点算术；
- 比较/相等/恒等；
- 逻辑短路；
- `??` 空值合并；
- 字符串拼接/插值；
- 整数溢出按 Int64 回绕（运行值）；
- 浮点格式按解释器确定性规则。

---

## 9. 双路径一致性

### 9.1 对照范围

| 项 | 是否对照 |
| --- | --- |
| stdout | 是，逐字节 |
| 退出码 | 是 |
| 诊断（语义/语法） | 共享同一前端/语义 |
| 内存时序/终结 | 否 |
| 对象地址/身份 | 否 |
| 性能 | 否 |

### 9.2 前提

- 同一 `CompilationUnit`；
- 同一 `sema` 检查；
- 同一入口签名/参数；
- 同一 stdout writer；
- 同一运行参数。

### 9.3 差异处理

- 解释器不支持而编译路径支持的构造：显式报错；
- 解释器更宽松的运行期分支：语义检查应提前拒绝；
- 发现差异先修语义/前端，不靠解释器“猜”。

---

## 10. 确定性与输出

- Map 键排序；
- 容器遍历按元素顺序；
- 顶层字段按声明顺序；
- 对象字段按声明顺序；
- 打印格式固定；
- 不使用 Go map 遍历输出；
- 同一程序多次运行输出一致。

### 10.1 已知风险

- Go map 若被直接遍历会引入随机顺序；当前 Map 值使用排序键；
- 浮点格式依赖 Go `strconv` 规则，需与编译路径对齐；
- 字符串插值/容器格式化必须与代码生成格式一致；
- 解释器的运行时宽松分支不得掩盖语义错误。

---

## 11. 运行期错误

| 情形 | 行为 |
| --- | --- |
| 未定义名称 | `runtimeErr`，退出 1 |
| 类型/操作数非法 | `runtimeErr`，退出 1 |
| 除零 | `runtimeErr`，退出 1 |
| 下标越界 | `runtimeErr`，退出 1 |
| 空引用调用 | `runtimeErr`，退出 1 |
| `try` 非 Result | `runtimeErr`，退出 1 |
| `throw` | `fatal`，退出 134 |
| `defer` 内控制转移 | `runtimeErr`，退出 1 |
| `goto` | `runtimeErr`，退出 1 |
| 不支持的语句/表达式 | `runtimeErr`，退出 1 |

说明：

- 解释器的 fatal 打印格式由 CLI 输出；
- 不执行 defer；
- 不进行 ARC/GC 终结；
- 运行错误是调试路径行为，不代表正式运行时语义。

---

## 12. 接口

```go
func Run(u *xfront.CompilationUnit, out io.Writer, progArgs []string) (code int, err error)
```

输入：

- `CompilationUnit`：已解析、已语义检查；
- `out`：stdout writer；
- `progArgs`：传给 `main(String[])` 的参数（目标态）。

输出：

- `code`：0/1/134 或 `Int main` 返回值；
- `err`：运行错误文本（由 CLI 写 stderr）。

---

## 13. 验证

| 测试 | 覆盖 |
| --- | --- |
| `interp_test.go` | 语句/表达式/控制流/入口/双路径 |
| `values_test.go` | 容器/元组/闭包/类型运算 |
| `hard_test.go` | throw 不展开栈、defer LIFO、errdefer、try 传播 |
| `TestDeterminismByteIdentical` | 多次运行逐字节一致 |
| `cli_test.go` | `--interp` 分派与退出码 |
| 示例对照 | hello/result-try/defer-cleanup/classes/containers/multi 等 |

关键断言：

- `defer` LIFO；
- `errdefer` 只在错误路径；
- `throw` 不执行清理；
- `try` 传播到函数边界；
- `Int main` 退出码；
- Map 输出排序；
- 同一程序输出一致。

---

## 14. 边界

| 能力 | 说明 |
| --- | --- |
| ARC/GC 时序 | 不模拟 |
| `deinit` | 不自动执行 |
| `goto` | 当前不支持 |
| 元组/闭包/对象 | 支持解释执行，但不代表代码生成已支持 |
| 泛型/协议完整面 | 依赖语义与运行期实现 |
| 性能 | 非目标 |
| 跨 FFI 调用 | 调试路径不承诺 |
| 任务/并发 | 调试路径不承诺；并发语义归任务运行时 |

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 1 部分 §10、§11 | `Result`/`try`/`defer`/`throw` 语法与入口 |
| 第 2 部分 §1—§15 | 对象、类、协议、枚举、容器、闭包的可观察语义 |
| 第 4 部分 §7.2 | 程序退出码映射 |
| 第 3 部分 §17 | 清理责任模型（解释器只执行源码可见清理，不模拟终结） |

### 实现选择

- Go 值模型与 `Value` 结构；
- panic/recover 控制信号；
- Go GC 托管对象；
- Map 键规范化与排序；
- 解释器不支持的 `goto` 等边界；
- 调试路径的退出码/输出实现。

以上为实现选择，不新增语言语义；解释器只执行第 1、2、4 部分已定义的源码可观察行为，不模拟正式运行时内存时序。

## 15. 参考

- `impl/internal/interp/interp.go`
- `impl/internal/interp/values.go`
- `impl/internal/interp/objects.go`
- `impl/internal/interp/hard_test.go`
- `impl/internal/interp/interp_test.go`
- `impl/internal/interp/values_test.go`
- `XNull解决方案-第1部分-基础语法-v3.4.0.md` §10
- `XNull解决方案-第4部分-错误处理-v1.1.0.md` §5.2
