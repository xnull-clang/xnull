# S6-04-E6 自检结论（资源表进入产物构建）

## 变更

| 文件 | 内容 |
|---|---|
| `impl/internal/codegen/build.go` | `runtimeCSources` 追加 `rt_std_res.c`；`Options.ResC`（工程资源表）；缺省写内置零资源空表（`xrt_resource_count/get/at` 三符号闭合）；`buildCCArgs` 在运行时源之后、LinkArgs 之前追加资源表 |
| `impl/internal/cli/cli.go` | `xnull build --resources <目录>`：用 `devtool.GenerateResources` 生成 `<out>.res.c` 后传入 `Options.ResC`；`knownFlags` 注册 `--resources` |
| `impl/internal/codegen/build_test.go` | 运行源清单含 `rt_std_res.c`；资源表位置断言；带工程资源构建（产物含 `templates/hello.txt`）+ 空表构建 |

## 验证

| 项 | 实测 |
|---|---|
| 带资源构建 | `xnull build examples/hello.x --resources <dir>` exit 0；`strings` 命中 `templates/a.txt`（1 次）；运行输出正常 |
| 无资源构建 | exit 0；产物不含资源名（0 次）；空表符号闭合 |
| 资源表位置 | 在 `rt_std_res.c` 之后、LinkArgs 之前（单测断言） |
| C 运行时 | `build_rt.sh` exit 0；「资源表测试通过」「资源 API 测试通过（5 API / 7 约束）」 |
| 单测 | codegen `TestBuild*` 全过；cli 全过 |

## 缺口（他卡，未越界修）

`impl/internal/codegen/s6_03_test.go`（E4/S6-03，`ef48796`）引用未定义的 `InjectSys603`，导致 codegen 测试包**编译失败**——main 该包本就红。本卡验证时临时移出该文件，未修改其内容；需 S6-03 主责补齐函数或删该用例。
