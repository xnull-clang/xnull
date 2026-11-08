# 回执：S3 参考用例（MEM-05/06/03）

- **状态**：`DONE`（只加用例，不改生产代码）
- **目录**：`tests/s3/{mem05,mem06,mem03}/`，每例 `.x + .expect`；执行器 `tests/s3/run.sh`；说明 `tests/s3/README.md`。
- **MEM-05**：`none.x`（局部）、`return.x`（返回）、`other.x`（字段/参数）三类；解释路径 3/3 PASS，栈发射在 E4。
- **MEM-06**：`array.x`/`list.x`/`mapset.x`/`gc_elem.x`/`holder.x`，覆盖 T[]/List/Map/Set、GC 元素、remove/clear、容器字段；5/5 PASS。
- **MEM-03**：`identity.x`/`cycle.x`/`container_cycle.x`，覆盖对象身份、直接环、容器中介环；3/3 PASS；GC 回收/泄漏压力归 E5。
- **运行**：`bash tests/s3/run.sh --root .`（默认解释）；加 `--compiled` 跑双路径。
- **验证**：解释路径 11/11 PASS。
