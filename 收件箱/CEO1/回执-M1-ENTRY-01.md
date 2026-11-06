# 回执 M1-ENTRY-01（ENTRY-01 入口与启动）

- 先红：新增 `interp_test.go`/`cli_test.go` 入口用例后首次运行 exit 1——interp 4 项失败（重复入口、非法签名），cli 5 项失败（String[] 入口 cc 报 `xn_p_args` 缺参、TopField 未支持、缺失入口落到 cc、重复入口报“重载”）；原始输出 `evidence/M1-ENTRY-01/before/`。
- 修复：interp 增加入口唯一性/签名校验（缺失、重复、非 static、返回非 void/Int、参数非 String[] 均报编译错误）；codegen 增加 `RequireEntry`（Build 在生成 C 前拒绝缺失入口）、C 入口垫片支持 `String[] args`（argv[1:] 构造新数组）与顶层字段按声明顺序初始化（Int/Bool/String，`xn_init_globals` 先于 `xn_main`）；cli 将非标志参数透传为程序参数，编译/解释一致。
- 验证：`go test ./internal/interp/...`、`./internal/cli/...` exit 0；8 个示例编译/解释双路径逐字节一致；`entry.x` 双路径输出 `init 1/init 2/main t2 args=2`、退出码 7；`gofmt -l`、`go vet` 无输出。
- 证据：`evidence/M1-ENTRY-01/` 七件套（command/stdout/stderr/exit_code/sha/artifact.sha256/acceptance.md）+ `before/` 红输出 + `entry.x`/`entry-bin`/`entry-bin.c`。
- 提交：`pod/e4-codegen` 分支提交 `592e7f7`（不 push、不合并）；改动仅 `impl/internal/{interp/interp.go,interp/interp_test.go,cli/cli.go,cli/cli_test.go,codegen/codegen.go,codegen/build.go,codegen/classes_expr.go,codegen/containers_expr.go,codegen/strmethods.go,codegen/types.go}` 与 `evidence/M1-ENTRY-01/`、本回执；未改既有测试期望、未删测试、未碰 ffi/示例。

## 验收要点逐项

- [x] 入口与启动
- [x] 两种 `main` 签名均可运行（void/Int × 无参/String[] 四形态）
- [x] 退出码正确（Int 直通、void→0、fatal→134、双路径一致）
- [x] 初始化顺序正确（顶层字段按声明顺序先于入口，编译/解释一致）
- [x] 缺失入口被拒绝（编译错误，不落到 cc）
- [x] 重复入口被拒绝（编译错误）

## 未测项

1. 入口 `public` 可见性（private/protected main 拒绝）。
2. 工程清单入口文件/入口包（§11.4 清单模式）。
3. 泛型 main、默认参数、可变参数（语法层未支持）。
4. 非默认包 main 不作为入口（多包编译属 PKG-01）。
5. 顶层字段仅 Int/Bool/String；类引用/容器顶层字段显式报错。

执行侧自检，不构成验收签署（QA L1 / CEO1 L2 未签）。
