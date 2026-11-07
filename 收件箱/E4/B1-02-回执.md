# 回执：B1-02（XNull 版 xnfmt）

| 字段 | 内容 |
|---|---|
| 卡片ID | B1-02（XNull 版 xnfmt 实现） |
| 角色/线 | 自举线 E4（`wt/e4-codegen` / `pod/e4-codegen`） |
| 结论 | **DONE**（实现 + 差分 0；诊断 3/4，非法 UTF-8 待运行时 API） |
| 改动 | 采用 `wt/c3-rd1@c3d5ca6` 的 XNull 初版并修复：①`$"…"` 插值串整体成 token；②`===` 成单 token；③数字扫描不再吞 `p.1.length()` 的点后标识符；④一元 `!` 与 `(` 间 0 空格；⑤`case (` 关键字后 1 空格；⑥头部之外独立注释计入 import 区段并补 R9.1 段间空行；⑦新增 `pathExists` 绑定与 FMT-104 诊断（缺文件/目录/无参数，写 `/dev/stderr`，rc=2）。支撑改动：`impl/internal/codegen` 支持 FFI `Bool` 标量返回。 |
| 验证 | `cd impl && go build -o /tmp/xnull ./cmd/xnull && XNULL_RUNTIME=runtime /tmp/xnull build xnfmt/xnfmt.x -o /tmp/xnfmt-x`；B1-03 差分 0（见 `evidence/M6-B1-03/e4/rerun/`）；`go test ./internal/xnfmt ./cmd/xnfmt` 绿；`go test ./...` 绿。 |
| sha | 代码+证据提交 `0d8c985`（pod/e4-codegen）；XNull 版二进制 sha256 `699c3006caf94adc6a430f4cf48632f3c955a108e4b88f2f393dc895b61bd8fd`；Go oracle `7acfc46bd0b1341f212fd7963e109d137e2bc2c27e662d7afddd3eb4a8d6803e`。 |
| 证据路径 | `evidence/M6-B1-03/e4/`（`rerun/` 为权威重跑：`diff-*` 空、`*-idem-*` 空、`artifact.sha256`、`env.txt`、`go-test-all.log`）；`handoff/B1-02.md`。 |
| 未测/风险 | ①非法 UTF-8 仍静默接受（需 E5 `xdkc_utf8_valid`）；②批处理仍一文件一进程（同进程多文件曾信号 11）；③`rt_string*`/`xrt_string*` 类型告警（P-08 迁移未做，布局兼容）。 |
| 下一步 | E5 交付 utf8 校验入口 → E4 补第 4 项诊断；QA1 独立复验 B1-03。 |
