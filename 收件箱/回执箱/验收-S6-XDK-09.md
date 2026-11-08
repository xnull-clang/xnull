# 验收：S6-XDK-09（sys / net）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（运行时、sema、compiled E2E、Result 成员、错误/取消/关闭全部通过）
> **复验点**：main `ba60c61`（含 E2 `6ad665c` XDK-09d、E4 `c7b33cf` XDK-09d，以及 E5 XDK-09c、E4 XDK-09b）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-09d/`
> **依据**：S6 §4.7、XDK-09、ADR-009；`收件箱/门/S6-09验收用例-E2.md`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `build_rt.sh` 链接 | **PASS**：exit 0，`net tests passed (socket plain/close + http get/post/status)` |
| sema：socket plain/Async、`net.http`、`HttpResponse` 导入 | **PASS**：`TestS609NetSignatures/NetNegative/HttpResponseImport/HttpResponseHint` |
| `net.x` 单元/合同/loader | **PASS**：`TestS609NetUnitSurface/Contracts/Loader` |
| compiled E2E：socket plain/Async close | **PASS**：stdout `true/true`，生成调用面 `xdkc_socket_connect_async(`、`xn_ffi_socketClose(` |
| compiled E2E：`net.http` getAsync/status/body/close | **PASS**：stdout `true/200/hello/true` |
| compiled E2E：`Result<HttpResponse, ErrorKind>` 成员/解包 | **PASS**：`TestS609HttpResponseResultMember`，生成 `xn_Result_HttpResponse_ErrorKind` |
| runtime plain socket | **PASS**：connect/write/read/close；句柄 close 幂等 |
| runtime `net.http` | **PASS**：get/post/404；404 → code=3 |
| 错误映射 | **PASS**：InvalidArgument code=1；connect 失败 code!=0；不静默成功 |
| 取消/超时 | **PASS**：deadline 到期 → `code=3 Cancelled`（`connect_async`/`recv_async`），非 Timeout/Io |
| 资源关闭 | **PASS**：`xrt_handle_close` 两次均 0，`xrt_handle_native` 置 NULL |
| NET-01..05 用例文件 | **BLOCKED**：`tests/s6/xdk09/` 仍未落盘（覆盖等价物见下） |
| interp 路径 | **BLOCKED**：解释路径未接 |

**判定：PASS。** 上一轮两处红（`Result 成员类型 HttpResponse 未支持（S4-02）`、`RES-105` 导入）已由 E2/E4 XDK-09d 关闭；运行时链接与取消/关闭语义实测通过。

---

## 二、实测

```text
$ sh impl/runtime/build_rt.sh                      # exit 0
net tests passed (socket plain/close + http get/post/status)

$ cd impl && go test ./internal/codegen -run TestS609 -count=1 -v
PASS TestS609SocketPlainAndAsyncClose
PASS TestS609HTTPGetAsync
PASS TestS609HttpResponseResultMember
PASS TestS609NetUnitSurface
PASS TestS609NetContracts
PASS TestS609NetLoader

$ go test ./internal/sema -run TestS609 -count=1 -v
PASS TestS609NetSignatures / TestS609NetNegative
PASS TestS609dHttpResponseImport / TestS609dHttpResponseHint

$ sh evidence/S6-QA/XDK-09d/run.sh                 # QA 补充夹具
qa net cancel/error/close passed (code=3 cancelled, code=1 invalid, close idempotent)
```

---

## 三、覆盖等价与边界

| NET 用例 | 等价执行证据 | 状态 |
|---|---|---|
| NET-01 plain socket | runtime `test_plain_socket`；compiled `TestS609SocketPlainAndAsyncClose` | 已覆盖（非 `.x` 夹具） |
| NET-02 Async + 取消 | QA 夹具 `qa_net_cancel.c`：deadline → code=3 | 已覆盖（非 `.x` 夹具） |
| NET-03 Listener Async | E2 用例文件未落盘 | **BLOCKED** |
| NET-04 `net.http` | compiled `TestS609HTTPGetAsync`；runtime get/post/404 | 已覆盖（header 未单测） |
| NET-05 错误映射 | runtime `test_errors` + 404；QA 夹具 InvalidArgument | 已覆盖 |

| 边界 | 说明 |
|---|---|
| `tests/s6/xdk09/NET-01..05` `.x/.expect` | 仍未落盘；E2 侧用例文件缺口，不影响本轮实现面判定 |
| interp 路径 | 未接；S6-09 用例文档要求的双路径逐字节一致暂不可执行 |
| HTTP | E5 最小实现，无 TLS/重定向；`header` 读取未在本轮断言 |

---

## 四、证据

- `evidence/S6-QA/XDK-09d/matrix.tsv`
- `build_rt.log`（exit 0 + net tests passed）
- `codegen-s609.log`（6/6 PASS，含 `Result<HttpResponse>` 回归用例）
- `sema.log`（签名/负例/导入 4/4 PASS）
- `qa-cancel.log`、`qa_net_cancel.c`、`run.sh`（取消/错误/关闭夹具）
- `source-contract.txt`（`s609_test.go`、`test_net.c` 摘录）
- `收件箱/回执箱/回执-S6-09d-E2.md`、`回执-S6-09d-E4.md`
- `收件箱/门/S6-09验收用例-E2.md`
