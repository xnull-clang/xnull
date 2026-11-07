# 验收：S2-SINGLE-01（单例）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `6e37d88`（`6e37d88d3371a827d1ccec4849946ebf927342c4`；含 E4 `a9144c1` SINGLE-01 codegen：静态成员 + 前序单例引用）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-single`，sha256 `9b937825026fc2d4a5583eae5b02c20dbcb708cd4f62e0709e704c28579a6e57`
> **证据**：`evidence/S2-QA/SINGLE-01-6e37d88/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §9.1–§9.4、§18 SINGLE-01
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `instance` 自动提供、字段/方法可读 | **PASS**：双路径 `XNull\n6` |
| `instance` 只读，不能赋值/置 null | **PASS**：`TY-215` @3:12 |
| 单例不能 `new` | **PASS**：`TY-216` @3:17 |
| 单例不能继承 | **PASS**：`TY-202` @2:7 |
| 单例不能实现协议 | **PASS**：`SYN-101` @2:19 |
| 启动前完成初始化（`main` 前可见） | **PASS**：双路径 `localhost\n8080` |
| 静态字段/静态方法 | **PASS**：`Config.base=7`、`Config.twice()=14`；静态字段可读写 `1/5/6` |
| 初始化式引用前面的单例 | **PASS**：`Derived.v = Config.instance.port + 1` → `9` |
| 前向引用拒绝 | **PASS**：`TY-222` @2:23 |
| `instance` 进程常驻 | **PASS（可观察）**：全局句柄；GC 分类归 E5 |

**判定：PASS。** E4 `a9144c1` 已闭合单例静态字段/方法与前序单例引用；A01–A04 双路径输出一致，R01–R03 全部命中专用诊断与位置。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | interp | compiled | 判定 |
|---|---|---|---|---|
| `a01_instance_ro` `AppInfo.instance.name/twice()` | `XNull\n6` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a02_startup` `Config.instance.host/port` | `localhost\n8080` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a03_static_prev` 静态字段/方法 + 前序单例引用 | `7\n14\n8\nlocalhost\n9` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a04_static_write` 静态字段读写 + 静态方法内写 | `1\n5\n6` | 一致，rc=0 | 一致，rc=0 | **PASS** |

### 2.2 负例（三路径一致）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `r01_new` `new AppInfo()` | rc≠0 + 单例诊断 | `3:17 error[TY-216]` | **PASS** |
| `r01_write_instance` `AppInfo.instance = null` | rc≠0 + 只读诊断 | `3:12 error[TY-215]`（另有 `TY-103`） | **PASS** |
| `r02_inherit` `class Sub : AppInfo` | rc≠0 + 不可继承 | `2:7 error[TY-202]：父类必须是 class（得到 singleton）` | **PASS** |
| `r02_implements` `singleton ... implements P` | rc≠0 + 位置 | `2:19 error[SYN-101]：单例头部不能带参数或继承` | **PASS** |
| `r03_fwd` A 引用后面的 B.instance | rc≠0 + 前向引用 | `2:23 error[TY-222]` | **PASS** |

---

## 三、边界

| 项 | 现状 |
|---|---|
| `instance` GC 分类 | codegen 用全局 `rt_arc_new` 句柄；进程常驻可观察一致，固定 GC 语义归 E5 |
| 单例 `deinit` 退出期调用 | 规范不保证，不纳入本锚点 |

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2SINGLE01\|TestS2BND07Singleton' -count=1` | PASS |
| `go test ./internal/sema -run 'TestS2BND0708SingletonFactory\|TestS2BND07SingletonRules' -count=1` | PASS |
| `go test ./internal/interp -run 'TestS2SingletonRuntime' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 五、证据

- `evidence/S2-QA/SINGLE-01-6e37d88/matrix.tsv`
- `evidence/S2-QA/SINGLE-01-6e37d88/S2-SINGLE-a01_instance_ro/{check,interp,compiled}/` … `a04_static_write/`
- `evidence/S2-QA/SINGLE-01-6e37d88/S2-SINGLE-r01_new/`、`r01_write_instance/`、`r02_inherit/`、`r02_implements/`、`r03_fwd/`
- `evidence/S2-QA/SINGLE-01-6e37d88/gotest-codegen/`、`gotest-sema/`、`gotest-interp/`、`regression-*/`
- 夹具：`wt/qa-1/difftest/s2/single01/`
