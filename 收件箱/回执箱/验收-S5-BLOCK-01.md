# 验收：S5-BLOCK-01（@tasks 块）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `6c0609b`（含 S5-05 语言面）
> **时间**：2026-11-08
> **证据**：`evidence/S5-QA/BLOCK-01/`
> **依据**：S5 §2.3、BLOCK-01；S5-05 E2 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `@tasks` 块外使用任务 API | **PASS**：`TY-227` @3:24 |
| `@tasks` 块内放行 | **PASS**：`check` rc=0 |
| 任务 env 按 external root 处理 | **PASS**：`test_env_root`：join 前 weak 可见，collect 后 weak=NULL |
| 块内提交/根注销 | **PASS**：`xrt_task_root_bind/unbind` + test_env_root |

**判定：PASS。** `@tasks` 是任务 API 的编译期门；块外调用被 `TY-227` 拒绝，块内可用；任务 env 外部根在 join 后注销。

---

## 二、实测

```text
$ xnull check outside.x
outside.x:3:24: error[TY-227]: 任务 API `background` 只能在 @tasks 方法/块内使用（S5 §2.3）

$ xnull check inside.x
exit 0
```

`test_env_root`：spawn(env) → join → `xrt_weak_read(w)==env`；`rt_gc_collect()` 后 `weak==NULL`（根已注销）。

---

## 三、证据

- `evidence/S5-QA/BLOCK-01/matrix.tsv`
- `outside.x` / `.err`、`inside.x` / `.err`
- `runtime-build.log`（test_env_root）
- `sema.log`（TestS5TasksSemaSurface）
- `收件箱/回执箱/回执-S5-05-E2.md`
