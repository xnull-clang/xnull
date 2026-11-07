# 验收：S7-FFI-07（阻塞分类 / 伴生执行器）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E4 FFI-07 路由 `c156108`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S7-QA/FFI-07/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `.unaware + @longRunning` 调用点 → `xrt_companion_submit/wait` | **PASS**：生成 C 含 submit/wait/thunk；运行在伴生 worker |
| 清单 companion 只认注册表 | **PASS**：存在才报告，不按命名推导 |
| companion 缺失拒绝 | **PASS**：`FFI-107` + 位置 |
| 跨文件 companion 可见 | **PASS** |
| 清单排序/行数/分类 | **PASS** |
| 64 并发 + 16 取消风暴 + 载体不受阻 | **PASS**：`pool=4, stress=64+cancel=16, carrier-free` |
| 分类缺失 `@blocking` | **PASS**：`FFI-107` |

**判定：PASS。** E4 的调用点路由与清单注册表校验落地后，FFI-07 的路由、一致性与压力用例全部通过。

---

## 二、路由端到端

`ffi07-tests.log`：

```text
TestFFI07CompanionRoutingEndToEnd  PASS
TestFFI07ManifestCompanionRegistry PASS
  companion_存在            PASS
  companion_缺失拒绝        PASS
  跨文件_companion_可见     PASS
  清单不按命名推导          PASS
```

`routing.txt`：

- `ffi_gen.go:617` 生成 `xrt_companion_submit(xn_companion_ffiExec_thunk, ...)`。
- `ffi_gen.go:621` 生成 `xrt_companion_wait(...)`。
- `load.go` 全局校验 `submit<Entry>` 是否存在，缺失 → `FFI-107`。
- `emit.go` 清单只在 `r.Entry("submit"+Name)` 存在时填 `Companion`。

端到端夹具中 `native_exec` 返回 `xrt_companion_on_worker() ? x : -1`；构建产物运行 stdout=`7`，证明调用发生在伴生 worker。

---

## 三、压力/一致性

`runtime.log`：

```text
task tests passed (... pool/companion)
companion tests passed (pool=4, stress=64+cancel=16, carrier-free)
```

覆盖：64 长阻塞并发、伴生池忙时普通任务 200ms 内完成、16 个取消风暴（等待 `Cancelled`，原生继续）、worker 标识。

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S7-QA/FFI-07/ffi07-tests.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S7-QA/FFI-07/runtime.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S7-QA/FFI-07/routing.txt`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S7-QA/FFI-07/vet.log`
- 断言依据：S7 §7.3/§10 FFI-07；S5 §2.2
