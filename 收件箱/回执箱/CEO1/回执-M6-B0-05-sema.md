# 回执-M6-B0-05-sema

**状态：DONE（sema 一处）**

1. **变更**：`impl/internal/sema/ty.go` 的 `List.remove` 从 `void` 拆出，返回 `V`（`genericArg(k, "List<")`）；`push/insert/set/clear` 仍为 `void`。
2. **用例**：新增 `impl/internal/sema/list_remove_test.go`，覆盖 `List<Int>`/`List<String>` 正例、语句丢弃返回值、`Int→String` 负例；未改既有期望。
3. **验证**：目标测试先红后绿；`go test ./... -count=1` 全绿；`go vet ./...` exit 0。
4. **协同**：解释器 `List.remove` 当前仍返回 `vNull`、codegen 仍为 void；按卡面由 E3/E4 同批提交值返回，本卡未跨域修改。
5. **证据**：`evidence/M6-B0-05-sema/`（七件套 + `before/` + `after/`）；提交 `pod/e2-sema`，不 push、不合并。

## 边界

- 本卡只负责 sema 返回类型；同批完成前，解释器路径运行 `Int v = xs.remove(0)` 会得到 null，属批次中间态。
- 未改其他锚点文件、未改 `status.tsv`。
