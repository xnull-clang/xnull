# S0-21d 回归与残留

## 结果

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 静态检查 | `go vet ./...` | 退出码 0 |
| 全量测试 | `go test ./... -count=1` | 退出码 1：仅 `internal/codegen` 超时失败（`TestExamplesCompileMatchesInterp/parser-seed.xn`，606s，**P0-1 已知缺陷，非本卡引入**）；cli/ffi/devtool/diag/interp/sema/xfront/xpd 全 `ok` |
| C 运行时 | `sh impl/runtime/build_rt.sh` | 退出码 0（见 S0-21c） |
| 9 示例双路径 | `xnull run --interp` vs `xnull run` | 9/9 stdout 相同、退出码 0（部分示例本身无输出，两路径同样为空） |
| 工作区守门 | 主树 cwd 跑 `dev check` | 退出码 0 |
| 公开布局守门 | `xnull/` cwd 跑 `dev check` | 退出码 0 |
| Python 文件 | `find impl -name '*.py'` | 0 |
| Python 引用 | `git grep -n 'impl/tools/.*\.py' -- ':!*.md'` | 1（`resources.go` 冻结 golden 头，董事会已登记为指标 7 例外） |

## 供 QA 复跑的二进制

`evidence/S0-21d/bin/xnull`，sha256：

```
5668af912a9ed1742a030f98d8e24ecaa642a30d9196f6e6abc883e9f105a453
```

两布局复跑：

```
(cd /Users/vjs/Desktop/XNull-Lang      && <worktree>/evidence/S0-21d/bin/xnull dev check)  # 0
(cd /Users/vjs/Desktop/XNull-Lang/xnull && <worktree>/evidence/S0-21d/bin/xnull dev check)  # 0
```

## 说明

`go test` 未加 `-timeout`，按默认 10m 跑满后被 codegen 用例拖到 606s；这是 P0-1 的表现，按要求未追、未跳过、未用 `-short`。后续复跑统一加 `-timeout 180s` 并如实记录。
