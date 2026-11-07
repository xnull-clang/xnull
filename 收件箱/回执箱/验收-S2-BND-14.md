# 验收：S2-BND-14（负例总闸）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 已含 `4b463a7`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-14/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 交付的 19 例禁止构造矩阵 | **PASS**：19/19 rc=1、码 + 位置 |
| `final` 字段构造后二次写 | **PASS**：`TY-224` + 位置 |
| 扩展预定义类型 `extension Int` | **PASS**：`TY-225` + 位置 |
| 扩展泛型实例化 `extension Box<Int>` | **PASS**：`TY-225` + 位置 |
| `super._name` 读父类私有字段 | **PASS**：`TY-207` + 位置 |
| 批量运行无 panic / 栈回溯 | **PASS**：23/23 |
| 无「只报未实现」兜底 | **PASS**：23/23 均为具体语义诊断 |
| 不只运行期失败 | **PASS**：23/23 `check` 即 rc=1 |

**判定：PASS。** `4b463a7` 补齐了上一轮发现的 4 类缺口（`final` 二次写、extension 预定义/泛型目标、`super._name`）；加上原 19 例矩阵，23/23 全部为带码 + 位置的编译期诊断，无 panic、无静默接受、无「未实现」兜底。台账 BND-14 可登记为 PASS。

---

## 二、交付矩阵 19/19

| 用例 | 诊断 | 判定 |
|---|---|---|
| `01` protected 外部访问 | `TY-209` + 位置 | **PASS** |
| `02` `new abstract` | `TY-210` + 位置 | **PASS** |
| `03` struct 引用字段 | `TY-204` + 位置 | **PASS** |
| `04` 协议方法未实现 | `TY-208` + 位置 | **PASS** |
| `05` 枚举 switch 非穷尽 | `TY-213` + 位置 | **PASS** |
| `06` `new singleton` | `TY-216` + 位置 | **PASS** |
| `07` factory 不可见 Target | `TY-217` + 位置 | **PASS** |
| `08` 私有字段外部访问 | `TY-207` + 位置 | **PASS** |
| `09` 源码 `@arc` | `TY-201` + 位置 | **PASS** |
| `10` 静态成员用类类型参数 | `TY-214` + 位置 | **PASS** |
| `11` `private _x` | `TY-207` + 位置 | **PASS** |
| `12` 继承 `final` 类 | `TY-202` + 位置 | **PASS** |
| `13` 协议 private 方法 | `TY-205` + 位置 | **PASS** |
| `14` struct `deinit` | `TY-204` + 位置 | **PASS** |
| `15` 数据枚举字段非 final | `TY-206` + 位置 | **PASS** |
| `16` 主构造器参数非 final | `TY-212` + 位置 | **PASS** |
| `17` singleton 手写 `instance` | `TY-215` + 位置 | **PASS** |
| `18` factory 使用 `self` | `TY-221` + 位置 | **PASS** |
| `19` 数据枚举项字段写入 | `TY-218` + 位置 | **PASS** |

---

## 三、上一轮 4 类缺口复验

| 用例 | 规范要求 | 实测（check / interp / compiled） | 判定 |
|---|---|---|---|
| `20_final_field_write` `c.x=2`（`final Int x`） | 编译期拒绝 + 位置 | 三路径 rc=1；`source.x:4:6: error[TY-224]: final 字段 \`x\` 只能在声明类构造器中赋值一次（§6.1）` | **PASS** |
| `21_extension_predefined` `extension Int` | 编译期拒绝 + 位置 | 三路径 rc=1；`source.x:1:11: error[TY-225]: extension 不能扩展预定义类型 \`Int\`（§11.1）` | **PASS** |
| `22_extension_generic` `extension Box<Int>` | 编译期拒绝 + 位置 | 三路径 rc=1；`source.x:2:11: error[TY-225]: extension Target 不能写泛型实参（§11.1）` | **PASS** |
| `23_super_private` `super._x` 读父类私有字段 | 编译期拒绝 + 位置 | 三路径 rc=1；`source.x:2:39: error[TY-207]: \`super._x\` 不能访问父类 \`B\` 的私有字段（§7.4）` | **PASS** |

说明：`20`–`23` 的 `interp`/`compiled` 也在 sema 阶段被拒绝（rc=1），不再出现「check 通过、运行期才失败」或「codegen 无位置报错」。

---

## 四、批量校验

`evidence/S2-QA/QA-BND0914b/BND-14/summary.txt` 逐例校验：

- `rc=1`：23/23
- `panic=no`：23/23
- `code=yes`（含 `error[CODE]`）：23/23
- `pos=yes`（含 `file:line:col`）：23/23
- `unimpl=no`（无「暂未支持/暂不支持/未实现」兜底；`04` 的「未实现协议」为语义诊断，不计）：23/23
- `BAD` 计数：**0**

---

## 五、官方用例

| 用例 | 结果 | 说明 |
|---|---|---|
| `internal/sema/s2_bnd14_test.go:TestS2BND14NegativeMatrix` | **PASS** | 19 个子用例 |
| `internal/sema/s2_bnd0914b_test.go:TestS2BND0914b` | **PASS** | `super._x`、final 二次写、extension 目标 |
| `internal/sema/s2_ext_test.go:TestS2EXT01` | **PASS** | extension 限制矩阵 |

---

## 六、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0914b\|TestS2BND09FieldRules\|TestS2BND14NegativeMatrix\|TestPrivateFieldRules\|TestS2EXT01' -count=1` | **PASS** |
| `go test ./internal/sema -count=1` | **PASS** |
| `go vet ./internal/sema` | exit 0 |

---

## 七、证据

- 交付矩阵：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-14/01_*/`–`19_*/`
- 缺口复验：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-14/20_*/`–`23_*/`
- 汇总：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/BND-14/matrix.tsv`、`summary.txt`
- 官方用例日志：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-BND0914b/sema-targeted.log`、`sema-ext.log`、`sema-full.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §6.1、§7.4、§11.1/§11.4、§16 BND-14
