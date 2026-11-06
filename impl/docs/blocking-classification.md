# 阻塞分类清单（impl/docs/blocking-classification.md）

> 依据：S6 §9（阻塞分类与调用面）、S5 §9（逐 API 分类清单）、S7 §7.3（`@blocking` + 长阻塞伴生形态）。
> 生成源：仓库内 `bindings/**/*.xfb` 的注册表。清单与注册表的一致性由自动化用例
> （`internal/codegen/ffi` 的 `TestBlockingClassificationDocInSync`）机械核验——改绑定必须同步本表，否则测试失败。

## 1. 分类语义

| 分类 | 含义 | 调用面要求 |
| --- | --- | --- |
| `.aware` | 不会长时间占用执行器；快速返回或只做内存/系统调用 | 可在任务内直接调用 |
| `.unaware` | 可能阻塞执行器（文件/网络/同步系统调用） | 长阻塞必须提供专用执行器伴生入口 `submit<Entry>`（S7 §7.3） |

长阻塞（`@longRunning`）且 `.unaware` 的入口，注册表要求同区域存在 `submit<Entry>`，否则构建失败（`FFI-107`）。

## 2. 逐入口清单（当前绑定面）

| 入口 | 原生符号 | 区域 | 分类 | 长阻塞 | 伴生入口 |
| --- | --- | --- | --- | --- | --- |
| diagnose | xdkc_diagnose | xdkc_runtime | .aware | 否 | — |
| exit | xdkc_exit | xdkc_runtime | .aware | 否 | — |
| dirClose | xdkc_dir_close | xdkc_sys | .aware | 否 | — |
| dirOpen | xdkc_dir_open | xdkc_sys | .unaware | 否 | — |
| dirRead | xdkc_dir_read | xdkc_sys | .aware | 否 | — |
| fileClose | xdkc_file_close | xdkc_sys | .aware | 否 | — |
| fileOpenRead | xdkc_file_open_read | xdkc_sys | .unaware | 否 | — |
| fileRead | xdkc_file_read | xdkc_sys | .unaware | 否 | — |
| fileWrite | xdkc_file_write | xdkc_sys | .unaware | 否 | — |
| nowMono | xdkc_now_mono_ms | xdkc_runtime | .aware | 否 | — |
| nowWall | xdkc_now_wall_ms | xdkc_runtime | .aware | 否 | — |
| pathExists | xdkc_path_exists | xdkc_sys | .aware | 否 | — |

## 3. 维护规则

1. 新增绑定入口：先在 `.xfb` 声明 `@blocking(...)`（长阻塞再加 `@longRunning` 与伴生入口），再补本表一行；
2. 分类必须与实现一致（实测阻塞行为）；分类错误按 `FFI-07` 合同违规处理；
3. 本表不手写"总数"等派生数字，避免与注册表漂移；统计以注册表为准。
