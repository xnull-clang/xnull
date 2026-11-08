# 验收：S6-XDK-09（sys / net）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（sema/net.x 单元面通过；compiled E2E 与 net 运行时链接未闭合）
> **复验点**：main `4adbce3`（net 四线 b0cbf04/57b1b0a/fea33f2/985d9f9 合入后）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-09b/`
> **依据**：S6 §4.7、XDK-09、ADR-009；`收件箱/门/S6-09验收用例-E2.md`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| sema：socket plain/Async、net.http 签名 | **PASS**：`TestS609NetSignatures/NetNegative` |
| net.x 类型/入口/合同/loader | **PASS**：`TestS609NetUnitSurface/Contracts/Loader` |
| socket plain/Async compiled E2E | **FAIL**：`codegen：返回表达式 *xfront.Member 未支持（M4.1）` |
| `net.http` `httpGet(ctx,url)` compiled E2E | **FAIL**：同一 Member 返回缺口 |
| net 运行时链接 | **FAIL**：`test_net` 缺 `xdkc_socket_*`、`xrt_bytes_from_c` 符号；`build_rt.sh` exit 1 |
| S6-09 NET-01..05 双路径夹具 | **BLOCKED**：`tests/s6/xdk09/` 未落盘 |
| 错误映射/取消/超时/资源关闭 | **BLOCKED**：compiled/runtime 路径未跑通 |

**判定：FAIL。** 语言面（sema + net.x 单元）成立；E4 调用点与 E5 运行时 ABI 仍不一致，无法按 NET-01..05 双路径签 PASS。

---

## 二、精确缺口（按归属）

| # | 缺口 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | codegen 不支持 `r.value()` 成员返回表达式（Socket/Bytes） | `codegen-s609.log` | E4 |
| P-02 | `rt_std_net.c` 导出 `xdkc_net_*`，`test_net.c`/xfb 期望 `xdkc_socket_*` | `runtime-build.log` | E5/E4 ABI |
| P-03 | `xrt_bytes_from_c` 未链接到 net 测试目标 | `runtime-build.log` | E5/E6 |
| P-04 | NET-01..05 `tests/s6/xdk09/*.x` 与 `.expect` 未落盘 | `S6-09验收用例-E2.md` | E2/E6 |
| P-05 | net.http `Response.status/body` 返回/错误映射未进 compiled E2E | `codegen-s609.log` | E4 |

---

## 三、已通过面

```text
$ go test ./internal/sema -run TestS609 -count=1 -v
PASS TestS609NetSignatures / TestS609NetNegative

$ go test ./internal/codegen -run 'TestS609NetUnitSurface|TestS609NetContracts|TestS609NetLoader'
PASS（3/3）
```

---

## 四、放行条件

1. E4：`r.value()` / `Response.status/body` 等 Member 返回表达式编组。
2. E5/E4：统一 `xdkc_socket_*` ABI（或 xfb/test 对齐），补齐 `xrt_bytes_from_c`。
3. E2/E6：落盘 `tests/s6/xdk09/NET-01..05` 与 `.expect`。
4. 复跑 `TestS609SocketPlainAndAsyncClose`、`TestS609HTTPGetAsync` 与 NET-01..05 双路径；`build_rt.sh` exit 0。

---

## 五、证据

- `evidence/S6-QA/XDK-09b/matrix.tsv`
- `codegen-s609.log`（2 个 E2E FAIL）
- `codegen-unit.log`、`sema.log`（语言面 PASS）
- `runtime-build.log`（link 失败）
- `source-contract.txt`
- `收件箱/门/S6-09验收用例-E2.md`
