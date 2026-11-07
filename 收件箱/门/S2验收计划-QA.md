# S2 验收计划（QA1 独立）

> **版本**：v0.1（启动版）　**日期**：2026-11-07
> **范围**：Stage 2 / S2 对象编程，台账 29 锚点（15 个 BND + 14 个 §18 锚点）
> **性质**：验收计划与黄金用例矩阵；**尚未执行验收**，不构成任何 PASS 结论
> **被测规范**：`XNull解决方案-第2部分-对象编程-v3.3.0.md`（§16 实现边界、§18 验收）
> **台账**：`XNull一致性用例台账-v1.0.0.md`；旁表 `impl/docs/conformance/status.tsv`

---

## 0. 先给结论

1. **S2 当前不具备开验条件**：29 锚点中仅 2 个 `PASS`（INH-01、FIELD-01），且这两个只有 sema 级用例；5 个 `部分`（STRUCT-01、PROTO-01、ENUM-01、MEM-01、MEM-02）；22 个 `未实现`。
2. **零用例锚点 22 个**：15 个 BND 全部无 BND 专项用例；DISP-01、PCTOR-01、INT-01、SINGLE-01、EXT-01、ANN-01、GATE-01 无实现/无用例。  
   注：BND-04/05/06/09 与 STRUCT-01/PROTO-01/ENUM-01/FIELD-01 的部分 sema 用例重叠，但 BND 要求成员级、跨包、负例矩阵，现有用例不能替代。
3. **S2 的运行时/编译路径基本空白**：现有测试集中在 `internal/sema/typedecl_test.go` 与 `policy_test.go`；`internal/interp` 只有 `examples/classes.x`、`examples/objlist.x` 两个基础类示例；`internal/codegen` 只有字段初始化用例，无继承派发、协议 vtable、factory、singleton、extension、annotation 用例。
4. **先列缺口**见 §1；黄金用例矩阵见 §2；独立验收执行计划见 §3。
5. **两个口径必须先冻结**：
   - **D-02：S2 分母 29 还是 35？** 台账 29 = 15 BND + 14 条 §18；规范 §18 实为 20 条，缺 `TYPE-01`、`FACTORY-01`、`GEN-01`、`TUPLE-01`、`NEG-01`、`DET-01` 六条（附录 B）。按 29 判会漏验工厂类型、S2 元组内存与 S2 确定性。
   - **D-04：诊断码表未交付前，“诊断码触发 100%”不可判 PASS**；只能判“不具备判定条件”。
6. 本计划不写生产代码；QA 只建用例、夹具、执行器与证据。

---

## 1. 先列缺口（本轮要补哪些用例）

### 1.1 零用例锚点（22 个，全部需要从 0 建例）

| # | 锚点 | 条款 | 最低用例数 | 缺什么 |
|---:|---|---|---:|---|
| 1 | BND-01 | §7.3/§16 | 6 | 成员级 public/protected/private 同包/跨包矩阵；跨包顶层+成员规则；具体诊断码 |
| 2 | BND-02 | §2.5/§5.1/§16 | 5 | abstract 实例化、继承 final、子类同签名、字段隐藏、多级继承复用 |
| 3 | BND-03 | §5.6–5.7/§16 | 6 | 类接收者静态派发、协议 vtable、策略不影响 vtable、构造/deinit/super 静态 |
| 4 | BND-04 | §3.2/§16 | 4 | struct 值字段复制独立性、捕获 self、非值泛型字段实参、跨包 struct |
| 5 | BND-05 | §4/§16 | 6 | 默认实现、关联类型、泛型协议方法、约束、父协议实现检查、协议变量强持有 |
| 6 | BND-06 | §8.5/§16 | 6 | 穷尽性、非穷尽、重复项、未知项、default 位置、枚举 implements protocol |
| 7 | BND-07 | §9.4/§16 | 5 | instance 只读、无 new、不继承/不实现协议、启动前初始化、前向引用 |
| 8 | BND-08 | §10/§16 | 6 | 同包私有构造器、跨包公开成员、不可见 Target、泛型裸名/返回约束/非类型使用/非法声明 |
| 9 | BND-09 | §7.4/§16 | 4 | 跨包私有字段、protected 子类访问、继承链基名唯一、字段隐藏 |
| 10 | BND-10 | §15.1/15.6/§16 | 5 | 判定表边界、@arc/@gc 拒绝、stack/ARC/GC 行为、混合图不变量 |
| 11 | BND-11 | §3.3/§5.7/§15.3/§16 | 4 | struct 值复制、类身份不被优化改变、vtable 只含协议槽、地址+sret ABI |
| 12 | BND-12 | §13.4/§16 | 3 | 单态化先于内存分析、残留 T、泛型协议、泛型 struct 非值实参 |
| 13 | BND-13 | §11/§16 | 5 | 同包非泛型目标、只加方法、不进 vtable、重复/同签名、协议实现违规 |
| 14 | BND-14 | §16 | 3 | 全禁止构造负例矩阵、带位置诊断、不崩溃/不静默/不只运行期失败 |
| 15 | BND-15 | §16 + S1 §10 | 4 | Result/try/defer + 对象、new T[count]、标签控制、枚举穷尽集成 |
| 16 | DISP-01 | §5.6–5.7 | 5 | 类静态得 1、协议动态得 2、策略不影响、super 静态、构造/deinit |
| 17 | PCTOR-01 | §6.3 | 5 | 头部参数绑定字段、super 后声明序、final 恰好一次、与非主构造器混用拒绝 |
| 18 | INT-01 | §18 + S1 §10 | 4 | Result/try/defer + class、+ factory、枚举穷尽、清理/deinit |
| 19 | SINGLE-01 | §9 | 5 | instance 自动提供/只读、无 new、不实现协议、启动前初始化、前向引用 |
| 20 | EXT-01 | §11 | 5 | 同包非泛型、只加方法、重复/同签名拒绝、协议实现违规、不进 vtable |
| 21 | ANN-01 | §12 | 4 | 编译期字段/参数、目标限制、无运行期对象、@Override 只对协议、@arc/@gc 拒绝 |
| 22 | GATE-01 | §16 | 4 | 15 BND 全过、负例断言诊断、无静默降级、证据完整 |

按最低集计：22 个零用例锚点 **≥104 例**；5 个部分锚点 **≥24 例**；2 个 PASS 锚点补强 **≥9 例**；合计 **≥137 例**（不含 35 口径追加的 6 条）。

### 1.2 部分锚点（5 个，已有 sema 用例但不够）

| 锚点 | 现有 | 缺口 |
|---|---|---|
| STRUCT-01 | `sema/typedecl_test.go:TestStructValueRules`（引用/可空引用/容器/数组/Result 字段、deinit、递归、嵌套合法） | 值复制独立性（运行期）、struct 参数/返回、捕获 self 运行期、非值泛型字段实参、跨包 struct |
| PROTO-01 | `sema/typedecl_test.go:TestProtocolRules`（字段/方法体/泛型协议/private/static 拒绝） | 默认实现、关联类型、泛型协议方法、约束、父协议实现检查、协议变量强持有、只调协议方法、动态派发 |
| ENUM-01 | `sema/typedecl_test.go:TestEnumRules`（重复项/重复值/混合/非 final 字段/项参数不匹配/无构造器/方法/隐式递增值） | 穷尽 switch、非穷尽、重复 case、未知 case、default 位置、枚举 implements protocol、简单枚举内联/无分配、数据枚举单例/GC/不可变 |
| MEM-01 | `sema/policy_test.go:TestPolicyTable/TestPolicyInternalAnnos/TestPolicyDeterministic/TestPolicySelfCaptureScan` | stack/ARC/GC 可观察行为、struct 不进 ARC/GC、deinit 顺序、策略判定边界（Any/协议/Result/元组含引用/泛型/self 捕获） |
| MEM-02 | `impl/runtime/test_gc.c`、`test_hard.c`（部分） | ARC↔GC 不悬挂/不泄漏、弱引用清除、环由 GC、全 ARC 环避免、压力/泄漏统计 |

### 1.3 已 PASS 锚点的补强（不能直接沿用 status.tsv）

| 锚点 | 现有 | 仍需补 |
|---|---|---|
| INH-01 | `sema/typedecl_test.go:TestInheritanceRules`（继承环、协议环、final 父类、struct 父类、子类同签名、字段隐藏、重载合法、implements 目标） | 单父多协议运行期、多级继承字段/方法复用、跨包继承、非法 `:` 目标矩阵、双路径 |
| FIELD-01 | `sema/typedecl_test.go:TestPrivateFieldRules`（private name/_name、private _name、_/__x/_1、裸 name、self._name/self.name、局部/参数 _name、外部两名） | 跨包访问、protected 子类访问、继承链基名唯一、运行期字段访问双路径 |

### 1.4 夹具/能力缺口（不补则大量用例无法执行）

| # | 缺口 | 影响锚点 | 处理 |
|---:|---|---|---|
| F-01 | 无 S2 跨包夹具（`xnull.project`/`src/main/x`/`src/lib/...`） | BND-01/02/08/09、INH/FIELD 跨包 | 建 `difftest/s2/pkg/` 三包夹具 |
| F-02 | 无 S2 运行期 C harness 接入（GC/ARC/弱引用/泄漏统计） | MEM-01/02、BND-10/11 | 复用 `impl/runtime/test_gc.c`，增 S2 驱动 |
| F-03 | 无协议 vtable/继承派发 codegen 用例 | DISP-01、BND-03/11 | 建双路径用例，编译路径必须能跑 |
| F-04 | factory/singleton/extension/annotation 语法与语义实现未见 | BND-07/08/13、SINGLE/EXT/ANN | 先确认实现卡，再建例；未实现前判 BLOCKED，不判 PASS |
| F-05 | 诊断码表未交付（D-04） | 全部负例 | 负例先断言“位置+消息关键字”，码表交付后补码 |
| F-06 | 29 vs 35 未冻结（D-02） | 全部 | 先裁决；本计划按 29 建主矩阵，附录 B 预留 6 条 |
| F-07 | 无 S2 黄金执行器/清单 | 全部 | 建 `difftest/s2/run.sh` + `cases.tsv`，期望值取自规范 |
| F-08 | 机器争用导致全仓测试超时 | GATE-01 | 固定 `-timeout 1200s`，关键包单跑并记录负载 |

### 1.5 起手顺序（P0）

1. 先落 **F-01 跨包夹具 + F-02 运行期 harness + F-07 执行器/cases.tsv**；否则后面的用例无法执行。
2. 建 **BND-14 负例骨架**（统一断言码+位置+消息），后续所有 R 类复用。
3. 补 **BND-01/02/09** 可见性与继承负例（sema 可先跑）。
4. 补 **DISP-01/BND-03** 类/协议派发（依赖 vtable；先建例，后等实现）。
5. 补 **BND-08/FACTORY-01** 跨包工厂（依赖 F-01）。
6. 补 **BND-10/MEM-01/MEM-02** 内存判定与运行时（依赖 F-02）。
7. 补 **BND-07/SINGLE-01、BND-13/EXT-01、ANN-01**（依赖语法/语义实现）。
8. 最后跑 **BND-15/INT-01/GATE-01** 集成门。

---

## 2. 黄金用例矩阵（29 锚点）

### 2.1 用例编号与判定层级

- 编号：`S2-<锚点>-<类型><序号>`。
  - `A`：accept/正向运行；`R`：reject/负向编译；`X`：跨包；`M`：内存/运行时不变量；`D`：双路径；`T`：确定性；`G`：门禁/集成。
- 每个用例必须在 `cases.tsv` 登记：`id, anchor, clause, mode, fixture, expect_exit, expect_stdout, expect_stderr_code, expect_position, owner`。
- 期望值来源：规范条款原文，不取自实现输出；负例必须断言 `file:line:col` + 诊断码（码表交付后）+ 消息关键字。

### 2.2 矩阵总表

| # | 锚点 | 条款 | 现有覆盖 | 黄金用例（最低） | 优先级 |
|---:|---|---|---|---|---|
| 1 | BND-01 | §7.3/§16 | 无 | A01–A02、R01–R03、X01 | P0 |
| 2 | BND-02 | §2.5/§5.1/§16 | INH 部分 | A01–A02、R01–R03 | P0 |
| 3 | BND-03 | §5.6–5.7/§16 | 无 | A01–A04、D01、M01 | P0 |
| 4 | BND-04 | §3.2/§16 | STRUCT 部分 | A01、R01–R02、D01 | P0 |
| 5 | BND-05 | §4/§16 | PROTO 部分 | A01–A02、R01–R03、D01 | P0 |
| 6 | BND-06 | §8.5/§16 | ENUM 部分 | A01–A02、R01–R04、D01 | P0 |
| 7 | BND-07 | §9.4/§16 | 无 | A01–A02、R01–R02、M01 | P0 |
| 8 | BND-08 | §10/§16 | 无 | A01–A02、R01–R03、X01 | P0 |
| 9 | BND-09 | §7.4/§16 | FIELD 部分 | A01、R01–R02、X01 | P0 |
| 10 | BND-10 | §15.1/15.6/§16 | MEM-01 部分 | M01–M03、R01、T01 | P0 |
| 11 | BND-11 | §3.3/§5.7/§15.3/§16 | 无 | A01–A02、D01、M01 | P0 |
| 12 | BND-12 | §13.4/§16 | 无 | R01–R03 | P0 |
| 13 | BND-13 | §11/§16 | 无 | A01–A02、R01–R03 | P0 |
| 14 | BND-14 | §16 | 无 | R01–R03 | P0 |
| 15 | BND-15 | §16+S1§10 | 无 | A01–A04、D01 | P0 |
| 16 | INH-01 | §5.1–5.2 | sema PASS | A01–A02、R01–R02、X01、D01 | P1 |
| 17 | DISP-01 | §5.6–5.7 | 无 | A01–A04、D01 | P0 |
| 18 | STRUCT-01 | §3.1–3.7 | sema 部分 | A01–A02、R01–R02、D01 | P1 |
| 19 | PCTOR-01 | §6.3 | 无 | A01–A03、R01–R02 | P0 |
| 20 | PROTO-01 | §4 | sema 部分 | A01–A02、R01–R03、D01 | P1 |
| 21 | ENUM-01 | §8 | sema 部分 | A01–A03、R01–R04、D01 | P1 |
| 22 | INT-01 | §18+S1§10 | 无 | A01–A03、D01 | P1 |
| 23 | SINGLE-01 | §9 | 无 | A01–A02、R01–R03、M01 | P1 |
| 24 | EXT-01 | §11 | 无 | A01–A02、R01–R03 | P1 |
| 25 | ANN-01 | §12 | 无 | A01–A02、R01–R03 | P1 |
| 26 | MEM-01 | §15.1–15.7 | sema 部分 | M01–M03、R01、T01 | P0 |
| 27 | MEM-02 | §15.6/15.8 | runtime 部分 | M01–M04 | P0 |
| 28 | FIELD-01 | §7.3–7.4 | sema PASS | A01、R01–R02、X01 | P1 |
| 29 | GATE-01 | §16 | 无 | G01–G04 | P0 |

### 2.3 逐锚点用例与期望

> 下表的“期望”是黄金判据；`R` 类必须同时断言诊断码（码表交付后）、`file:line:col`、消息关键字。`D` 类要求解释/编译 stdout 逐字节一致、退出码一致。

#### BND-01 成员级可见性

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND01-A01 | A | 同包 class 的 public/protected/private 成员访问 | 合法访问 rc=0；输出预期值 |
| S2-BND01-A02 | A | protected 成员在子类内访问 | rc=0 |
| S2-BND01-R01 | R | 类外访问 private 成员 | 错误码 + 位置，rc≠0 |
| S2-BND01-R02 | R | 跨包访问 protected（非子类） | 错误码 + 位置 |
| S2-BND01-R03 | R | 跨包访问 private | 错误码 + 位置 |
| S2-BND01-X01 | X | 跨包 public 顶层/类型/成员 | rc=0；私有/保护面拒绝 |

#### BND-02 类继承限制

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND02-A01 | A | 单父类字段/方法复用 | rc=0，输出父字段+子方法 |
| S2-BND02-A02 | A | 多级继承 + 多协议 | rc=0 |
| S2-BND02-R01 | R | abstract 类实例化 | 错误码 + 位置 |
| S2-BND02-R02 | R | 继承 final 类 | 错误码 + 位置 |
| S2-BND02-R03 | R | 子类同签名方法/字段隐藏 | 错误码 + 位置（两条独立用例） |

#### BND-03 派发

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND03-A01 | A | 类继承示例，类类型接收者 | 静态派发，输出 `1` |
| S2-BND03-A02 | A | 协议类型变量 | 动态派发，输出 `2` |
| S2-BND03-A03 | A | 同结构 ARC/GC 两种策略 | 策略不影响方法结果 |
| S2-BND03-A04 | A | 构造器/`deinit`/`super` 调用 | 静态派发，顺序确定 |
| S2-BND03-D01 | D | A01–A04 各跑双路径 | stdout+rc 一致 |
| S2-BND03-M01 | M | deinit 调用链 | 顺序/次数符合 §14/§15 |

#### BND-04 结构体

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND04-A01 | A | struct 赋值/传参/返回 | 副本独立，原值不变 |
| S2-BND04-R01 | R | 引用/可空引用/容器/数组/Result 字段 | 逐条错误码+位置 |
| S2-BND04-R02 | R | struct 捕获 self、deinit、非值泛型字段实参 | 逐条错误码+位置 |
| S2-BND04-D01 | D | A01 双路径 | 输出与 rc 一致 |

#### BND-05 协议

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND05-A01 | A | class implements 协议 + 父协议 | 实现检查通过，rc=0 |
| S2-BND05-A02 | A | 协议变量强持有 + 只调协议方法 | rc=0；非协议方法拒绝 |
| S2-BND05-R01 | R | 协议字段/方法体/默认实现 | 错误码+位置 |
| S2-BND05-R02 | R | 泛型协议/关联类型/泛型协议方法/约束 | 错误码+位置 |
| S2-BND05-R03 | R | 父协议方法未实现 | 错误码+位置 |
| S2-BND05-D01 | D | A01/A02 双路径 | 一致 |

#### BND-06 枚举

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND06-A01 | A | 无 default 的穷尽 switch | rc=0，命中全部分支 |
| S2-BND06-A02 | A | 简单枚举内联、数据枚举项单例/不可变 | 行为符合 §8；无分配可观察 |
| S2-BND06-R01 | R | 非穷尽 switch | 错误码+位置 |
| S2-BND06-R02 | R | 重复 case/未知项 | 错误码+位置 |
| S2-BND06-R03 | R | `default` 位置非法 | 错误码+位置 |
| S2-BND06-R04 | R | enum implements protocol | 错误码+位置 |
| S2-BND06-D01 | D | A01/A02 双路径 | 一致 |

#### BND-07 单例

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND07-A01 | A | `instance` 自动提供、只读 | rc=0；写入拒绝 |
| S2-BND07-A02 | A | 启动前初始化 | 入口前可见，值正确 |
| S2-BND07-R01 | R | `new` 单例 / 继承 / 实现协议 | 逐条错误码+位置 |
| S2-BND07-R02 | R | 前向引用 `instance` | 错误码+位置 |
| S2-BND07-M01 | M | 单例 GC 根常驻 | 进程生命周期内不被回收 |

#### BND-08 工厂

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND08-A01 | A | 同包 factory 调用 Target 私有构造器 | rc=0 |
| S2-BND08-A02 | A | 跨包 factory 只访问公开成员 | rc=0 |
| S2-BND08-R01 | R | 跨包访问私有成员 | 错误码+位置 |
| S2-BND08-R02 | R | 不可见 Target | 错误码+位置 |
| S2-BND08-R03 | R | 泛型裸名/返回约束/非类型使用/非法声明 | 逐条错误码+位置 |
| S2-BND08-X01 | X | 三包夹具（app/lib/factory） | rc=0 + 负例拒绝 |

#### BND-09 私有字段

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND09-A01 | A | `private name` / `_name` / protected 子类访问 | 类内合法路径 rc=0 |
| S2-BND09-R01 | R | `private _name`、`public/protected _name`、`_`/`__x`/`_1` | 逐条错误码+位置 |
| S2-BND09-R02 | R | 类内 `self._name`、裸 `name`、外部两名、局部/参数 `_name`、字段隐藏 | 逐条错误码+位置 |
| S2-BND09-X01 | X | 跨包私有字段/继承链基名唯一 | 错误码+位置 |

#### BND-10 内存策略

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND10-M01 | M | 判定表全行（Any/协议/Result/元组含引用/泛型/self 捕获/环） | 策略/规则与 §15.1 一致 |
| S2-BND10-M02 | M | stack/ARC/GC 可观察行为 | 身份、deinit、回收符合 §15 |
| S2-BND10-M03 | M | 混合引用图 15.6 六条不变量 | 无悬挂/泄漏/重复释放 |
| S2-BND10-R01 | R | 源码 `@arc` / `@gc` | 错误码+位置 |
| S2-BND10-T01 | T | 同源两次判定/两次构建 | 策略/槽位/hash 一致 |

#### BND-11 值/身份/ABI

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND11-A01 | A | struct 按值复制 | 副本独立 |
| S2-BND11-A02 | A | class 身份不被优化改变 | `===` 语义不变 |
| S2-BND11-D01 | D | A01/A02 双路径 | 一致 |
| S2-BND11-M01 | M | vtable 只含协议槽；地址+sret ABI | C 侧探针无共享身份泄漏 |

#### BND-12 泛型与内存

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND12-R01 | R | 残留类型参数 | 错误码+位置 |
| S2-BND12-R02 | R | 泛型协议/关联类型 | 错误码+位置 |
| S2-BND12-R03 | R | 泛型 struct 非值字段类型实参 | 错误码+位置 |

#### BND-13 扩展

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND13-A01 | A | 同包非泛型目标加方法 | rc=0，调用成功 |
| S2-BND13-A02 | A | 扩展不进入 vtable | 静态派发结果不变 |
| S2-BND13-R01 | R | 重复/同签名/覆写已有方法 | 错误码+位置 |
| S2-BND13-R02 | R | 协议实现通过扩展 | 错误码+位置 |
| S2-BND13-R03 | R | 跨包/泛型目标 | 错误码+位置 |

#### BND-14 负例总闸

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND14-R01 | R | BND-01..13 全部禁止构造 | 每条：码+位置+消息 |
| S2-BND14-R02 | R | “只报未实现”诊断 | 判失败（不得作为通过） |
| S2-BND14-R03 | T | 负例批量运行 | 无 panic/栈回溯；可报多条 |

#### BND-15 集成

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-BND15-A01 | A | Result/try/defer + class | 错误传播/清理顺序正确 |
| S2-BND15-A02 | A | `new T[count]` + class/struct | 零值/边界正确 |
| S2-BND15-A03 | A | 标签控制 + 枚举穷尽 switch | 行为符合 S1 |
| S2-BND15-A04 | A | 对象 + factory + Result | 组合语义正确 |
| S2-BND15-D01 | D | A01–A04 双路径 | 一致 |

#### INH-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-INH-A01 | A | 单父类 + 多协议运行期 | rc=0 |
| S2-INH-A02 | A | 多级继承字段/方法复用 | rc=0 |
| S2-INH-R01 | R | 非法 `:` / `implements` 目标 | 错误码+位置 |
| S2-INH-R02 | R | 继承环/协议环/子类同签名 | 错误码+位置 |
| S2-INH-X01 | X | 跨包继承 | rc=0 + 可见性负例 |
| S2-INH-D01 | D | A01/A02 双路径 | 一致 |

#### DISP-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-DISP-A01 | A | 类继承示例 | 静态 `1` |
| S2-DISP-A02 | A | 协议变量 | 动态 `2` |
| S2-DISP-A03 | A | 同结构 ARC/GC | 结果不受策略影响 |
| S2-DISP-A04 | A | `super` 调用 | 静态父实现 |
| S2-DISP-D01 | D | A01–A04 双路径 | 一致 |

#### STRUCT-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-STRUCT-A01 | A | 赋值/传参/返回复制 | 副本独立 |
| S2-STRUCT-A02 | A | 嵌套值 struct / 可空值字段 | rc=0 |
| S2-STRUCT-R01 | R | 引用/可空引用/容器/数组/Result 字段 | 错误码+位置 |
| S2-STRUCT-R02 | R | deinit/self 捕获/非值泛型实参/递归包含 | 错误码+位置 |
| S2-STRUCT-D01 | D | A01/A02 双路径 | 一致 |

#### PCTOR-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-PCTOR-A01 | A | 头部参数绑定同名字段 | 字段值正确 |
| S2-PCTOR-A02 | A | `super(...)` 后按声明顺序执行 | 可观察顺序正确 |
| S2-PCTOR-A03 | A | final 字段恰好赋值一次 | rc=0 |
| S2-PCTOR-R01 | R | 与非主构造器混用/非 final 参数 | 错误码+位置 |
| S2-PCTOR-R02 | R | 非 class 使用主构造器 | 错误码+位置 |

#### PROTO-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-PROTO-A01 | A | 实现检查含父协议 | rc=0 |
| S2-PROTO-A02 | A | 协议变量强持有 + 只调协议方法 | rc=0；非协议方法拒绝 |
| S2-PROTO-R01 | R | 字段/方法体/默认实现 | 错误码+位置 |
| S2-PROTO-R02 | R | 泛型协议/关联类型/泛型协议方法/约束 | 错误码+位置 |
| S2-PROTO-R03 | R | 父协议未实现 | 错误码+位置 |
| S2-PROTO-D01 | D | A01/A02 双路径 | 一致 |

#### ENUM-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-ENUM-A01 | A | 穷尽 switch（无 default） | rc=0 |
| S2-ENUM-A02 | A | 简单枚举内联/无分配 | 行为符合 §8 |
| S2-ENUM-A03 | A | 数据枚举项单例/GC/不可变 | 身份与写入限制正确 |
| S2-ENUM-R01 | R | 非穷尽/重复 case/未知项/default 位置 | 错误码+位置 |
| S2-ENUM-R02 | R | enum implements protocol | 错误码+位置 |
| S2-ENUM-D01 | D | A01–A03 双路径 | 一致 |

#### INT-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-INT-A01 | A | Result/try/defer + class | 语义正确 |
| S2-INT-A02 | A | Result/try/defer + factory | 语义正确 |
| S2-INT-A03 | A | 枚举穷尽 switch 集成 | 正确 |
| S2-INT-D01 | D | A01–A03 双路径 | 一致 |

#### SINGLE-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-SINGLE-A01 | A | `instance` 自动提供/只读 | rc=0；写入拒绝 |
| S2-SINGLE-A02 | A | 启动前初始化 | 入口前值可见 |
| S2-SINGLE-R01 | R | `new` 单例 | 错误码+位置 |
| S2-SINGLE-R02 | R | 继承/实现协议 | 错误码+位置 |
| S2-SINGLE-R03 | R | 前向引用 | 错误码+位置 |
| S2-SINGLE-M01 | M | GC 根常驻 | 不回收 |

#### EXT-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-EXT-A01 | A | 同包非泛型目标加方法 | rc=0 |
| S2-EXT-A02 | A | 扩展不进 vtable | 静态派发结果不变 |
| S2-EXT-R01 | R | 重复/同签名/覆写 | 错误码+位置 |
| S2-EXT-R02 | R | 协议实现违规 | 错误码+位置 |
| S2-EXT-R03 | R | 跨包/泛型目标 | 错误码+位置 |

#### ANN-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-ANN-A01 | A | 编译期字段/参数注解 | rc=0，无运行期对象 |
| S2-ANN-A02 | A | `@Override` 对协议实现 | rc=0 |
| S2-ANN-R01 | R | 非法目标 | 错误码+位置 |
| S2-ANN-R02 | R | 运行期对象/反射使用 | 错误码+位置 |
| S2-ANN-R03 | R | `@Override` 对父类方法 / 源码 @arc/@gc | 错误码+位置 |

#### MEM-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-MEM01-M01 | M | 判定表全行 + 边界 | 与 §15.1 一致 |
| S2-MEM01-M02 | M | struct 不进 ARC/GC | 无 retain/release/GC 记录 |
| S2-MEM01-M03 | M | stack/ARC/GC 行为 + deinit 顺序 | 符合 §15 |
| S2-MEM01-R01 | R | 源码 @arc/@gc | 错误码+位置 |
| S2-MEM01-T01 | T | 两次判定/两次构建 | 策略/槽位/hash 一致 |

#### MEM-02

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-MEM02-M01 | M | ARC↔GC 互引 | 不悬挂/不泄漏 |
| S2-MEM02-M02 | M | 弱引用目标终结 | 终结前清除；读不到 |
| S2-MEM02-M03 | M | 引用环 | 由 GC 回收 |
| S2-MEM02-M04 | M | 全 ARC 环 | 被避免（无泄漏） |

#### FIELD-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-FIELD-A01 | A | 类内合法字段访问（裸 `_name` 等） | rc=0 |
| S2-FIELD-R01 | R | `private _name`、`self._name`、裸 `name`、外部两名 | 错误码+位置 |
| S2-FIELD-R02 | R | 局部/参数 `_name`、字段隐藏 | 错误码+位置 |
| S2-FIELD-X01 | X | 跨包字段访问 | public 通过；private/protected 拒绝 |

#### GATE-01

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| S2-GATE-G01 | G | 15 个 BND 全过 | 29/29（或 35/35） |
| S2-GATE-G02 | G | 负例断言诊断 | 0 个“只报未实现” |
| S2-GATE-G03 | G | 全仓测试 + 10 次重复 | 全绿；0 flaky；0 SKIP |
| S2-GATE-G04 | G | 证据完整性 | 每锚点七件套齐全 |

---

## 3. 独立验收执行计划

### 3.1 入口条件（不满足则 BLOCKED，不判 PASS）

1. S2 实现已合入 main，给出 commit sha；`impl/` 无 QA 未审改动。
2. 29/35 口径已裁决（D-02）；本计划按 29 执行，附录 B 为 35 增量。
3. 诊断码表已交付（D-04）或明确“100% 项不具备判定条件”。
4. 跨包夹具可构建（PKG-01 限制已解除）；否则 BND-01/02/08/09 的 X 类判 BLOCKED。
5. factory/singleton/extension/annotation 语法与语义已实现；未实现前对应锚点判 BLOCKED，不用“未实现”当 PASS。
6. 运行期 GC/ARC harness 可构建（`impl/runtime`）。

### 3.2 批次

| 批次 | 内容 | 出口 |
|---|---|---|
| S2-QA-0 | 口径冻结、夹具、执行器、cases.tsv | 骨架可跑；空矩阵 0 用例 |
| S2-QA-1 | 编译期负例：BND-01/02/04/05/06/09/12/13/14 + INH/FIELD/STRUCT/PROTO/ENUM | 负例全带码+位置；0 panic |
| S2-QA-2 | 解释运行期正例：DISP/PCTOR/SINGLE/EXT/INT/ANN + 类/结构/枚举/协议 | stdout 与期望逐字节一致 |
| S2-QA-3 | 编译路径双路径：全部 A/D 用例 | 0 mismatch；退出码一致 |
| S2-QA-4 | 内存/运行时不变量：MEM-01/02、BND-10/11 | 无泄漏/悬挂；deinit 顺序正确 |
| S2-QA-5 | 跨包/工厂/可见性：BND-01/02/08/09、INH/FIELD X 类 | 跨包正例通过、负例拒绝 |
| S2-QA-6 | 门禁：GATE-01、BND-15、DET、全仓、flaky | 29/29；证据齐全 |

### 3.3 执行方式

- 从干净 worktree/归档副本构建，不在被测工作树写文件。
- 用例独立于实现者测试：QA 自写 fixtures；不把 RD 测试当唯一证据。
- 负例：`xnull build` / `xnull check`，断言 `error[CODE]` + `file:line:col` + 消息关键字；禁止只断言“失败”。
- 正例：`xnull run --interp` 与 `xnull run` 各跑一次，stdout 逐字节 + 退出码一致。
- 运行期：`xnull build` 产出可执行，10 次运行；C harness 记录分配/释放/GC 计数。
- 每批固定 `go test ./... -count=1 -timeout 1200s`；关键包单跑并记录机器负载。
- 抽样：P0/P1 锚点 100% 用例；P2 回归每批抽 20%；变异按董事会验收标准 ≥80%（Stage 1 起适用）；覆盖率按标准阈值。

### 3.4 证据格式

```
evidence/S2-QA/<anchor>/<case-id>/
  cmd.txt        # 可复制命令
  stdout.txt     # 原样 stdout
  stderr.txt     # 原样 stderr（含诊断）
  exit_code.txt
  sha.txt        # main sha + 二进制 sha256 + 工具链
evidence/S2-QA/matrix.tsv     # id/anchor/mode/expect/actual/verdict
evidence/S2-QA/summary.md     # 逐锚点 PASS/FAIL/BLOCKED + 缺口
```

门证据另附：`git log` sha、`go test` 原始输出、双路径 diff、内存统计、两次构建 hash。

### 3.5 PASS / FAIL 判据

- 锚点 PASS：该锚点全部 A/R/X/M/D/T 用例通过；无 SKIP；负例均有码+位置；双路径 0 mismatch。
- 锚点 FAIL：任一黄金用例失败；或只有“编译失败”无具体诊断；或运行期才失败而规范要求编译期。
- 锚点 BLOCKED：实现能力缺失（factory/singleton/extension/annotation/vtable/跨包）或口径未冻结；BLOCKED 不计 PASS。
- 阶段 PASS：29/29（或 35/35）全 PASS + GATE-01 + 条款追溯 100% + 诊断码触发 100% + 全仓绿 + 0 flaky + 0 SKIP。
- 反作弊：
  - 期望值必须来自规范；发现“期望=实现输出”即判该用例无效。
  - 禁止手改 `status.tsv` 翻 PASS；状态只能由 QA 验收后更新。
  - 禁止把“未实现/不支持”诊断当负例通过；BND-14 专测。
  - 禁止用单路径输出当双路径证据。

---

## 4. 风险与待裁决

| # | 风险/待裁决 | 影响 | 建议 |
|---:|---|---|---|
| R-01 | D-02：29 vs 35 | 按 29 漏验工厂、S2 元组内存、S2 确定性 | 董事会先裁决；本计划附录 B 预留 6 条 |
| R-02 | D-04：诊断码表未交付 | “码触发 100%”不可判 | 先按位置+消息关键字；码表后补 |
| R-03 | 跨包构建未通（PKG-01 限制） | BND-01/02/08/09 X 类无法执行 | 先打通 `xnull.project` 三包夹具 |
| R-04 | vtable/协议派发未实现 | DISP/BND-03/11 无法执行 | 实现卡先行；QA 只建例 |
| R-05 | factory/singleton/extension/annotation 未实现 | BND-07/08/13、SINGLE/EXT/ANN 全 BLOCKED | 确认实现卡与排期 |
| R-06 | GC/ARC 运行时未完成 | MEM-01/02、BND-10/11 无法判 | 复用/扩展 `impl/runtime/test_gc.c` |
| R-07 | 机器争用导致全仓超时 | GATE-01 假红 | 固定超时、单包复跑、记录负载 |
| R-08 | S2 元组内存维度不在 29 | TUPLE 内存未验 | 若 35 口径，按附录 B 补 |

---

## 附录 A：29 锚点清单（与台账一致）

BND-01..BND-15（15）
INH-01、DISP-01、STRUCT-01、PCTOR-01、PROTO-01、ENUM-01、INT-01、SINGLE-01、EXT-01、ANN-01、MEM-01、MEM-02、FIELD-01、GATE-01（14）

合计 29。

## 附录 B：若按 35 口径需追加的 6 条（§18 未入台账）

| 锚点 | 验证点 | 最低用例 |
|---|---|---|
| S2 TYPE-01 | 名义类型：同成员不同声明不兼容；导入别名不改身份；泛型实参不同是不同类型 | A01–A03、R01 |
| FACTORY-01 | 工厂类型（与 BND-08 同源，但作为 §18 独立锚点） | A01–A02、R01–R03、X01 |
| S2 GEN-01 | 单态化、型变位置、裸泛型擦除、递归终止；泛型协议/关联类型/泛型 struct 非值实参拒绝 | A01–A02、R01–R03 |
| S2 TUPLE-01 | 全值元素元组字段合法且内联复制；含引用元素元组的 struct 字段拒绝；类中该字段按 GC | A01–A02、R01、M01 |
| S2 NEG-01 | 每类禁止构造有诊断；不崩溃、不静默 | R01–R03 |
| S2 DET-01 | 同源/同版/同选项同布局决策、槽位、运行结果 | T01–T02 |

---

## 附录 C：现有用例映射（核对用）

| 锚点 | 现有文件/用例 | 级别 |
|---|---|---|
| INH-01 | `impl/internal/sema/typedecl_test.go:TestInheritanceRules` | sema |
| FIELD-01 | `impl/internal/sema/typedecl_test.go:TestPrivateFieldRules` | sema |
| STRUCT-01 | `impl/internal/sema/typedecl_test.go:TestStructValueRules` | sema |
| PROTO-01 | `impl/internal/sema/typedecl_test.go:TestProtocolRules` | sema |
| ENUM-01 | `impl/internal/sema/typedecl_test.go:TestEnumRules` | sema |
| MEM-01 | `impl/internal/sema/policy_test.go:TestPolicyTable/TestPolicyInternalAnnos/TestPolicyDeterministic/TestPolicySelfCaptureScan` | sema |
| MEM-02 | `impl/runtime/test_gc.c`、`impl/runtime/test_hard.c` | runtime（部分） |
| 基本类运行期 | `examples/classes.x`、`examples/objlist.x`；`impl/internal/codegen/codegen_test.go:TestExamplesCompileMatchesInterp` | dual-path（仅基础类） |
| 类字段初始化 | `impl/internal/codegen/b0_04_test.go` | codegen（字段） |

**未发现专项用例**：BND-01..15、DISP-01、PCTOR-01、INT-01、SINGLE-01、EXT-01、ANN-01、GATE-01。

---

> 本计划为 QA1 启动版；下一版在 D-02/D-04 裁决、夹具落地后更新为 v0.2，并开始 S2-QA-0。
