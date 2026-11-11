# B4b 门：PARTIAL（9 示例管线通，大文件仍阻塞）

- **判定**：`PARTIAL`（B4c 不得启动）
- **时间**：2026-11-11 10:05
- **范围**：`handoff/B4b-c-plan.md`

## 已完成

### B4b-01 Go-free build/run 管线：PASS

- `tests/b4/xnull-build.sh`：`build`/`run`/`verify`/`examples`；
- 管线：`xnast --ast`（Go oracle，B4c 前允许）→ native xnullc → cc →
  可执行；
- 9 示例：C 与 Go `--emit-c` 逐字节一致、二次生成一致、三路运行一致。

### B4b-02 native xparser：PARTIAL

- `impl/lib/b2/xparser.x` 新增 `--file`/`--diags --file`（`xdk.sys.readFileText`），
  保留源码字符串模式；
- native xparser 构建成功；
- **9 示例 AST 与 `xnast --ast` 逐字节一致**，C/运行一致；
- **大文件阻塞**：`xparser.x` / `xlex.x` / `xnfmt.x` native 解析段错误/0 输出，
  已定位到 runtime/concat 与语言面缺口，属 E6 边界外。

## 未完成

- B4b-02 大文件 native xparser；
- B4b-03 工程模型（manifest/resman/reactor/config）；
- B4b-04 工具（plugin/repro/artifact/xpd/xmeta/tree/why/install）；
- B4b-05 XNull CLI vs Go CLI 全命令对拍；
- B4c 冻结 golden、删除 Go。

## 阻塞

native xparser 对 >1000 行源码（尤其自身）不稳定；CLI 目前对大入口仍回退
Go `xnast`。B4b 不能以“9 示例”通过收口，需先修大文件解析（concatenation/GC
或 codegen 缺口）。

## 证据

- `handoff/B4b-01.md`、`handoff/B4b-02.md`；
- `tests/b4/xnull-build.sh`；
- 9 示例日志（worktree `/tmp/b4b02-examples.log`，未入库）。

## 判定

B4b **PARTIAL**；B4c 不启动。
