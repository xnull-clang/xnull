# 验收：S2-BND-08（工厂 factory）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（名称空间与 Target 规则已接入；跨包可见性、跨包 codegen、返回约束、`self` 禁止仍未闭合）
> **复验点**：main `e2f943c`（`e2f943cf01319544c655469f9f9a81df690964d9`，含 `1b1d12e` singleton/factory sema）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-e2f943c`，sha256 `baa515e915fb4d1cb653e1dbda5efbc15bab98cf74849b22df832b81a6e9c42d`
> **证据**：`evidence/S2-QA/BND-08-e2f943c/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §10.1–§10.5、§16 BND-08
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`，源码含 `TY-215/216/217`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 同包 factory 调用 Target 私有构造器 | **PASS**：双路径 `cam`，rc=0 |
| 跨包 factory 只访问公开成员 | **部分**：解释路径 `x` PASS；编译路径 `codegen：未登记标识符 Device` FAIL |
| 跨包 factory 访问私有构造器拒绝 | **FAIL**：`check` rc=0；`interp`/`compiled` 输出 `x`，成功访问私有构造器 |
| 跨包私有成员访问拒绝 | **FAIL**：`check` rc=0，无诊断 |
| Target 必须可见 | **PASS**：`TY-217` @1:9 |
| Target 不能写泛型实参 | **PASS**：`TY-217` @5:9 |
| Target 必须是 class/struct | **PASS**：`TY-217` @1:9（`Int` 被拒；消息为“未在本包声明或不可见”） |
| factory 不能声明字段 | **PASS**：`SYN-101` @3:5 |
| factory 不是类型 | **PASS**：`TY-217` @6:5 |
| `new` factory 拒绝 | **PASS**：`TY-217` + `TY-216` |
| 工厂方法返回类型受 §10.2 约束 | **FAIL**：`static Int make()`（Target 为 class D）`check`/`run` rc=0 |
| 工厂方法不得使用 `self`/`super` | **FAIL**：`check`/`interp` rc=0；compiled C 编译失败 `self` 未声明 |
| 三包工程 | **BLOCKED**：工程 build 未实现；跨包公开工厂 codegen 失败 |

**判定：FAIL。** 1b1d12e 已补齐名称空间、Target 可见性、泛型实参、非类型 Target、factory 非类型、`new` 等禁止面；但 BND-08 的核心“跨包只能访问公开成员”和跨包 codegen 尚未成立，并有返回约束与 `self` 禁止缺口。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | check | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|---|
| `S2-BND08-A01` 同包 factory 调 `private Device(...)` | `cam` | rc=0 | `cam`，rc=0 | `cam`，rc=0 | **PASS** |
| `S2-BND08-A02` 跨包 factory 只访问公开成员（`Device.make`） | `x` | rc=0 | `x`，rc=0 | rc=1；`codegen：未登记标识符 Device` | **FAIL** |

### 2.2 负例

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `A02-cross-private` 跨包 factory 调 Target 私有构造器 | rc≠0 + 私有访问诊断 | **`check` rc=0；`interp`/`compiled` 输出 `x`，rc=0** | **FAIL** |
| `R01-cross-private` 跨包访问私有成员 | rc≠0 + 可见性诊断 | **`check` rc=0，无诊断** | **FAIL** |
| `R02-invisible` `factory F for Missing` | rc≠0 + Target 不可见诊断 | `1:9 error[TY-217]：Target Missing 未在本包声明或不可见` | **PASS** |
| `R03-generic-args` `factory BoxFactory for Box<Int>` | rc≠0（Target 应写裸名） | `5:9 error[TY-217]：Target 不能写泛型实参` | **PASS** |
| `R03-non-type` `factory IntFactory for Int` | rc≠0 + Target 非 class/struct | `1:9 error[TY-217]：Target Int 未在本包声明或不可见` | **PASS** |
| `R03-field` factory 内声明字段 | rc≠0 + 位置 | `3:5 error[SYN-101]：工厂方法必须写 static` | **PASS** |

`R03-non-type` 已拒绝且带 `TY-217` 与位置；消息把内建 `Int` 说成“未在本包声明或不可见”，措辞不准确，但不影响“拒绝非 class/struct Target”的判定。

### 2.3 补充探针

| 探针 | 期望 | 实测 | 判定 |
|---|---|---|---|
| factory 当类型 `F f` | rc≠0 | `TY-217` @6:5 | **PASS** |
| `new F()` | rc≠0 | `TY-217` @6:5 + `TY-216` @6:11 | **PASS** |
| 工厂方法返回无关类型 `static Int make()` | rc≠0（§10.2） | `check`/`interp`/`compiled` 均 rc=0 | **FAIL** |
| 工厂方法使用 `self` | rc≠0 | `check`/`interp` rc=0；compiled C 编译失败 `self` 未声明 | **FAIL** |

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | 跨包 factory 访问 Target 私有构造器被接受并运行 | `S2-BND08-A02-cross-private/{check,interp,compiled}` rc=0，输出 `x` | E2 sema（跨包可见性）+ E4 |
| P-02 | 跨包私有成员访问未拒绝 | `S2-BND08-R01-cross-private/check` rc=0 | E2 sema |
| P-03 | 跨包公开工厂编译路径失败（`Device` 未登记） | `S2-BND08-A02-cross-public/compiled` rc=1 | E4 codegen（跨包类型登记） |
| P-04 | 工厂方法返回类型未按 §10.2 约束 | `probe-bnd08_bad_return` check/run rc=0 | E2 sema |
| P-05 | 工厂方法 `self` 未拒绝，延迟到 C 编译失败 | `probe-bnd08_self/check` rc=0；compiled C 错误 | E2 sema |
| P-06 | 三包工程无法执行 | 工程 build 未实现；跨包 codegen 失败 | E1/E6 + E4 |

已通过面：同包私有构造器访问、Target 可见性、泛型实参、非类型 Target、factory 非类型、`new` factory、factory 字段声明。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0708SingletonFactory' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2BND08Factory' -count=1` | PASS（不覆盖跨包/可见性/返回约束/self） |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、放行条件

1. E2：跨包 factory 只能访问 Target 公开构造器/公开静态成员；私有/受保护访问必须拒绝，且诊断不得被 `RES-101` 或“未登记”掩盖。
2. E4：跨包 factory 编译路径能登记并引用 Target 类型（`Device.make` 正例双路径 `x`）。
3. E2：工厂方法返回类型按 §10.2 集合检查；`self`/`super`/实例字段访问拒绝。
4. E1/E6：三包工程夹具可执行。
5. 复跑本文件全部 A/R/探针；P-01–P-06 关闭后再判 PASS。

---

## 六、证据

- `evidence/S2-QA/BND-08-e2f943c/matrix.tsv`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-A01/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-A02-cross-public/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-A02-cross-private/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-R01-cross-private/check/`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-R02-invisible/check/`
- `evidence/S2-QA/BND-08-e2f943c/S2-BND08-R03-{generic-args,non-type,field}/check/`
- `evidence/S2-QA/BND-08-e2f943c/probe-*/`
- `evidence/S2-QA/BND-08-e2f943c/gotest-sema/`、`gotest-codegen/`
- 夹具：`difftest/s2/bnd08/`、`difftest/s2/bnd08/xpkg/`
