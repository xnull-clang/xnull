# 回执：B1-02（XNull 版 xnfmt）

| 字段 | 内容 |
|---|---|
| 卡片ID | B1-02（XNull 版 xnfmt 实现） |
| 角色/线 | 自举线 E4（`wt/e4-codegen` / `pod/e4-codegen`） |
| 结论 | **DONE**（实现 + 差分 0；诊断 6/6，FMT-101/102/104 与 Go oracle 码型对齐） |
| 改动 | 采用 `wt/c3-rd1@c3d5ca6` 的 XNull 初版并修复：①`$"…"` 插值串整体成 token；②`===` 成单 token；③数字扫描不再吞 `p.1.length()` 的点后标识符；④一元 `!` 与 `(` 间 0 空格；⑤`case (` 关键字后 1 空格；⑥头部之外独立注释计入 import 区段并补 R9.1 段间空行；⑦`pathExists` 绑定 + FMT-104（缺文件/目录/无参数）；⑧`utf8Valid` 绑定 + FMT-102（非法 UTF-8）；⑨词法未闭合（字符串/字符/块注释）→ FMT-101。支撑改动：`impl/internal/codegen` 支持 FFI `Bool` 标量返回。 |
| 验证 | `cd impl && go build -o /tmp/xnull ./cmd/xnull && XNULL_RUNTIME=runtime /tmp/xnull build xnfmt/xnfmt.x -o /tmp/xnfmt-x`；`./evidence/M6-B1-03/e4/run.sh f63fcba` 全 0；`go test ./...` 绿。 |
| sha | 实现+证据提交 `cac6686`（pod/e4-codegen）；E5 运行时交付 cherry-pick `2948e82`（原 `c9e8a5d`）。重跑产物 sha256 见 `evidence/M6-B1-03/e4/rerun/artifact.sha256`。 |
| 证据路径 | `evidence/M6-B1-03/e4/`（`run.sh`、`acceptance.md`、`summary.md`、`rerun/`）；`handoff/B1-02.md`。 |
| 未测/风险 | ①诊断位置统一 `0:0`（Go 为精确 line:col），码型/退出码已对齐；②批处理仍一文件一进程（同进程多文件曾信号 11）；③`rt_string*`/`xrt_string*` 类型告警（P-08 迁移未做，布局兼容）。 |
| 下一步 | QA1 独立复验 B1-03；通过后 B1 门可判过。 |
