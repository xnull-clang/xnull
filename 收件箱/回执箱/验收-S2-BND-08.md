# 验收：S2-BND-08（工厂 factory）

> **验收人**：QA1（独立质量线）
> **结论：PASS（全表 7/7，双路径）**
> **复验点**：main `0177c80`（`0177c8077670eaa618b3052544ec475a775abf72`；含 `395a17c` BND-08 sema、`16e8e1b` BND-08 codegen）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-0177c80`，sha256 `44a6b9f31a0bec34115f91b43673a3442ca9c6e0b85e7dc5d58e8429be9fe6d4`
> **证据**：`evidence/S2-QA/BND-08-0177c80/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §10.1–§10.5、§16 BND-08
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`，并核对源码含 `TY-217/219/220/221`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 同包 factory 调用 Target 私有构造器 | **PASS**：三路径 `cam` |
| 跨包 factory 只访问公开成员 | **PASS**：check/interp/compiled 全 rc=0，`x` |
| 跨包 factory 访问私有构造器拒绝 | **PASS**：`TY-219` @3:19（三路径） |
| Target 必须可见 | **PASS**：`TY-217` @1:9 |
| Target 不能写泛型实参 | **PASS**：`TY-217` @5:9 |
| Target 必须是 class/struct | **PASS**：`TY-217` @1:9 |
| factory 不能声明字段 | **PASS**：`SYN-101` @3:5 |
| factory 不是类型 | **PASS**：`TY-217` @6:5（补充探针） |
| `new` factory 拒绝 | **PASS**：`TY-217` + `TY-216`（补充探针） |
| 工厂方法返回约束 | **PASS**：无关返回 `TY-220` @3:16（补充探针） |
| 工厂方法禁用 `self`/`super` | **PASS**：`TY-221` @3:14（补充探针） |
| Target protocol/enum/singleton/array/Object/Any/可空 | **PASS**：全部 `TY-217`（补充探针） |

**判定：PASS。** 全表 7 个夹具在 check/interp/compiled 三路径均符合预期；上一轮失败的跨包私有构造器与跨包公开工厂 codegen 均已闭合。

---

## 二、全表实测

### 2.1 正例

| 用例 | 期望 | check | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|---|
| `a01_same_pkg` 同包 factory 调 `private Device(...)` | `cam` | rc=0 | `cam`，rc=0 | `cam`，rc=0 | **PASS** |
| `factory_public` 跨包 factory 调公开静态工厂 | `x` | rc=0 | `x`，rc=0 | `x`，rc=0 | **PASS** |

### 2.2 负例（三路径一致）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `factory_cross` 跨包 factory 调私有构造器 | rc≠0 + 可见性诊断 | `3:19 error[TY-219]：跨包 factory 不能调用 Target Device 的非公开构造器` | **PASS** |
| `r02_invisible` `factory F for Missing` | rc≠0 + Target 不可见 | `1:9 error[TY-217]：Target Missing 未在本包声明或不可见` | **PASS** |
| `r03_generic_args` `for Box<Int>` | rc≠0 + 裸名规则 | `5:9 error[TY-217]：Target 不能写泛型实参` | **PASS** |
| `r03_non_type` `for Int` | rc≠0 + Target 种类规则 | `1:9 error[TY-217]` | **PASS** |
| `r03_field` factory 内声明字段 | rc≠0 + 位置 | `3:5 error[SYN-101]：工厂方法必须写 static` | **PASS** |

全部 check/interp/compiled 均为 rc=1，诊断一致。

### 2.3 补充探针

| 探针 | 期望 | 实测 | 判定 |
|---|---|---|---|
| 返回无关类型 `static Int make()` | rc≠0 | `TY-220` @3:16（三路径） | **PASS** |
| 工厂方法使用 `self` | rc≠0 | `TY-221` @3:14（三路径） | **PASS** |
| factory 当类型 / `new F()` | rc≠0 | `TY-217` / `TY-216` | **PASS** |
| Target protocol / enum / singleton / array / Object / Any / 可空 | rc≠0 | 全部 `TY-217` + 位置 | **PASS** |
| 工厂方法 `abstract` / `final` | rc≠0 | `SYN-101` @方法修饰符 | **PASS** |
| 返回父类 | 可用 | 双路径 rc=0（C 编译有指针兼容 warning） | **PASS** |

---

## 三、边界（不改变本轮全表判定）

以下为全表未覆盖的 §10.2/§10.5 细节，已记录并建议后续卡关闭：

| 项 | 现状 | 证据 |
|---|---|---|
| `protected static` 工厂方法 | check/interp/compiled 均 rc=0；§10.2 应拒绝 | `probe-bnd08_protected_method/` |
| 重复签名 | sema/interp rc=0；compiled C 重定义错误；§10.5 应提前拒绝 | `probe-bnd08_dup_sig/` |
| 返回 `Object` | sema/interp 通过；compiled `类型 Object 未支持` | `probe-bnd08_ret_object/` |
| 返回协议 | sema/interp 通过；compiled `未登记标识符 F` | `probe-bnd08_ret_protocol2/` |
| 返回 `Result`（非 String 错误类型） | codegen `Result 错误类型暂仅支持 String` | `probe-bnd08_ret_result2/` |

建议 E2/E4 在 BND-08 收线前补上述边界；本轮按 `difftest/s2/bnd08` 全表判定 PASS。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0708SingletonFactory' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2BND08Factory' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、证据

- `evidence/S2-QA/BND-08-0177c80/matrix.tsv`
- `evidence/S2-QA/BND-08-0177c80/S2-BND08-A01/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-0177c80/S2-BND08-A02-cross-private/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-0177c80/S2-BND08-A02-cross-public/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-0177c80/S2-BND08-R02-invisible/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-0177c80/S2-BND08-R03-{field,generic-args,non-type}/{check,interp,compiled}/`
- `evidence/S2-QA/BND-08-0177c80/probe-*/`
- `evidence/S2-QA/BND-08-0177c80/gotest-sema/`、`gotest-codegen/`
- 夹具：`difftest/s2/bnd08/`、`difftest/s2/bnd08/xpkg/`
