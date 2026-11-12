# tests/b3 已标记 legacy（B4c-02b）

`tests/b3/` 下的脚本（`xnullc_all.sh`、`xnullc_all.py`、`dual-path.sh`、`emit-diff.sh`、
`xnullc-bundle.sh` 等）依赖 **Go 工具链**（`go build ./cmd/xnull`、`./cmd/xnast`、`./cmd/xnfmt`），
而 Go 代码已在 B4c-02b 删除。

- 这些脚本**仅作历史存档**，不再作为任何门禁/CI 步骤；
- 现行验证入口：`tests/b4/verify-golden.sh`（142 入口 C / 97 负例 / 9 示例）与 `ci/run.sh`；
- 如需复用，请在保留 Go 的历史提交（B4c-02a 及之前）上运行。
