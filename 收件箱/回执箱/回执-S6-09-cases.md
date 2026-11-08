# 回执：S6-09 net 验收用例准备

- **状态**：`DONE`（只写用例；不写实现、不签 PASS）
- **用例**：NET-01 plain socket、NET-02 Async+取消、NET-03 Listener Async、NET-04 net.http、NET-05 错误映射；每例含 `.x` 源码、期望输出、运行命令、证据目录。
- **覆盖**：`bind/accept/connect/read/write/close`、`bindAsync/acceptAsync`、`connectAsync/readAsync`、`Context.withDeadline`、`get/getAsync/post`、`Response.status/header/body`、`Network/InvalidArgument/Cancelled`。
- **fixture**：echo（39107）、delay（39108）、http（39109）、closed（39110）；仅固定端口，不依赖外网。
- **状态**：sema 可执行；interp/compiled `BLOCKED`（E5/E4 未接）。文档：`收件箱/门/S6-09验收用例-E2.md`。
