# XNull 解决方案 第 7 部分：工具链（模块 06：工程配置与构建编排）

> **2026-11-15**：本文档是内部实现基线，不属于语言规范序列；实现细节（含 `.xfb` 等格式）可按实现需要修正。

> 本文是第 7 部分模块 06，只落实第 9 部分、第 6 部分 §4.8、第 7 部分 §7 已定义的工程配置、资源与链接合同；内部实现选择不构成语言语义；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 7 部分（T7） |
| 模块 | 06 工程配置与构建编排 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 7 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 9 部分、第 6 部分 §4.8、第 7 部分 §7、第 1 部分 §11 |
| 组件 | XPD 解析、工程模型、依赖/锁/仓库、生命周期、C 编译链接编排、资源打包、插件、产物元数据 |
| 上游输入 | `xnull.project`、`xnull.lock`、目录树、资源、插件元数据、命令行 |
| 下游输出 | 编译器调用、C 编译/链接、产物、`.xmeta`、诊断 |
| 明确不含 | 编译器内部算法（模块 01）、C 运行时（模块 03）、`xrt` ABI（模块 04）、FFI 校验（模块 05）、诊断渲染（模块 07） |
| 配套文档 | 第 7 部分总览；模块 01、02、05、07 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。定义 XPD 解析层、工程模型层、构建驱动层与可复现合同。 |

---

## 0. 范围与分层

### 0.1 组件定位

工程配置与构建负责把“项目目录 + 清单 + 锁 + 资源 + 插件”变成“可复现产物”。

```
xnull.project / xnull.lock / 目录树
        │
        ▼
  XPD 解析层（词法/文法/AST）
        │
        ▼
  工程模型层（继承/坐标/依赖/锁/profile/资源/配置）
        │
        ▼
  构建驱动层（validate → compile → test → package → install）
        │
        ├─ 编译器（01）
        ├─ FFI 合同层（05）
        ├─ C 运行时（03）/ xrt ABI（04）
        └─ 系统 cc
        ▼
  target/<artifact>-<version>.<ext> + .xmeta
```

### 0.2 三层职责

| 层 | 职责 | 入口 |
| --- | --- | --- |
| XPD 解析层 | 词法、文法、AST、错误恢复 | `xpd.Parse` |
| 工程模型层 | 继承展开、变量替换、依赖/锁/profile/资源/配置解析 | 设计目标 |
| 构建驱动层 | 生命周期、编译/链接、产物/元数据、插件执行 | `xnull build/run/test/lock` |

### 0.3 当前代码落点

- `impl/internal/xpd`：XPD 词法/文法/AST；
- `impl/internal/cli`：命令分派、文件模式、`-o`/`-l`/`-L`/`--runtime`；
- `impl/internal/codegen/build.go`：文件模式构建、C 清单、`LinkArgs`；
- `impl/internal/devtool/resources.go`：资源表生成；
- 工程模型（继承/依赖/锁/插件/生命周期）按第 9 部分合同设计，CLI 尚未接入完整工程模式。

本文件描述目标结构，不把未接入部分当作已实现行为。

---

## 1. XPD 解析层

### 1.1 词法

| 记号 | 规则 |
| --- | --- |
| 空白 | 空格/制表符；换行是语句终止符 |
| 注释 | `#` 到行尾 |
| 标点 | `{ } = [ ] ( ) ,` |
| 标识符 | `[A-Za-z][A-Za-z0-9-]*` |
| 键名 | 小写字母/数字/点/连字符，不以点开头或结尾；只允许出现在 `configuration` |
| 裸词 | `[A-Za-z0-9._:/\\*?\-]` 与 `${…}` |
| 字符串 | `"`…`"`，仅 `\"`/`\\` 转义 |
| 变量 | `${标识符}`，可出现在裸词/字符串内 |

- UTF-8，禁止 BOM；
- 缩进无语义；
- 列表/范围不得跨行；
- 字段/条目必须换行或 `}` 收尾。

### 1.2 AST

```go
type File struct { Path string; Items []Node }
type Field struct { Name string; Value Value; Pos Pos }
type Block struct { Name string; Args []Value; Children []Node; Pos Pos; Leaf bool }
type Value struct { Kind ValueKind; Text string; Elems []Value; LoIncl, HiIncl bool; Pos Pos }
```

`ValueKind`：

| 值 | 形态 |
| --- | --- |
| `StringValue` | 带引号字符串 |
| `BareValue` | 裸词/标识符 |
| `ListValue` | `[a, b]` |
| `RangeValue` | `[a, b)` / `(a, b]` |

### 1.3 文法

```text
文件    = { 换行 | 条目 } ;
条目    = 字段 | 条目块 ;
字段    = 名称 "=" 值 ;
条目块  = 名称 { 参数 } [ "{" { 换行 | 条目 } "}" ] ;
参数    = 值 ;
名称    = 标识符 | 键名 ;
值      = 字符串 | 裸词 | 列表 | 范围 ;
列表    = "[" [ 值 { "," 值 } ] "]" ;
范围    = ( "[" | "(" ) 值 "," 值 ( "]" | ")" ) ;
```

### 1.4 语义约束

- 根层只允许一个 `project`/`lock`/`plugin`/`settings`；
- 段落嵌套/字段组合由第 9 部分表规定；
- 不可重复段落重复 → 错误；
- 键名只允许 `configuration`；
- 值恒字符串；列表字段必须给列表；
- 范围只用于 `language-version`；
- 错误必须报告行、列、段落路径。

### 1.5 诊断

| 段位 | 类别 |
| --- | --- |
| `XPD-0xx` | 词法 |
| `XPD-1xx` | 文法/结构 |
| `XPD-2xx` | 段落/字段语义 |
| `XPD-3xx` | 坐标/继承 |
| `XPD-4xx` | 依赖/锁 |
| `XPD-5xx` | 插件 |
| `XPD-6xx` | 配置 |
| `XPD-7xx` | 元数据 |
| `XPD-8xx` | 资源/打包 |

### 1.6 错误恢复

- 词法/语法错误不中断扫描；
- 一次可报多条；
- 诊断含源码行/插入符/段落路径；
- 解析失败不进入模型层。

---

## 2. 工程模型层

### 2.1 打包类型

| packaging | 职责 | 产物 | 可依赖 |
| --- | --- | --- | --- |
| `pom` | 父/聚合 | 清单 + `.xmeta` | 仅 parent/聚合 |
| `library` | 库 | `.xlib` | 是 |
| `starter` | 能力聚合 | 清单 + `.xmeta` | 是（传递依赖） |
| `app` | 服务 | 可执行体 + `.xmeta` | 否 |

约束：

- 四类共用同一段落骨架；
- `modules` 仅 `pom` 可非空；
- `configuration` 仅 `pom`；
- `entryFile`/`entryPackage` 仅 `app`；
- `link` 仅 `app`/`library`；
- `app` 不得作依赖/parent/starter 传递；
- `starter` 不得含 `src/`；
- 父工程必须 `pom`。

### 2.2 坐标与布局

```
groupId     反向域名，小写点分
artifactId  小写字母/数字/连字符
version     精确语义化版本
packaging   四类之一
```

每个模块显式书写四字段，不从 parent 继承。

目录：

```
<project>/
├── xnull.project
├── xnull.lock
├── src/main/x/
├── src/test/x/
├── src/main/resources/
├── src/test/resources/
└── target/
```

- 源码根缺省 `src/main/x`；
- 测试根缺省 `src/test/x`；
- 资源根缺省 `src/main/resources`；
- 测试资源根缺省 `src/test/resources`；
- 产物根固定 `target/`；
- `sourceRoot` 不得包含 `target/`；
- 锁文件位于聚合根。

### 2.3 清单段落

| 段落 | 必需 | 可重复 | 内容 |
| --- | --- | --- | --- |
| `project` | 是 | 否 | 根块 |
| `parent` | 否 | 否 | 单父 |
| `modules` | 否 | `module` | 聚合 |
| `properties` | 否 | 键唯一 | 变量 |
| `dependencyManagement` | 否 | 固定 | 版本仲裁 |
| `dependencies` | 否 | `dependency` | 依赖 |
| `repositories` | 否 | `repository` | 仓库 |
| `build` | 否 | 否 | 构建/入口/资源/插件 |
| `link` | 否 | 否 | 原生库/unsafe |
| `profiles` | 否 | `profile` | 条件覆盖 |
| `configuration` | 否 | 键唯一 | 服务配置基线 |

### 2.4 继承

- 单父；
- 父定位：`relativePath`（缺省 `../xnull.project`）→ 本地仓库 → 远程仓库；
- 继承：`properties`、`dependencyManagement`、`dependencies`、`repositories`、`build`（含 plugins）、`configuration`；
- 不继承：坐标、`parent`、`modules`、`profiles`；
- 深度 ≤ 8；
- 环/self-parent/缺失/非 pom parent → 失败。

### 2.5 属性与变量

- 键 kebab-case，值恒字符串；
- `${name}` 单次替换；
- 内置只读：`project.groupId`、`project.artifactId`、`project.version`、`project.basedir`、`xnull.version`；
- 子覆盖父；
- 未解析变量 → 失败；
- 不得用于枚举字段（`packaging`/`scope`/`phase`/`kind`）；
- 不递归展开替换结果。

### 2.6 依赖管理与依赖

`dependencyManagement`：

- 只声明 `version` 与可选 `exclusions`；
- 出现 `scope`/`optional` → 失败；
- 子依赖不写版本时由最近管理项唯一提供；
- 显式版本覆盖管理版本 → 警告；
- 声明依赖无人提供版本 → 失败；
- 同管理表坐标重复 → 失败。

`dependencies`：

| 字段 | 缺省 | 说明 |
| --- | --- | --- |
| `version` | 管理表提供 | 两者都无 → 失败 |
| `scope` | `compile` | `compile`/`runtime`/`test`/`provided` |
| `optional` | `false` | true 不传递 |
| `exclusions` | 空 | 精确坐标删除传递依赖 |

作用域：

| scope | 编译可见 | 运行时可见 | 传递 |
| --- | --- | --- | --- |
| `compile` | 是 | 是 | compile |
| `runtime` | 否 | 是 | runtime |
| `test` | 测试 | 测试 | 否 |
| `provided` | 是 | 否 | 否 |

### 2.7 Profiles

- 激活：显式 `-P`、`activation.platform`；
- 环境变量激活否决；
- 可覆盖：`properties`、`dependencies`、`build`（含 plugins）、`configuration`；
- 不可覆盖：坐标、`parent`、`modules`、`repositories`；
- 多个 profile 改同一键 → 失败；
- 生效集合写入 `.xmeta`。

### 2.8 版本声明

- `properties.xdk-version` 精确；
- `properties.language-version` 范围，唯一允许范围表达式；
- 两者由根 `pom` 定义；
- 子模块重复定义 → 失败；
- 版本不符 → 失败。

### 2.9 依赖解析

顺序：

```
1. 展开继承链，合并六类配置
2. 变量替换
3. 逐模块确定依赖/插件版本
4. 构建依赖图（传递 + scope + exclusions）
5. 冲突仲裁
6. 写锁
7. 仓库拉取
```

仲裁：

- 最近优先；
- 同深度多处冲突 → 失败并列出全部路径；
- `dependencyManagement` 优先；
- 结果必须唯一。

版本：

| 形态 | 状态 |
| --- | --- |
| 精确 `1.4.0` | 定案 |
| 预发布 `1.2.3-rc.1` | 定案 |
| 范围 `[1.0,2.0)` | 依赖/插件否决；仅 `language-version` |
| `SNAPSHOT`/`LATEST`/`RELEASE`/`*` | 否决 |
| 工作区模块 | 聚合或 relativePath，不靠版本变通 |

### 2.10 锁文件

```xpd
lock {
  version = 1

  entry com.example:common 1.4.0 {
    kind       = dependency
    repository = central
    sha256     = 64位小写十六进制
  }
}
```

规则：

- 全工程一份，位于聚合根；
- 每个依赖/插件一条，`kind` = `dependency`/`plugin`；
- 按 `groupId:artifactId` 字典序；
- 同坐标唯一；
- 摘要为制品 SHA-256；
- 锁与清单不一致 → 失败；
- 无锁首次构建生成并警告提交；
- `--update-lock` 唯一重生成入口；
- 构建以锁为准（先锁后网）；
- 锁中多余坐标 → 失败。

### 2.11 仓库与凭据

- 声明仓库按顺序尝试，首个命中即用；
- 全链未声明 → 默认 `central`；
- 镜像可替代仓库，同 id 一个 mirror，mirror 不得再被 mirror；
- 凭据只从 `~/.xnull/settings.xpd`；
- 令牌只存环境变量名（`tokenEnv`）；
- 缺失凭据且需要认证 → 失败；
- 签名验证非承诺。

---

## 3. 构建驱动层

### 3.1 生命周期

| 阶段 | 动作 |
| --- | --- |
| `validate` | 词法/文法/未知段落、继承、变量、入口、锁一致性 |
| `compile` | 编译 `src/main/x` |
| `test` | 运行 `src/test/x`（可 `--skip test`） |
| `package` | 产出 `target/<artifactId>-<version>.<ext>` + `.xmeta` |
| `install` | 安装到本地仓库（可跳过） |

- `deploy` 1.x 否决；
- 插件只能绑定 5 阶段；
- 工具链退出码 0/1/2/130。

### 3.2 build 字段

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `mode` | `debug`/`release`/`size` | 优化档位，不改语义 |
| `warnings` | `default`/`strict` | strict 警告提升为错误 |
| `sourceRoot`/`testRoot` | 路径 | 覆盖缺省 |
| `resources` | `resource` 容器 | 资源根/过滤 |
| `entryFile`/`entryPackage` | 路径/包名 | `app` 必需 |
| `plugins` | `plugin` 容器 | 受控插件 |

环境变量不参与构建选项（`XNULL_REPO` 例外）。

### 3.3 产物与 `.xmeta`

| packaging | 产物 |
| --- | --- |
| `app` | 可执行体 |
| `library` | `.xlib` |
| `pom`/`starter` | 清单 + 元数据 |

`.xmeta` 必需字段：

| 字段 | 内容 |
| --- | --- |
| 坐标 | groupId/artifactId/version/packaging |
| `platform` | 目标平台 |
| `xdkVersion`/`languageVersion` | 生效版本 |
| `toolchainVersion` | 工具链版本 |
| `profiles` | 生效 profile id 升序 |
| `plugins` | 插件坐标 + goal + phase（执行序） |
| `lockSha256` | 锁内容摘要 |
| `inputs` | 清单链/源码/锁摘要 |

构建只写 `target/` 与清单允许位置；缓存写 `target/.cache`。

### 3.4 入口解析

1. `entryFile` + `entryPackage`：该文件 `main`，包匹配；
2. 仅 `entryFile`：该文件 `main`；
3. 无入口字段：`src/main/x/main.x`；
4. 无清单：当前目录 `main.x`。

失败集合：文件不存在、无匹配 `main`、多个 `main`、`entryPackage` 不匹配、非 `app` 声明入口。

### 3.5 编译与链接

文件模式（当前代码落点）：

```
LoadUnits
  → LoadFFI（工程根 .xfb）
  → InjectFFI（P-09 入口注入）
  → UnsupportedFFIEntries（显式提示）
  → sema.Analyze
  → EmitCWithFFI
  → 写 <out>.c
  → cc -std=c11 -O2 -I <runtime> -o <out> <cfile> <runtime C sources> [LinkArgs]
```

运行时 C 清单（顺序固定）：

```
rt.c
rt_gc.c
rt_policy.c
rt_weak.c
xrt_abi.c
rt_std_runtime.c
rt_std_text.c
rt_std_sys.c
```

链接：

- `LinkArgs` 去重 + 升序；
- `-l/-L` 排在全部目标文件之后；
- 未声明库不得链接；
- `xrt_*` 自动链接；
- 缺库由 `cc` 失败显式报错，不回退。

工程模式目标态：

- 按 import 闭包纳入所需 `rt_std_*.c`；
- 缓存键包含运行时源内容哈希、编译旗标、工具链版本、链接清单哈希；
- 缓存只落 `target/.cache`。

### 3.6 资源

- 资源 = 随产物发布、不参与编译的非 `.x` 文件；
- 缺省根 `src/main/resources`；测试根 `src/test/resources`；
- `resource <dir>` 可重复；声明后不叠加缺省根；
- 收录目录内全部常规文件，相对路径；
- glob：`*` 单段、`**` 跨段、`?` 单字符；
- `excludes` 优先于 `includes`；
- 制品内固定前缀 `resources/`；
- 同路径冲突失败；
- 符号链接按目标读取；断链失败；
- 权限位/时间戳不保留；
- 资源根内 `.x` 按数据打包；
- `pom` 声明资源失败；
- 构建期过滤/变量替换否决。

依赖库资源：

- `app` 合并自身 + `compile`/`runtime` 依赖（含 starter 传递）资源；
- 冲突失败；
- `starter` 不合并；
- `library` 只含自身。

生成：

- `xnull dev res` 递归收录、按名升序、空目录零条目；
- 输出只读 C 常量表；
- 资源名 = 相对路径，`/` 分隔。

### 3.7 运行时配置

- 仅 `app` 有 `application.properties`；
- 固定资源根顶层；
- `application-<profile>.properties`，profile 名必须与清单 id 匹配；
- flat properties，值恒字符串；
- 五层覆盖：父 `configuration` → 内建缺省 → `application.properties` → profile → 白名单环境变量 → 命令行；
- 未知键/缺必需键/解析失败 → 启动失败；
- 同层重复键失败；
- 覆盖只能改值，不能新增键；
- 白名单外环境变量忽略；
- 疑似密钥键且值非占位 → 构建失败；
- 键名小写字母/数字/点/连字符，长度 ≤ 128；
- 配置热重载/跨服务继承/配置中心 1.x 否决。

### 3.8 插件

- 精确版本；
- 绑定 5 阶段之一；
- 显式 goal；
- `configuration` 键必须由 `.xplugin` 的 `configKeys` 声明；
- 只读清单/`src/`/依赖；只写 `target/`；
- 禁网；
- 环境变量仅 `XNULL_REPO` + `envOverrides` 白名单；
- 不得改写 `src/`、不得注入运行时行为；
- 非零退出 = 构建失败；
- 插件依赖不进被构建工程编译类路径；
- 坐标/goal/phase 入锁与 `.xmeta`；
- `.xplugin` 缺失/字段不符/工具链主版本不符 → 失败。

### 3.9 可复现

输入穷举：

- 清单（含继承链）；
- 锁文件；
- 源码；
- 工具链版本；
- 目标平台；
- profile 集合；
- 生效插件集合。

约束：

- 同输入 ⇒ 同产物；
- `.xmeta` 记录全部输入摘要；
- 锁文件字节稳定；
- 构建只写 `target/`；
- 插件禁网/禁环境读取；
- 增量编译/并行构建策略非承诺；
- 产物加密/混淆否决。

---

## 4. 错误与退出码

| 场景 | 退出码 |
| --- | --- |
| 全部阶段成功 | 0 |
| 编译/测试/插件/校验失败 | 1 |
| 清单/用法错误 | 2 |
| 中断 | 130 |

诊断：

- XPD 解析：`XPD-0xx`—`8xx`；
- 模型/解析/锁/插件/资源：对应 XPD 段位；
- 编译器诊断：LEX/SYN/RES/DA/TY/ERR；
- 链接失败：`cc` 原始错误透传；
- 诊断渲染由 07 统一。

---

## 5. 确定性与排序

| 对象 | 排序 |
| --- | --- |
| 锁条目 | `groupId:artifactId` 字典序 |
| profiles | 生效 id 升序 |
| 插件 | 阶段/声明顺序 |
| 资源 | 资源名升序 |
| 诊断 | 文件/行/列/码 |
| 依赖图 | 声明/解析顺序稳定 |

禁止依赖文件系统枚举、map 遍历、环境变量顺序。

---

## 6. 验证

| 领域 | 要点 |
| --- | --- |
| XPD 文法 | 规范样例逐块解析；错误码/行列/段落路径 |
| 骨架/坐标 | 未知段落/字段、重复、容器条目、四字段 |
| 继承 | 深度、环、非 pom parent、坐标不继承 |
| 依赖 | 管理表、缺失版本、同深度冲突、scope |
| 锁 | 排序、摘要、一致性、`--update-lock` |
| 生命周期 | 5 阶段、`--skip test`、退出码、`.xmeta` |
| 插件 | 版本/phase/goal/configKeys/越界写/网络/非零退出 |
| 资源 | 缺省根、glob、前缀、冲突、依赖合并、`.x` 数据 |
| 配置 | 五层覆盖、未知键、缺键、解析失败、密钥 |
| 链接 | 未声明库、`xrt_*`、unsafe 闸门 |
| 可复现 | 两次构建摘要一致、锁字节稳定 |

---

## 7. 边界

| 能力 | 说明 |
| --- | --- |
| 工程模式 | 设计目标；当前代码以 XPD 解析与文件模式构建为主 |
| 继承/依赖/锁/插件/生命周期 | 按第 9 部分合同接入 |
| 配置中心 | 1.x 否决 |
| 配置热重载 | 否决 |
| 跨服务配置继承 | 否决 |
| YAML/嵌套配置 | 否决 |
| 远程签名验证 | 非承诺 |
| 增量编译/并行构建 | 非承诺 |
| 资源过滤/变量替换 | 否决 |
| 资源体积上限 | 非承诺 |
| deploy | 1.x 否决 |

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 9 部分 §2—§10、附录 A/C | 工程模型、清单、继承、依赖、锁、仓库、生命周期、插件、资源、配置、链接、可复现 |
| 第 6 部分 §4.8 | 资源读取 API 的资源打包前提 |
| 第 7 部分 §7 | 原生库链接与 unsafe 闸门 |
| 第 1 部分 §11.4 | 入口解析规则 |
| 第 4 部分 §7.2 | 程序退出码与工具链退出码边界 |

### 实现选择

- XPD 词法/文法/AST 的具体 Go 结构；
- 工程模型的分层与函数边界；
- 文件模式构建的 C 源顺序；
- 资源表 C 生成形态；
- `target/.cache` 缓存策略；
- CLI 旗标到工程字段的映射。

以上为实现选择，不新增语言语义；工程配置语义以第 9 部分为准，资源读取语义以第 6 部分 §4.8 为准。

## 8. 参考

- `impl/internal/xpd/`
- `impl/internal/cli/cli.go`
- `impl/internal/codegen/build.go`
- `impl/internal/devtool/resources.go`
- `XNull解决方案-第9部分-工程配置-v5.2.0.md`
- `XNull解决方案-第6部分-标准库XDK-v1.1.0.md` §4.8
- `XNull解决方案-第7部分-FFI-v1.1.0.md` §7
