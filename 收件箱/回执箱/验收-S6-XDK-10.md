# 验收：S6-XDK-10（资源读取）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `44d7681`（含 E4 XDK-10 绑定端到端；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-10/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 5 API：exists/size/read/readText/list | **PASS**：runtime + codegen + CLI 端到端 |
| 资源表进入构建并运行 | **PASS**：`TestS6_04ResourceEndToEnd`、`TestS6Xdk10CheckBuildRun` |
| 非法路径（绝对/`..`/空段/反斜杠）→ `InvalidArgument` | **PASS**：`test_res_api` |
| 缺失 → `NotFound` | **PASS**：`test_res_api` |
| `listResources` 字典序 | **PASS**：runtime 用例 |
| 无 `close` | **PASS**：API 面无 close |
| 可取消 | **PASS**：Context 首参 + runtime |
| 不回退 FS / 文件 API 读不到资源 | **PASS**：runtime 约束用例 |
| `check` 与 `build` 注入面一致 | **PASS**：`TestS6Xdk10CheckBuildRun`（`resourceExists(1)` 被 check 拒绝） |

**判定：PASS。** 资源 5 API 的声明注入、资源表链接、check/build 一致性与运行时 7 条约束均通过；CLI 端到端输出 `true/size-ok/rb-ok/rt-ok/rl-ok`。

---

## 二、实测

### 2.1 发射面

`codegen-xdk10.log`：

- `TestS6_04ResourceSurface` PASS：生成 C 含 `xdkc_resource_exists/size/read/read_text/list/list_free` 与 `xn_Result_Bytes_Text_List_Error`。
- `TestS6_04ResourceEndToEnd` PASS：真实资源表 + runtime 运行。

### 2.2 CLI 端到端

`cli-xdk10.log`：

- `TestS6Xdk10CheckBuildRun` PASS：
  - `check` 合法程序 rc=0；`resourceExists(1)` 被拒。
  - 资源表构建 + 运行输出。

真实 CLI 复验（`XDK-10/cli-build-resources/`）：

```bash
xnull build source.x --resources <dir> -o prog && ./prog
```

```text
true
size-ok
rb-ok
rt-ok
rl-ok
strings=1   # 产物内命中 a.txt
```

### 2.3 运行时 7 约束

`runtime.log`：

```text
资源表测试通过
资源 API 测试通过（5 API / 7 约束）
```

`test_res_api.c` 覆盖非法路径、缺失、字典序、无 close、取消、不回退 FS、文件 API 隔离。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-10/codegen-xdk10.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-10/cli-xdk10.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-10/runtime.log`
- 断言依据：S6 §4.8/§10 XDK-10
