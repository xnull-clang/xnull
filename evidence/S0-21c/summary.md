# S0-21c 切换构建与删除 Python

## 改动

| 文件 | 改动 |
| --- | --- |
| `impl/runtime/build_rt.sh` | `python3 ../tools/gen_resources.py` → `(cd .. && go run ./cmd/xnull dev res "$XNULL_RES_DIR" "$XNULL_RES_C")` |
| `impl/tools/check_specs.py` | 删除（`git rm`） |
| `impl/tools/gen_ledger.py` | 删除（`git rm`） |
| `impl/tools/gen_resources.py` | 删除（`git rm`） |
| `impl/README.md` | 目录说明改为 `internal/devtool/`；新增「内部维护工具（xnull dev）」一节，写明 `build_rt.sh` 用 `go run` 且不进入运行时产物 |
| `impl/docs/xdk-design.md` | 资源表生成器改指 `xnull dev res` |
| `impl/docs/conformance/ledger-restructure.md` | 两处 `gen_ledger.py` → `xnull dev ledger` |
| `XNull一致性用例台账-v1.0.0.md` | 头部生成器名 → `xnull dev ledger`（其余 101 行内容不变） |

`go run` 与已构建二进制二选一的结论：**用 `go run ./cmd/xnull`**。理由：build_rt 是仓库内构建期调用，`go run` 复用模块缓存、无需约定二进制安装路径；且生成的 C 源不依赖 Go，运行时产物不携带 Go 运行时（v1.4.0 §4.3）。

## 验证

| 项 | 命令 | 结果 |
| --- | --- | --- |
| C 运行时构建 | `sh impl/runtime/build_rt.sh` | 退出码 0（11.3s），含资源表测试「资源表测试通过」 |
| Python 归零 | `find impl -name '*.py'` | 0 |
| Python 引用 | `git grep -n 'impl/tools/.*\.py' -- ':!*.md'` | 1 处，见下 |

## 指标冲突（需董事会裁决）

`git grep 'impl/tools/.*\.py'`（v1.4.0 §7 第 7 项）与第 6 项「资源生成器 sha256 逐字节一致」在字面上互斥：

- 生成的 C 文件首行是 Python golden 的一部分：`/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。`
- 要让 sha256 相同（第 6 项），Go 必须原样输出这一行；
- 该行落在 `impl/internal/devtool/resources.go`，于是第 7 项 grep 命中 1 次。

处理：保留该行为**冻结的 golden 头**（不写死为可执行引用，仅生成期字符串），其余位置已清理为 0。建议 S0-25（D1 子目录修正）一并把该行改为 `xnull dev res` 并重取 golden、同步修订第 7 项命令的例外说明。**本卡不擅自改头，以免第 6 项失守。**

## 结论

构建切换完成，Python 文件归零，`build_rt.sh` 退出码 0。
