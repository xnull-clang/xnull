# B4b-03 设计：工程模型（manifest / resman / reactor / config / artifact）

- 卡片：B4b-03 设计（只读调研，无代码改动）
- 日期：2026-11-11
- 基线：main `08e21a5`（B4b 门 PARTIAL）、`tests/b4/xnull-build.sh`（B4b-01/02）
- 范围：把 Go 的工程模型（清单/依赖/资源/聚合/配置/制品）在 XNull 侧重实现，供 `build/run/test/install/tree/why` 使用
- 前置状态：B4b-02 大文件 native xparser 段错误未解决（B4b 门 PARTIAL），见 §5.1

## 1. Go 侧现状：包职责、输入输出、数据格式

### 1.0 依赖关系总览

```text
xpd（.project DSL 解析）
  └─ manifest ── Load / ResolveDependencies / graph / lock
        ├─ reactor ── 聚合根 + modules + 拓扑
        └─ cli ─┬─ manifestPipeline（validate→compile→test→package→install）
                ├─ manifest_integration（lock → config → resman → plugin）
                ├─ reactor_build（聚合构建 + reactor-summary.txt）
                └─ deps_commands（install / tree / why）
artifact（.xlib 打包 + 本地仓库安装）
config（六层配置合并）
resman（资源根/glob/冲突）
```

### 1.1 `impl/internal/xpd`（被上面全部依赖）

- 输入：`.project` / `.lock` 文本（XPD DSL：`block { field = value; block { … } }`）。
- 输出：`File` → `Block{Name, Args, Children, Pos}` / `Field{Name, Value}`；位置 `Pos{Line, Col}` 用于诊断。
- 语义错误通过 `[]diag.Diagnostic` 返回（`XPD-0xx` 段），IO 错误走 `error`。

### 1.2 `impl/internal/manifest`

| 入口 | 签名 | 说明 |
|---|---|---|
| `Load` | `(path string, opts Options) (*Resolved, []diag.Diagnostic, error)` | 展开 parent 链（`relativePath`，最多 8 层，`manifest.go:36`）、属性单次替换 `${…}`、合并激活 profile |
| `ResolveDependencies` | `(path, opts) (*Resolved, ds, error)` | `Load` + 依赖版本仲裁 |
| `ResolveGraph` | `(res *Resolved, repoRoot string) (*Graph, ds)` | 传递闭包 + 仲裁（见 1.3） |
| `GenerateLockForGraph` / `ValidateLockForGraph` | — | 锁生成/校验（sha256 来自本地仓库制品） |
| `LoadLock` / `WriteLock` | — | 锁文件读写 |

- `Options{Profiles, Platform, ToolchainVersion, ManagedFallback}`；
- `Resolved{GroupID, ArtifactID, Version, Packaging, Properties, Dependencies(坐标→版本), Build, Configuration, ActiveProfiles, Chain, Plugins, ResourceRoots, Scopes, Exclusions, Managed, Warnings}`。
- **版本仲裁顺序**（`deps.go:22`）：依赖自身版本 > 自身 `dependencyManagement` > 聚合根 `ManagedFallback`；三者都空 → 诊断；只接受精确版本 `X.Y.Z[-pre]`（拒绝范围/SNAPSHOT/LATEST）；显式版本覆盖管理版本 → `Warnings`。
- 继承规则：parent 的 properties/deps/build/config 先合入，子覆盖；`parent.relativePath` 优先于本地仓库解析。

**`xnull.lock` 格式**（`WriteLock`）：

```text
lock {
  version = 1

  entry <group:artifact> <version> {
    kind       = dependency
    repository = central
    sha256     = <64 hex>
  }
}
```

- 条目按坐标排序；`kind ∈ {dependency, plugin}`；sha256 为该坐标本地仓库制品的摘要（取不到即报错，不静默留空）。

### 1.3 `impl/internal/manifest/graph.go`

- `Graph{Selected(坐标→版本), Depth(坐标→最近深度), Paths(坐标→选中路径)}`。
- 规则：最近优先（nearest wins）；同深度多版本 → `XPD-403` 并列出全部路径；`dependencyManagement` 版本恒优先；依赖环 → `XPD-409`；支持 `scope` 与 `exclusions`。

### 1.4 `impl/internal/resman`

| 类型 | 字段 |
|---|---|
| `Root` | `Path`、`Includes`（缺省 `["**"]`）、`Excludes`、`Owner`（`group:artifact`） |
| `Entry` | `ArtifactPath`（`resources/<相对路径>`）、`SourcePath`、`Origin`、`Data` |
| `Set` | `Entries map[ArtifactPath]Entry` |

- `Collect(roots)`：遍历根、按 glob 过滤、同名多源冲突 `XPD-803`；非法根 `XPD-801`、非法 glob `XPD-802`、pom 声明资源 `XPD-804`、断链符号链接 `XPD-805`。
- `CollectForPhase`（main/test）、`CollectForPackaging`（app/library）、`MergeDependency`（依赖带入资源，冲突诊断）。
- glob 语义：`**` 跨目录、`*`/`?` 单段；实现见 `resman.go:238`（**不是** 正则，不能用 `regexMatch` 直接替代）。
- 输出消费方：`devtool.GenerateResourcesFromMap` 渲染 C 资源表（`xrt_resource_count/get/at`，名称按字节序升序、每行 16 字节大写十六进制）。

### 1.5 `impl/internal/reactor`

- `Module{Rel, Dir, GroupID, ArtifactID, Version, Packaging, Deps}`；`Plan{Root, Managed, Modules, Order}`；`Result{Module, Artifact}`。
- 规则：聚合根必须 `packaging = pom`；模块 `packaging ∈ {library, starter, app}`；`starter` 不得含 `src/`，其依赖递归并入使用者；Kahn 拓扑排序、同层按 `modules` 声明顺序（确定性）；`Build` 失败即停（返回已完成结果 + 诊断）。
- 产物：`<root>/target/reactor-summary.txt`，格式 `module <rel> <artifact> <sha256>`，首行 `# reactor 聚合摘要（脚本生成，手改即作废）`。

### 1.6 `impl/internal/config`

- 覆盖层（低→高，枚举 `Layer` 共 6 级；Go 注释里沿用「五层」说法，`configuration` 是额外的第 0 层）：
  `configuration`（父 pom）→ `builtin` → `application`（`src/main/resources/application*.properties`）→ `profile` → `env`（白名单）→ `cli`。
- `Spec{Keys map[string]KeySpec{Kind, Required}, Profiles, EnvWhitelist}`；`Options{ResourcesDir, Profile, Packaging, Configuration, Builtin, Environ, CLI, Audit}`；`Result{Values, Origins(map[key]Origin{Layer,Source,Line}), Audit}`。
- 诊断：`XPD-600`（格式/编码）`XPD-601`（键名）`XPD-602`（同层重复）`XPD-603`（未知键）`XPD-604`（缺必需）`XPD-605`（类型）`XPD-606`（疑似密钥字面量）`XPD-607`（profile 文件名与清单不符）`XPD-608`（非 app 工程出现配置）。
- 放置规则：配置只允许在 app 工程的资源根；环境的 `XNULL_CONFIG_*` 只认白名单。

### 1.7 `impl/internal/artifact`

- `Spec{Root, GroupID, ArtifactID, Version, Packaging, ManifestPath, SourceRoot, ResourceDirs, LockPath, Dependencies}`；`Info{Path, SHA256, Files}`。
- `Build`：把 `xnull.project`（必需）、`xnull.lock`（可选）、`SourceRoot` 与资源目录下全部文件收进 `.xlib`；
  zip 使用 **Store（不压缩）**、条目名排序、时间戳清零（确定性），并生成 `xlib.meta`：

```text
xlib {
  groupId    = <g>
  artifactId = <a>
  version    = <v>
  packaging  = <library|app|…>
  dependency <coord> <version>        ← 按坐标排序
  files {
    <sha256> <相对路径>
  }
}
```

- `RepoDir` = `<repo>/<group 点转斜杠>/<artifact>/<version>/`；`XlibName` = `<artifact>-<version>.xlib`。
- `Install`：把 `.xlib` 与 `xnull.project` 复制到本地仓库目录；远程 `Remote` 接口仅占位（`ErrRemoteUnimplemented`）。

### 1.8 CLI 调用点（现状语义，XNull 需对齐）

| 命令 | 入口 | 行为 |
|---|---|---|
| `xnull build` | `cli/manifest.go:518` | 无 `xnull.project` → 单文件构建；有 → 生命周期 `validate→compile→test→package→install`（`--skip <stage>`） |
| 聚合 `build`（pom 根） | `cli/reactor_build.go:18` | `reactor.Load` → 拓扑逐个构建 → 写 `target/reactor-summary.txt` |
| `xnull install` | `cli/deps_commands.go:61` | library：构建即安装；app：复制产物 + `.xmeta` + `xnull.project` 到本地仓库 |
| `xnull tree` / `why` | `cli/deps_commands.go:119,161` | 打印 `坐标@版本` 树 / 解释某坐标的选中路径 |
| `xnull lock` | `cli/lock.go` | `--update-lock` 生成、默认校验；需 `XNULL_REPO` 解析 sha256 |

**阶段集成**（`cli/manifest_integration.go:44`）顺序固定：锁校验（存在才校验）→ `config.Load` → `resman.CollectForPackaging` + 生成资源表 C → 插件元数据校验 → 计算 `cfg/res/plugin` 三个摘要写进 `.xmeta`。

`.xmeta` 字段顺序固定：`groupId/artifactId/version/packaging/platform/xdkVersion/languageVersion/toolchainVersion/profiles/plugins/configSha256/resourcesSha256/pluginsSha256/lockSha256/inputs`。

## 2. XNull 侧模块划分与最小 API

新增目录 `impl/lib/b4/`（均为 XNull 源码，最终由 native xnullc 编译进 CLI）：

| 模块 | 职责 | 依赖 |
|---|---|---|
| `xpd.x` | `.project`/`.lock` 的 DSL 词法+语法：`Block{name, args, children, pos}`、`Field{name, value}` | 无 |
| `manifest.x` | parent 链、属性替换、profile 合并、`Resolved` 视图 | `xpd` |
| `deps.x` | 版本仲裁、传递图（nearest-wins/冲突/环）、lock 读写与校验 | `manifest`、`fsx` |
| `resman.x` | 资源根收集、glob（`**/*/?`）、冲突、phase/packaging、依赖资源合并 | `fsx` |
| `config.x` | 六层合并、类型校验、env 白名单、密钥检测、Origin/Audit | `fsx` |
| `reactor.x` | pom 聚合、modules 校验、starter 展开、拓扑排序、失败即停 | `manifest` |
| `artifact.x` | `.xlib` 打包（`xlib.meta`）、install、sha256/CRC32 | `zipx` |
| `zipx.x` | Store-only ZIP 写入（本地头/中央目录/CRC32） | 无 |
| `fsx.x` | 目录递归遍历、mkdir、stat、删除、路径规范化；`XNULL_REPO` 定位 | `xdk.sys` |
| `cli.x` | 命令解析与生命周期编排；调用 B4b-01/02 的 AST→C→cc 管线 | 以上全部 |

### 2.1 最小 API（build/run/test/install/tree/why 必需）

```text
# xpd.x
Block loadProject(String path)                 # 失败抛 Diag
Value field(Block b, String name)

# manifest.x
Model loadManifest(String dir, Options o)      # Options{profiles, platform, toolchainVersion, managedFallback}
Model resolveDeps(Model m)                     # 仲裁；Diagnostics 累积

# deps.x
Graph buildGraph(Model m, String repo)
Text  renderLock(Graph g, String repo)         # 确定性：坐标排序
Diags validateLock(Text lock, Graph g, String repo)
String[] treeLines(Graph g)
String  whyLine(Graph g, String coord)

# resman.x
Set collectResources(Root[] roots, String phase, String packaging)
Text renderResourceTable(Set s)                # 与 devtool 逐字节一致

# config.x
Cfg loadConfig(CfgOptions o)                   # 六层；Value+Origin
Diags checkConfig(Cfg c, Spec spec)

# reactor.x
Plan loadReactor(String root, Options o)
Diags buildReactor(Plan p, Fn buildOne)        # 串行（ADR-011）

# artifact.x
Info packageXlib(Spec s)                       # Store-only zip + xlib.meta
Path installXlib(String repo, Spec s, Info i)

# cli.x
Int main(String[] args)                        # build/run/test/install/tree/why/lock
```

### 2.2 语言面缺口与对策

| 缺口 | 影响 | 对策 |
|---|---|---|
| 无 `mkdir/stat/remove/rename` | 无法创建 `target/`、判断文件/目录、清理 | 一期用 `xdk.runtime.procStatus("mkdir -p …")`；二期加 `xdk.fs` FFI（E5 域） |
| 无 Bytes→String / 码点构造 | 二进制读入（zip/CRC 输入）困难 | `fsx.x` 用 `fileRead` + `Bytes.get` 做字节级处理；字符串仅在 UTF-8 文本路径使用 |
| 无 deflate | `.xlib` 只能 Store | 与 Go 一致（Go 也用 `zip.Store`），无需 deflate |
| Map 迭代顺序未定义 | lock/xlib.meta 顺序不确定 | 所有输出显式 `keys→排序→遍历` |
| 无 glob 库 | `**` 语义 | `resman.x` 手写段匹配（对齐 `resman.go:238` 语义），不用 `regexMatch` |
| 无线程/并发原语（有 tasks.x） | 并发收集 | 一律串行（ADR-011；reactor 本身串行） |

## 3. 与 B4b-01/02 CLI 的接口

### 3.1 命令面

| 新命令 | 语义 | 复用 |
|---|---|---|
| `xnull build [dir] [-o out] [--skip s] [--profile p]` | 有 `xnull.project` → 工程构建；否则退化为单文件（B4b-01 行为） | `cli.x` → `xnull-build.sh` 等价管线 |
| `xnull run [dir] [-- args]` | 构建 + 运行 | 同上 |
| `xnull test [dir]` | 构建 `testRoot/main.x` 并运行 | 同上 |
| `xnull install` | library→`.xlib`；app→产物+`.xmeta` | `artifact.x` |
| `xnull tree` / `xnull why <coord>` | 依赖树 / 选中路径 | `deps.x` |
| `xnull lock [--update-lock]` | 生成/校验锁 | `deps.x` |
| `xnull validate`（设计新增，B4b-03a 验收用） | 只跑清单+配置+资源校验，不编译 | `manifest/config/resman` |

### 3.2 文件契约

| 文件 | 生产者 | 消费者 | 说明 |
|---|---|---|---|
| `xnull.project` | 人 | CLI | XPD DSL；`project{}`/`build{}`/`profiles{}`/`modules{}` |
| `xnull.lock` | `xnull lock` | build/install | 只读校验，不自动改 |
| `target/.cache/<artifact>-<version>` | compile | package | 临时产物 |
| `target/.cache/resources.c` | resman | cc | 资源表 C（字节级一致） |
| `target/<artifact>-<version>[.xlib]` + `.xmeta` | package | install | `.xmeta` 字段顺序固定 |
| `target/reactor-summary.txt` | reactor | 人/CI | `module <rel> <artifact> <sha256>` |
| `<repo>/<g>/<a>/<v>/{<a>-<v>.xlib,xnull.project}` | install | 依赖解析 | `XNULL_REPO`，缺省 `~/.xnull/repository` |

### 3.3 与 `tests/b4/xnull-build.sh` 的衔接

- 脚本现有 `build/run/verify/examples` 是"单文件入口"级；B4b-03 增加：
  - `build --project <dir>` → 交给 `cli.x`（工程模式），脚本只负责传入 AST/C 管线回调；
  - 环境变量沿用：`XNULL_FRONTEND=go`（测试期）、`XNULLC_BIN`、`XPARSER_BIN`、`XNULL_REPO`、`XNULL_B4_WORK`。
- 新增 `XNULL_B4_ORACLE=1`：工程模型层（manifest/graph/config/resman/artifact 的输出）在过渡期可与 Go CLI 对拍，不进入生产路径。

### 3.4 诊断与退出码契约

- 诊断文本：`<file>:<line>:<col>: error[<CODE>]: <message>`（沿用 `diag.String()`），XPD 码段保持不变；
- 退出码：0 成功、1 构建/校验失败、2 用法错误（与 Go CLI 一致）。

## 4. 卡拆分与验收

### B4b-03a：清单与校验（xpd + manifest + validate）

- 交付：`xpd.x`、`manifest.x`、`cli.x` 的 `xnull validate`；parent 链、属性替换、profile（`-P` 与 platform）、`ManagedFallback`。
- 验收：
  1. 用 Go 测试夹具（`impl/internal/manifest/{manifest_test.go(3),deps_test.go(3),validate_test.go(4)}` 共 10 组：parent 链/属性/profile/依赖版本/清单校验）逐组对比 `validate` 输出与诊断码，**文本逐字节一致**；
  2. 负例：parent 环、超过 8 层、非法 `build.warnings`、非 app 用 `entryFile` → 码与位置一致；
  3. `xnull validate` 对 `examples/` 之外的 3 个真实工程（library/app/pom）返回 0。

### B4b-03b：依赖图、锁与仓库（deps + tree/why/lock）

- 交付：`buildGraph`、`renderLock/validateLock`、`tree`/`why`、`XNULL_REPO` 解析。
- 验收：
  1. 对 `impl/internal/manifest/graph_test.go` 的 5 组传递/仲裁/冲突/环用例做对拍：`Selected/Depth/Paths` 与诊断集合一致；
  2. 同一工程连续两次 `lock --update-lock` 输出逐字节一致（可复现）；
  3. 篡改 `.xlib` 后 `xnull lock` 报 `XPD-4xx`，且提示与 Go 一致；
  4. `tree` 输出与 Go `tree` 行序一致；`why` 输出的路径与 `Graph.Paths` 一致。

### B4b-03c：聚合、资源、配置、制品（reactor + resman + config + artifact）

- 交付：`reactor.x`、`resman.x`、`config.x`、`artifact.x`/`zipx.x`；聚合构建写 `reactor-summary.txt`；`.xlib`/`.xmeta`/install 布局。
- 验收：
  1. `resman` 对 `resman_test.go` 的 7 组 glob/冲突/符号链接/phase/packaging 用例逐条对拍，诊断码一致；
  2. 资源表 C 与 `devtool.GenerateResourcesFromMap` **逐字节一致**（含空表）；
  3. `.xlib` 与 Go 产物的 `xlib.meta` 文本一致、条目顺序一致；同一输入两次打包 sha256 相同（确定性）；
  4. 聚合工程 `pom + library×2 + app`（对齐 `reactor_test.go` 的 3 组夹具）：`build` 顺序=拓扑序、`reactor-summary.txt` 行与 Go 一致；
  5. config 六层用 `config_test.go` 的 15 组用例对拍（值、Origin、诊断码）；
  6. `install` 后本地仓库目录结构与 Go 一致（library：`.xlib`+`xnull.project`；app：产物+`.xmeta`+`xnull.project`）。

### 交付顺序与依赖

```text
B4b-03a（xpd/manifest/validate）
   └─ B4b-03b（deps/graph/lock/tree/why）
        └─ B4b-03c（reactor/resman/config/artifact）
             └─ B4b-05（全命令对拍）
```

每卡结束跑：`tests/b4/xnull-build.sh examples`（9/9 不回归）+ 本卡新增用例 + B2 L2 子集（≥20 入口）。
遵循 AGENTS 测试硬规则：用例级切片并发 `xnull dev test --shard k/n --parallel 4`，合并门禁用 `--shard 0/n`。

## 5. 风险

### 5.1 阻塞级（先决条件）

- **native xparser 大文件崩溃**（B4b-02 已定位，B4b 门 PARTIAL）：`xparser.x`/`xlex.x`/`xnfmt.x` native 解析 rc=139；
  `impl/lib/b4/*` 每个模块预计 500–2000 行，**自举编译前必须先修**（runtime concat/根集合或 codegen，E5/E4 域）。
  过渡方案：模块先用 interp（`xnull run --interp`）跑通对拍，native 修复后再切换。
- **语言面缺 Bytes→String / 码点构造**：影响 `\uXXXX` 解析与二进制路径；`.xlib` 可用 `Bytes` 读写规避，但 zip/CRC 错误信息里的字符串处理会受限。

### 5.2 语义差异

| 项 | Go 语义 | XNull 侧风险 |
|---|---|---|
| 依赖仲裁 | nearest-wins + management 恒优先 + 同深度报错 | 图遍历顺序影响"最近"；必须按 Go 队列顺序复刻 |
| 版本形式 | 仅精确 `X.Y.Z[-pre]` | 正则能力可用 `regexMatch`，但需与 Go 正则语义一致 |
| profile 激活 | `-P` 显式 + platform + 声明 | profile 文件命名/激活条件易差 |
| 资源 glob | `**`/`*`/`?` 自实现 | 用 regex 近似会破坏 `**` 语义（必须手写段匹配） |
| 配置层级 | 6 层 + 白名单 + 密钥启发 | 顺序/覆盖/Origin 行号需逐字节对拍 |
| `.xlib` 打包 | zip Store + 固定顺序 + 零时间戳 | 需自写 zip 写入器；CRC32 与中央目录字段顺序必须一致 |

### 5.3 依赖与工具

- 文件系统 API 缺口（mkdir/stat/rename/remove/递归遍历）：一期用 `procStatus` 调系统命令，需处理路径空格/注入（`procStatus` 直接走 shell），二期加 `xdk.fs`。
- `XNULL_REPO` 缺失时 lock 生成会失败（Go 同语义），需在文档/报错中明确。
- 本地仓库并发写：聚合构建串行（ADR-011），但多进程同时 install 同一坐标无锁 → 建议写临时文件后原子 rename（缺 `rename`，一期用 `cp`+`mv` 外的 `procStatus("mv")`）。

### 5.4 并发

- reactor 构建：串行（ADR-011），不做模块级并行；
- 资源收集/打包：单进程内串行；`target/` 写入需固定顺序（先 cache 后 package）；
- 测试：仍按切片并发跑，但工程模型用例涉及共享 `target/`，需每用例独立 `t.TempDir()`（XNull 测试用独立工程目录）。

## 6. 参考文件

- `impl/internal/manifest/manifest.go:39`（Options/Resolved）、`deps.go:22`（仲裁）、`graph.go:19`（Graph）
- `impl/internal/resman/resman.go:26`（Root/Entry/Set）、`:238`（glob 匹配）
- `impl/internal/reactor/reactor.go:24`（Module/Plan/Result）、`:49`（Load）、`:295`（Build）
- `impl/internal/config/config.go:27`（诊断码）、`:40`（Layer）、`:100`（Spec）
- `impl/internal/artifact/artifact.go:21`（Dependency/Spec/Info）、`:58`（Build）、`:157`（Install）
- `impl/internal/cli/manifest.go:314`（生命周期）、`manifest_integration.go:44`（阶段集成）、`reactor_build.go:18`（聚合）、`deps_commands.go:61`（install/tree/why）
- `impl/internal/devtool/resources.go:273`（资源表渲染）
