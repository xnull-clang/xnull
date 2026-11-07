# 验收：S5-SYNC-03（Atomic）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `6c0609b`（含 S5-03 `63d15e6`）
> **时间**：2026-11-08
> **证据**：`evidence/S5-QA/SYNC-03/`
> **依据**：S5 §7、SYNC-03；S3 §11.3
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `AtomicInt` load/store/CAS | **PASS**：1→5→9；失败 CAS 返回 0 |
| `AtomicBool` load/store/CAS | **PASS**：0→1→0 |
| `AtomicRef` retain/release + CAS | **PASS**：refcount 正确；3 个 box 全部 deinit |
| seq_cst 顺序 | **PASS**：运行时使用 `_Atomic` + seq_cst 操作 |
| 静态类型规则 | **PASS**：`AtomicRef<Int>` 拒绝、store 类型检查 |
| 跨任务未同步共享保守按 GC | **BOUNDARY**：由 S3-03/S5-04 逃逸分析承担；本卡未单列运行期断言 |

**判定：PASS。** AtomicInt/Bool/Ref 的原子操作与引用计数合同成立；静态逃逸保守判定归 S3-03/S5-04，另有边界记录。

---

## 二、实测

```text
sync tests passed (channel/mutex/atomic/cancel)
```

`test_atomics`：
- Int：load 1 → store 5 → CAS(5,9)=1 → load 9 → CAS(5,1)=0。
- Bool：0→1→CAS(1,0)=1→0。
- Ref：new(a)+1、store(b)、CAS(b,c)、失败 CAS；释放后 `g_box_deinit=3`。

---

## 三、证据

- `evidence/S5-QA/SYNC-03/matrix.tsv`
- `runtime-build.log`
- `sema.log`
- `收件箱/回执箱/回执-S5-03-E5.md`
