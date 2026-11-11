# B4b 门（v1.0.1）：PARTIAL

- **判定**：`PARTIAL`（B4c 不得启动）
- **时间**：2026-11-11 12:45
- **原判定**：`B4b门.md`（PARTIAL）
- **范围**：`handoff/B4b-c-plan.md`

## 新增完成

- **B4b-01**：Go-free build/run 管线，9 示例 9/9（C 逐字节一致、三路运行一致）。
- **B4b-02**：native xparser `--file`；大文件修复完成：
  - `xlex.x` 240,916B、`xparser.x` 1,007,946B、`xnfmt.x` 272,310B
    AST 与 `xnast --ast` **逐字节一致**；
  - `ast-check` 12/12；examples 9/9；
  - 根因：native codegen 对 GC 局部重赋值未补 root（UAF），已在 xparser 侧
    用 `List<E>` 生根 + TP 绕过 + NUL 转义修复。
  - 附带修复：Go build 的 `.xfb` 向上查找（`impl/lib` 入口可找到根 `bindings/`），
    B3-09 复跑 142/0/97。
- **B4b-03a**：XNull `xpd.x`/`manifest.x` + `validate`：
  - `tests/b4/fixtures/proj02` 模块/依赖边/拓扑与 Go 一致；
  - 正例 + 2 负例，`validate-check` 4/4。

## 未完成

- B4b-03b：resman/reactor/config/artifact 完整实现；
- B4b-04：plugin/repro/xpd/xmeta/tree/why/install；
- B4b-05：XNull CLI vs Go CLI 全命令对拍；
- B4c：冻结 golden、删除 Go、无 Go 验证。

## 证据

- `handoff/B4b-01.md`、`B4b-02.md`、`B4b-03-design.md`、`B4b-03a.md`；
- `tests/b4/xnull-build.sh`、`tests/b4/validate-check.sh`；
- `evidence/B4b-xparser-largefile/`（E4）；
- `handoff/B3-09-bindings-path.md`（绑定向上查找）。

## 判定

B4b **PARTIAL**；B4c 不启动。剩余工作量仍大（工程工具 + 全命令对拍 +
去 Go），建议按卡继续或多会话推进。
