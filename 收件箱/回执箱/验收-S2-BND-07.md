# 验收：S2-BND-07（单例 singleton）

> **验收人**：QA1（独立质量线）
> **结论：PASS（全表 7/7，双路径）**
> **复验点**：main `0177c80`（`0177c8077670eaa618b3052544ec475a775abf72`；含 `cd5f65b` BND-07 sema、`cfa9c62` singleton interp）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-0177c80`，sha256 `44a6b9f31a0bec34115f91b43673a3442ca9c6e0b85e7dc5d58e8429be9fe6d4`
> **证据**：`evidence/S2-QA/BND-07-0177c80/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §9.1–§9.4、§16 BND-07
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`，并核对源码含 `TY-215/216/222` 与 interp `SingletonDecl` 注册。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `instance` 自动提供、字段/方法可读 | **PASS**：A01 三路径 `XNull\n3` |
| 启动前初始化（`main` 前可见） | **PASS**：A02 三路径 `localhost\n8080` |
| 单例不能实现协议 | **PASS**：`SYN-101` @2:19 |
| 单例不能继承 | **PASS**：`TY-202` @4:7 |
| 单例不能 `new` | **PASS**：`TY-216` @5:17 |
| `instance` 只读、不能为 `null` | **PASS**：`TY-215` @5:12 |
| 跨单例前向引用拒绝 | **PASS**：`TY-222` @2:23 |
| 不能是 `abstract` | **PASS**：`TY-222` @1:20（补充探针） |
| 不能手动声明 `instance` | **PASS**：`TY-215` @2:9（补充探针） |
| 不能声明构造器 | **PASS**：`TY-201` @3:6（补充探针） |
| 不能是泛型 | **PASS**：`SYN-101` @1:12（补充探针） |
| `instance` 进程常驻 | **PASS（可观察）**：全局句柄不释放；GC 分类归 E5 |

**判定：PASS。** 全表 7 个夹具在 check/interp/compiled 三路径均符合预期；A01/A02 双路径输出一致，全部负例命中专用诊断与位置。

---

## 二、全表实测

### 2.1 正例（双路径）

| 用例 | 期望 | check | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|---|
| `a01_instance` `AppInfo.instance.name/count` | `XNull\n3` | rc=0 | `XNull\n3`，rc=0 | `XNull\n3`，rc=0 | **PASS** |
| `a02_startup` `Config.instance.host/port` | `localhost\n8080` | rc=0 | `localhost\n8080`，rc=0 | `localhost\n8080`，rc=0 | **PASS** |

### 2.2 负例（三路径一致）

| 用例 | 期望 | 实测诊断 | 判定 |
|---|---|---|---|
| `r01_implements` `singleton ... implements P` | rc≠0 + 位置 | `2:19 error[SYN-101]：单例头部不能带参数或继承` | **PASS** |
| `r01_inherit` `class Sub : AppInfo` | rc≠0 + 单例规则 | `4:7 error[TY-202]：父类 AppInfo 必须是 class（得到 singleton）` | **PASS** |
| `r01_new` `new AppInfo()` | rc≠0 + 单例规则 | `5:17 error[TY-216]：不是可实例化类型（singleton/factory）` | **PASS** |
| `r01_write` `AppInfo.instance = null` | rc≠0 + 只读规则 | `5:12 error[TY-215]：instance 是只读全局实例` | **PASS** |
| `r02_fwd` A 引用后面的 B.instance | rc≠0 + 前向引用规则 | `2:23 error[TY-222]：单例 A 不能前向引用后面的单例 B` | **PASS** |

全部 check/interp/compiled 均为 rc=1，诊断一致，无“编译路径才失败”或“只报未定义”。

### 2.3 补充探针

| 探针 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `abstract singleton` | rc≠0 | `TY-222` @1:20（三路径） | **PASS** |
| 手动 `instance` | rc≠0 | `TY-215` @2:9（三路径） | **PASS** |
| 单例构造器 | rc≠0 | `TY-201` @3:6（三路径） | **PASS** |
| 泛型单例 | rc≠0 | `SYN-101` @1:12（三路径） | **PASS** |

---

## 三、边界（不改变本轮全表判定）

按 ADR-005「BND-07 暂只做 sema」，以下 codegen 项不在本轮全表范围，已记录：

| 项 | 现状 | 证据 |
|---|---|---|
| 单例静态字段/方法 | sema+interp 可用（`7`）；compiled `单例静态字段暂未支持` | `probe-bnd07_static_ok/` |
| 初始化式引用前面单例 | sema+interp 可用（`1`）；compiled `字段初始化式访问了成员 value` | `probe-bnd07_prev_ref_ok/` |
| `instance` GC 分类 | 全局 `rt_arc_new` 句柄进程常驻；GC 分类由 E5 | `impl/internal/codegen/singleton.go` |

建议后续 E4/E5 卡关闭；不影响本次全表 PASS。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND0708SingletonFactory' -count=1` | PASS |
| `go test ./internal/interp -run 'TestS2SingletonRuntime' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2BND07Singleton' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、证据

- `evidence/S2-QA/BND-07-0177c80/matrix.tsv`
- `evidence/S2-QA/BND-07-0177c80/S2-BND07-A01/{check,interp,compiled}/`、`A02/{check,interp,compiled}/`
- `evidence/S2-QA/BND-07-0177c80/S2-BND07-R01-{implements,inherit,new,write}/{check,interp,compiled}/`
- `evidence/S2-QA/BND-07-0177c80/S2-BND07-R02-fwd/{check,interp,compiled}/`
- `evidence/S2-QA/BND-07-0177c80/probe-*/`
- `evidence/S2-QA/BND-07-0177c80/gotest-sema/`、`gotest-interp/`、`gotest-codegen/`、`regression-*/`
- 夹具：`difftest/s2/bnd07/`
