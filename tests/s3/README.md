# S3 参考用例（MEM-05/06/03）

- 用途：QA 独立验收 S3 的参考输入；E2 仅提供用例与期望，不修改生产代码。
- 运行：
  ```bash
  bash tests/s3/run.sh --root .            # 解释路径（默认）
  bash tests/s3/run.sh --root . --compiled # 解释+编译路径
  ```
- 判定：stdout 与 `<case>.expect` 逐字节一致、退出码 0。
- MEM-05 栈分类：`none.x`/`return.x`/`other.x` 共享同一语义输出，差异在 E4 栈发射（当前 compiled 可能 BLOCKED）。
- MEM-06 容器 GC：`array/list/mapset/gc_elem/holder` 覆盖 T[]/List/Map/Set、GC 元素、clear/remove、容器字段。
- MEM-03 混合图：`identity/cycle/container_cycle` 覆盖对象身份、直接环、容器中介环；GC 回收/不泄漏需 E5 运行期压力用例。
- 现有状态：解释路径 11/11 PASS；编译路径中 MEM-05 栈发射与 MEM-06 GC 化可能 BLOCKED，按 E4/E5 落地后复跑。
