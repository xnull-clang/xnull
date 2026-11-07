# 验收：S2-BND-07（单例 singleton）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（名称空间与主要禁止面已接入；解释路径、前向引用、`abstract`、静态成员、GC 根仍未闭合）
> **复验点**：main `e2f943c`（`e2f943cf01319544c655469f9f9a81df690964d9`，含 `1b1d12e` singleton/factory sema）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-e2f943c`，sha256 `baa515e915fb4d1cb653e1dbda5efbc15bab98cf74849b22df832b81a6e9c42d`
> **证据**：`evidence/S2-QA/BND-07-e2f943c/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §9.1–§9.4、§16 BND-07
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`，源码含 `TY-215/216/217`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `instance` 自动提供、字段/方法可读 | **部分**：编译路径 `XNull\n3` PASS；解释路径 `未定义的名称 AppInfo` FAIL |
| 启动前初始化（`main` 前可见） | **部分**：编译路径 `localhost\n8080` PASS；解释路径 `未定义的名称 Config` FAIL |
| 单例不能 `new` | **PASS**：`TY-216` @5:17 |
| 单例不能继承 | **PASS**：`TY-202` @4:7 |
| 单例不能实现协议 | **PASS**：`SYN-101` @2:19 |
| `instance` 只读、不能为 `null` | **PASS**：`TY-215` @5:12 |
| 跨单例前向引用拒绝 | **FAIL**：`check`/`interp` rc=0；compiled 被“字段初始化式访问成员”间接拒绝 |
| 不能是 `abstract` | **FAIL**：`check`/`run` rc=0，无诊断 |
| 可以有静态字段/方法（§9.1） | **FAIL**：`check` rc=0；compiled `codegen：单例静态字段暂未支持` |
| 初始化式可引用前面的单例（§9.2） | **FAIL**：`A.v = B.instance.value` compiled rc=1 |
| `instance` 为 GC 全局根（§9.3） | **FAIL**：`impl/internal/codegen/singleton.go` 使用 `rt_arc_new`，未见 GC 根/GC 语义 |

**判定：FAIL。** 1b1d12e 已补齐名称空间、`new`、继承、`implements`、`instance` 只读与泛型禁止；但解释路径、前向引用、`abstract`、静态成员、单例间字段引用、GC 根仍未成立。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | check | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|---|
| `S2-BND07-A01` `AppInfo.instance.name/count` | `XNull\n3` | rc=0 | rc=1；`未定义的名称 AppInfo` | `XNull\n3`，rc=0 | **FAIL**（解释） |
| `S2-BND07-A02` `Config.instance.host/port` | `localhost\n8080` | rc=0 | rc=1；`未定义的名称 Config` | `localhost\n8080`，rc=0 | **FAIL**（解释） |

### 2.2 负例（`xnull check`）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `R01-new` `new AppInfo()` | rc≠0 + 单例诊断 | `5:17 error[TY-216]：不是可实例化类型（singleton/factory）` | **PASS** |
| `R01-write` `AppInfo.instance = null` | rc≠0 + 只读诊断 | `5:12 error[TY-215]：instance 是只读全局实例`（另有 `TY-103` null 类型不符） | **PASS** |
| `R01-inherit` `class Sub : AppInfo` | rc≠0 + 不可继承诊断 | `4:7 error[TY-202]：父类 AppInfo 必须是 class（得到 singleton）` | **PASS** |
| `R01-implements` `singleton ... implements P` | rc≠0 + 位置 | `2:19 error[SYN-101]：单例头部不能带参数或继承` | **PASS** |
| `R02-fwd` A 引用后面的 B.instance | rc≠0 + 前向引用诊断 | **`check`/`interp` rc=0，无诊断**；compiled rc=1，`字段初始化式访问了成员 value` | **FAIL** |

### 2.3 补充探针

| 探针 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `abstract singleton A` | rc≠0 + 位置 | `check`/`interp`/`compiled` 均 rc=0 | **FAIL** |
| 单例静态字段/方法 | 双路径可用 | `check` rc=0；compiled rc=1 `codegen：单例静态字段暂未支持`；interp rc=1 `未定义的名称 A` | **FAIL** |
| 引用前面的单例 `Int v = B.instance.value`（B 在前） | 双路径可用（§9.2） | compiled rc=1 `字段初始化式访问了成员 value`；interp rc=1 `未定义的名称 A` | **FAIL** |
| `instance` GC 根 | 进程常驻、GC 语义 | `impl/internal/codegen/singleton.go` 使用 `rt_arc_new`，注释自述“GC 语义由 E5”；未见 GC 根 | **FAIL** |

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | 解释器未登记 `SingletonDecl`，正例 `未定义的名称` | `S2-BND07-A01/interp`、`A02/interp` | E3 |
| P-02 | `abstract singleton` 未拒绝 | `probe-bnd07_abstract/*` rc=0 | E2 sema |
| P-03 | 单例静态字段/方法未发射 | `probe-bnd07_static_ok/compiled` rc=1 | E4 |
| P-04 | 初始化式不能引用前面单例字段 | `probe-bnd07_prev_ref_ok/compiled` rc=1 | E4 codegen |
| P-05 | 前向引用未在 `check` 拒绝；compiled 诊断错位 | `S2-BND07-R02-fwd/{check,interp,compiled}` | E2 + E4 |
| P-06 | `instance` 未按 GC 全局根实现（ARC 对象） | `impl/internal/codegen/singleton.go` | E4 + E5 |

已通过面：名称空间注册、`new`/继承/`implements`/只读/泛型禁止、编译路径 A01/A02、启动前初始化。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0708SingletonFactory' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2BND07Singleton' -count=1` | PASS（不覆盖解释路径与上述探针） |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、放行条件

1. E3：解释器注册单例，A01/A02 双路径 `XNull\n3`、`localhost\n8080`。
2. E2：拒绝 `abstract singleton`；前向引用 `check` 直接报错（专用诊断 + 位置）。
3. E4：发射单例静态字段/方法；支持初始化式引用前面单例的字段。
4. E4/E5：`instance` 按 GC 全局根实现，进程常驻。
5. 复跑本文件全部 A/R/探针；P-01–P-06 关闭后再判 PASS。

---

## 六、证据

- `evidence/S2-QA/BND-07-e2f943c/matrix.tsv`
- `evidence/S2-QA/BND-07-e2f943c/S2-BND07-A01/{check,interp,compiled}/`、`A02/{check,interp,compiled}/`
- `evidence/S2-QA/BND-07-e2f943c/S2-BND07-R01-{new,write,inherit,implements}/check/`
- `evidence/S2-QA/BND-07-e2f943c/S2-BND07-R02-fwd/{check,interp,compiled}/`
- `evidence/S2-QA/BND-07-e2f943c/probe-*/`
- `evidence/S2-QA/BND-07-e2f943c/gotest-sema/`、`gotest-codegen/`
- 夹具：`difftest/s2/bnd07/`
