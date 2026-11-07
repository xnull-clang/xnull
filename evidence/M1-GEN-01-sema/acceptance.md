# GEN-01 sema 半边验收（M1 小时制）

> 主责：CEO1-RD2　会签：CEO1-QA2（独立用例不得复用本表期望）
> 分支：`pod/c1-rd2`　基线：`09367e8`（ERR-01）→ DET/TYPE 修复之后
> 红源：`pod/c1-rd3` `evidence/M1-GEN-01/before/go-test-gen01-before.log`（TestGEN01：24 FAIL / 1 SKIP / 1 PASS，全部卡在 sema 先以 TY-101 拒绝）

## 一、结论

- sema 半边 26 项：**21 项全绿**、4 项半绿（跨域）、1 项不可测（G12）。
- 新增诊断码：`GEN-101`（显式实参）、`GEN-102`（推断冲突/未绑定）、`GEN-103`（重载歧义/零候选）、`GEN-104`（作用域/new T/无限展开）。
- 契约：推断成功后把最终类型实参写回 `Call.TypeArgs`（`TestGEN01WritesBackTypeArgs`），codegen 侧按 c1-rd3 的 `generics.go` 消费，合并即接线。
- 未改既有测试期望；sema/interp/codegen 示例/`go test ./...`/vet/gofmt 全部 rc=0。

## 二、26 项逐项

图例：`[x]` sema 半边达标｜`[~]` 半绿（跨域/边界）｜`[!]` 不可测

### 台账 8 项

- [x] **G1a** 显式实参 `identity<Int>(7)`：sema 写回/替换，`TestGEN01SemaAccept/G1a`
- [x] **G1b** 显式实参数量一致：`GEN-101`，`TestGEN01SemaReject/G1b`
- [x] **G2a** 直接推断：`TestGEN01SemaAccept/G2a`
- [x] **G2b** 嵌套 `List<T>` 推断：`TestGEN01SemaAccept/G2b`
- [x] **G2c** 无后缀字面量绑定 `Int` / 适配已绑定 `T`（`pick(1L, 2)`）：两个 accept 用例
- [x] **G2d** 返回类型不参与推断：`GEN-102 未绑定`，Reject/G2d
- [x] **G3** 冲突绑定：`GEN-102 冲突`，Reject/G3
- [~] **G4** 未绑定类型参数：单参数形态已测（Reject/G4）；`firstOf<T,U>` 多参数仍被 xfront B1 阻断
- [x] **G5a** 重载·唯一候选：普通同名函数优先（§8.2/codegen 同口径），Accept/G5a
- [x] **G5b** 重载·歧义：sema 已实现候选集与 `GEN-103`，自测「两个同元数泛型候选」通过；**c1-rd3 原用例把第二个候选写成 `pick2`，该用例本身不构成歧义**，需 QA 重写
- [x] **G5c** 重载·零候选：`GEN-103` 消息含「实参」，Reject/G5c
- [x] **G6a** 两个类型实参各自实例：写回两次 TypeArgs，Accept/G6a
- [x] **G6b** 实例内按具体类型检查输入：`count(List<Int>)` / `count(List<String>)` 各自推断，Accept/G6b（实例发射属 codegen）
- [~] **G7** 无限展开：**直接自递归**（`loop<T>`）报 `GEN-104 展开`；互递归深度上限仍由 codegen `maxInstDepth=64` 兜底
- [x] **G8** `Result` 类型实参可实例化：`unwrapOr<T>(Result<T,String>, T)`，Accept/G8

### S1 §8 补充 12 项

- [x] **G9** 类型参数作用域外不可见：`RES-101 未定义`，Reject/G9（`typeParamNames` 全单元登记 + 当前作用域白名单）
- [~] **G10** 类型参数不得重名：解析层已拒绝（SYN-101，B1）；sema 侧另加防御性 `RES-102`，但多参数声明当前进不到 sema
- [x] **G11** 类型参数用于局部/嵌套：`T local` + `List<T> box`，Accept/G11
- [!] **G12** 泛型函数不能作为值：语言无函数值/闭包值语法，条款不可表达（同 c1-rd3 判定）
- [x] **G13** 类型参数不能是 void：`GEN-101`，Reject/G13
- [x] **G14** 泛型内 `is T`/`as T`：`is Int` 用例通过；`as T` 由替换后的 Concrete 类型检查（Accept/G14）
- [x] **G15** 泛型内不能 `new T()`：`GEN-104`，Reject/G15
- [~] **G16** 跨文件模板可见：sema 对 `LoadUnits` 合并后的同一编译单元无文件边界；跨文件用例需合并 c1-rd3 后跑 `TestGEN01CrossFile`
- [x] **G17** 类型约束必须拒绝：解析层拒绝（诊断质量由 xfront 整改，不由 sema 决定）
- [x] **G18** 泛型与普通同名函数共存：普通优先 + 泛型推断，Accept/G18
- [x] **G19** `null` 实参不能定 `T`：`GEN-102` 消息含「null/未绑定」，Reject/G19

## 三、红→绿与回归

| 项 | 结果 | 文件 |
|---|---|---|
| 红（c1-rd3） | TestGEN01 24 FAIL / 1 SKIP / 1 PASS | `before/gen01-before.log` |
| 绿（本域） | `TestGEN01SemaAccept` 12/12、`TestGEN01SemaReject` 12/12、`TestGEN01WritesBackTypeArgs` PASS | `after/gen01.log`（exit 0） |
| sema 全量 | rc=0 | `after/sema-full.log` |
| interp 全量 | rc=0 | `after/interp.log` |
| 示例双路径 | 9/9 PASS | `after/codegen-examples.log` |
| 全仓 | `go test ./...` rc=0 | `after/go-all.log` |
| 静态 | vet rc=0；gofmt 无输出 | `after/vet.log`、`after/gofmt.log` |

## 四、跨域未闭合（不隐瞒）

| 编号 | 域 | 影响 | 状态 |
|---|---|---|---|
| B1 | xfront | `<T,U>` 多类型参数不解析（`genericParamsFollows` 把 Comma 当非法） | 不在本卡 |
| B1b | xfront | 嵌套实参 `>>` 被当比较/移位 | 不在本卡（用例用空格 `> >` 规避） |
| B3 | interp | 零泛型执行；泛型用例无法双路径 | 不在本卡（codegen 侧由 c1-rd3 覆盖） |
| 合并 | c1-rd2 × c1-rd3 | sema 写回 TypeArgs + codegen 实例发射需同批合入 | 待 CEO2 排合并 |
