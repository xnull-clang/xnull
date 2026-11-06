# XNull 解决方案 第 8 部分：工程配置

| 项目 | 内容 |
| --- | --- |
| 文档编号 | 第 8 部分（S9） |
| 文档版本 | 3.0.0 |
| 规范状态 | 草案（待审定） |
| 发布日期 | 2026-11-05 |
| 上游依赖 | 第 1 部分 §11.2/§11.4/§12；第 4 部分 §7.2；第 6 部分 §5；第 7 部分 §2.2/§6.1/§8 |

> **版本说明**：v3.0.0 —— 清单序列化格式由 XML 改为 **TOML**（`xnull.toml`），**功能语义与 v2.0.0 完全一致**（Maven 式单父继承、聚合、GAV、dependencyManagement 仲裁、5 阶段生命周期）；运行时配置保持逐服务 `application.properties`（Spring Boot 式五层覆盖）。v1.0.0（严格 JSON）、v2.0.0（XML）均已归档。
>
> **为什么是 TOML**：需要"结构性语义强"且能表达继承/数组表；JSON 无注释、深层嵌套难读；YAML 有隐式类型与缩进歧义（与本规范"行为唯一确定"冲突）；TOML 有显式类型、支持注释、表格语法天然对应"模块/依赖/配置项"三类结构，且 **重复键按 TOML 语法直接是解析错误**，与"重复即失败"原则零摩擦。

## 0. 核心立场

- **继承显式、坐标唯一**：一个模块只有一个父，父是谁写在清单里；GAV 在仓库内唯一标识一个模块版本。
- **版本精确**：依赖版本必须是精确语义化版本；范围、`SNAPSHOT`、最新版一律拒绝（可复现优先于便利）。
- **配置逐服务、可覆盖、必校验**：配置只在服务自己名下；覆盖顺序固定五层；未知键与缺失必需键都启动失败。
- **失败快于降级**：清单拼错、变量未解析、冲突无法唯一仲裁——全部构建失败，不静默修正。

## 1. 定位与范围

### 1.1 范围

工程结构（聚合/平台/模块）、`xnull.toml` 清单与继承规则、GAV 坐标、属性与变量替换、依赖管理与仲裁、作用域、仓库与本地仓库、profile 激活、打包类型、生命周期与产物、服务运行时配置文件（格式/键空间/覆盖优先级/严格性）、链接与 FFI 声明、可复现性。

### 1.2 不规定

- 命令行工具的具体参数拼写（语义等价即可，本部分行为是判定依据）；
- 远程仓库运营、镜像治理、签名体系（首版复用 Maven 2 布局，签名验证非承诺，§4.5）；
- IDE 集成、CI 平台适配；
- 配置热重载与配置中心：**1.x 否决**，演进方向见 §10（Nacos 兼容或自研外部配置服务）。

### 1.3 与其他部分的分界

| 维度 | 规定者 | 本部分的角色 |
| --- | --- | --- |
| 入口签名与语义 | 第 1 部分 §11.2 | 只规定"入口如何被找到"（§5.4） |
| 退出码映射 | 第 4 部分 §7.2 | 引用 |
| XDK 版本声明机制 | 第 6 部分定案 4-3（§5） | 给出清单键与校验语义（§3.9） |
| FFI 原生库与 `@unsafe` 闸门 | 第 7 部分 §2.2/§6.1/§8 | 给出清单键与链接合同（§7） |

## 2. 工程模型

### 2.1 四类工程（`project.kind`）

| kind | 对应 Maven | 职责 | 可被继承 |
| --- | --- | --- | --- |
| `platform` | `pom` | 父/聚合：定义 properties、dependencyManagement、公共 build/link/configuration；可列 `modules` | 是（单父） |
| `library` | `jar` | 可被依赖的库，产物 `.xlib` | 否（作为父即失败） |
| `starter` | BOM + starter | 能力聚合包：引入即传递一组经仲裁的依赖，无可执行码 | 否 |
| `app` | 可执行 jar | **服务**：有入口与自己的运行时配置（§6） | 否 |

- `platform` 既可当父也可当聚合（Maven 同构）；
- 继承深度上限 8；继承环、self-parent、parent 非 `platform`、缺失 parent → 构建失败。

### 2.2 GAV 坐标

```text
group    反向域名，小写点分（com.example）
name     小写字母/数字/连字符（order-service）
version  语义化版本，精确（1.4.0）
```

- `group` / `version` 可从 parent 继承；`name` 每个模块必须自己声明；
- `group` 被子模块覆盖为不同值 → 失败（禁止改名换姓的继承）；
- 同一次构建中 `group:name:version` 重复 → 失败。

### 2.3 目录布局

```text
order-system/
├── xnull.toml              # kind = "platform"：列 modules，定义 dependencyManagement
├── xnull.lock              # 解析结果锁（构建生成，纳入版本控制）
├── common/
│   ├── xnull.toml
│   └── src/main/x/
├── order-service/
│   ├── xnull.toml
│   ├── application.properties         # 本服务配置（§6）
│   ├── application-dev.properties     # profile 覆盖
│   └── src/main/x/
└── target/                 # 构建产物（勿提交）
```

- 源码根缺省 `src/main/x`，测试根 `src/test/x`；可在 `[build]` 覆盖；
- 产物根固定 `target/`（Maven 同构），不得作为源码来源。

## 3. 清单 `xnull.toml`

### 3.1 完整示例

```toml
[project]
kind = "app"
group = "com.example"
name = "order-service"
version = "1.4.0"

[project.parent]
group = "com.example"
name = "platform-parent"
version = "2.0.0"
# relative-path 缺省 "../xnull.toml"，可显式改写

[properties]
xdk-version = "1.0.0"
language-version = "[3.3,4.0)"

[[dependency-management]]
group = "com.example"
name = "common"
version = "${project.version}"

[[dependencies]]
group = "com.example"
name = "common"
# version 省略 → 由 dependency-management 提供

[[dependencies]]
group = "com.example"
name = "xdk-web-starter"
optional = false
exclusions = [{ group = "org.old", name = "legacy" }]

[build]
mode = "release"
warnings = "strict"
entry-file = "src/main/x/main.x"
entry-package = "com.example.order"

[link]
unsafe = false

[[link.libraries]]
name = "sqlite3"
link-kind = "dynamic"
system = true

[[repositories]]
id = "central"
url = "https://repo.xnull.dev/maven2"

[[profiles]]
id = "dev"
platform = "macos"
[profiles.properties]
"build-mode" = "debug"

# 仅 platform 定义；作为所有子服务配置的第 0 层（§6.6）
[configuration]
"db.pool.max-size" = "8"
"xdk.log.level" = "info"
```

### 3.2 键总表

| 键 | 必需 | 说明 |
| --- | --- | --- |
| `project.kind` | 是 | `platform`/`library`/`starter`/`app` |
| `project.group` / `project.name` / `project.version` | 见 §2.2 | GAV |
| `project.parent` | 否 | 单父（§3.3） |
| `project.modules` | 仅 `platform` | 聚合子目录列表 |
| `properties` | 否 | 变量定义（§3.4） |
| `dependency-management` | 否 | 版本仲裁表（§3.5） |
| `dependencies` | 否 | 依赖声明（§3.6） |
| `build` | 否 | 编译选项与入口（§5.2） |
| `link` | 否 | 原生库与 `@unsafe`（§7） |
| `repositories` | 否 | 远程仓库（§4.5） |
| `profiles` | 否 | 条件覆盖（§3.8） |
| `configuration` | 否 | 服务配置基线（§6.6） |

**语法约束（TOML 原生 + 本规范追加）**：

- 未知键 = 构建失败（TOML 解析器不报未知键，由清单校验补齐）；
- 重复键由 TOML 语法直接判为解析错误（不需要额外规则）；
- 清单不含脚本、条件表达式、任意命令；需要动态生成时用外部工具产出静态清单；
- 键名统一 kebab-case（`dependency-management`、`entry-file`）；`[configuration]` 表内的键保留点分原样（`"db.pool.max-size"`，因为它们直接对应运行时键空间）。

### 3.3 继承规则

- **单父**：`[project.parent]` 至多一个；不写即根工程；
- parent 定位顺序：`relative-path`（缺省 `../xnull.toml`）→ 本地仓库 → 远程仓库（§4.5）；
- **可继承**：`properties`（子覆盖父）、`dependency-management`（合并，子优先）、`dependencies`（合并）、`build`（子覆盖父）、`link`（合并，子覆盖同名 library）、`repositories`（合并）、`configuration`（合并，子覆盖同键）；
- **不可继承**：`project.name`、`project.kind`、`project.modules`、`profiles`；
- 父必须 `kind = "platform"`；
- 深度 > 8、环、缺失 parent、`group` 被覆盖 → 失败。

### 3.4 properties 与变量替换

- 变量形式 `${name}`；替换发生在**解析期**（清单载入后、依赖解析前），单次替换、不递归展开替换结果；
- 内置变量（只读）：`project.group`、`project.name`、`project.version`、`project.basedir`、`xnull.version`（工具链版本）；
- 自定义变量来自 `[properties]`，子覆盖父，值可引用内置变量；
- **未解析变量 = 失败**（不保留原文、不替换为空串）。

### 3.5 dependency-management 仲裁

- 子模块依赖**不写** `version` 时，版本由最近的 `dependency-management` 唯一提供（就近：本模块 > 父链近端 > 远端）；
- 子模块显式写 `version` 覆盖管理版本：允许，但产生构建警告并记入日志；
- 声明依赖却无人提供版本 → 失败（点名 `group:name`）；
- 同一 `dependency-management` 中坐标重复 → 失败。

### 3.6 dependencies

```toml
[[dependencies]]
group = "com.example"
name = "common"
scope = "compile"         # compile(默认) / runtime / test / provided
optional = false          # 不传递
exclusions = [{ group = "org.old", name = "legacy" }]
```

- `optional = true`：不传递（Maven 同义，定案）；
- `exclusions`：精确坐标删除传递依赖（定案）。

### 3.7 作用域

| scope | 编译可见 | 运行时可见 | 传递 |
| --- | --- | --- | --- |
| `compile`（默认） | 是 | 是 | 是（compile） |
| `runtime` | 否 | 是 | 是（runtime） |
| `test` | 测试可见 | 测试运行 | 否 |
| `provided` | 是 | 否（宿主提供） | 否 |

### 3.8 profiles

```toml
[[profiles]]
id = "dev"
platform = "macos"        # 唯一自动激活方式
[profiles.properties]
"build-mode" = "debug"
```

- 激活方式（定案两种）：显式 `-Pdev`；`platform` 匹配当前构建平台。**环境变量激活否决**（不可复现）；
- 可覆盖：`properties`、`dependencies`、`build`、`link`。改变 `project.kind`/GAV/`modules` 否决；
- 多个 profile 同时激活且改同一键 → 失败（不静默取后者）。

### 3.9 版本声明（落实第 6 部分定案 4-3）

- `xdk-version`：所需 XDK 版本（精确）；不匹配 → 失败；
- `language-version`：语言版本范围，**唯一允许范围表达式的位置**（`[3.3,4.0)`）；范围外 → 失败；
- 两者必须由**根 `platform`** 定义；子模块重复声明 → 失败（保证全组织唯一）。

## 4. 依赖解析

### 4.1 解析顺序

1. 展开继承链 → 合并 `properties` / `dependency-management` / `dependencies` / `build` / `link` / `configuration`；
2. 变量替换；
3. 逐模块确定坐标与版本（§3.5）；
4. 构建依赖图（传递 + 作用域传播 + exclusions）；
5. 冲突仲裁（§4.2）；
6. 写入 `xnull.lock`；
7. 仓库拉取（§4.5）。

### 4.2 冲突仲裁

- **最近优先**（nearest-wins）：路径最短者胜；
- 同深度多处出现 → **失败并列出全部路径**（不取第一个，避免声明顺序成为不可见输入）；
- `dependency-management` 版本恒优先于最近优先；
- 仲裁结果必须唯一，否则失败。

### 4.3 版本规则

| 形态 | 状态 |
| --- | --- |
| 精确 `1.4.0` | 定案 |
| 预发布 `1.2.3-rc.1` | 定案（精确即允许） |
| 范围 `[1.0,2.0)` | 否决（依赖中）；仅 `language-version` 可用 |
| `SNAPSHOT` | 否决 |
| `LATEST` / `RELEASE` / `*` | 否决 |
| 本地工作区模块 | 定案：`modules` 聚合或 `relative-path` 覆盖，不靠版本号变通 |

### 4.4 锁文件

- `xnull.lock` 记录每个坐标的解析版本、内容摘要（SHA-256）、来源仓库 id；
- 纳入版本控制；清单变化后重新生成；**锁与清单不一致 → 失败**（提示重新生成），不自动更新；
- 构建以锁为准（先锁后网）；首次无锁构建生成并警告提交。

### 4.5 仓库

- 本地仓库 `~/.xnull/repository`（Maven 2 布局）；`XNULL_REPO` 可覆盖（构建期唯一允许的环境变量）；
- 远程仓库按 `[[repositories]]` 声明顺序尝试，首个命中即用；`mirror-of` 可指定替代；
- 认证凭据只从 `~/.xnull/settings.toml` 读取，**不得写入工程清单**；
- 签名验证：非承诺（原因：生态未定；依赖后果：不得作为安全边界，1.x 不做）。

### 4.6 依赖图约束

- 环依赖 → 失败；`app` 作为依赖 → 失败；
- 依赖的 `xdk-version` 与本工程不一致的大版本 → 失败。

## 5. 生命周期与构建

### 5.1 阶段（定案 5 个，顺序不可变）

| 阶段 | 动作 |
| --- | --- |
| `validate` | 清单语法与未知键校验、继承展开、变量替换、入口存在性 |
| `compile` | 编译 `src/main/x` |
| `test` | 运行 `src/test/x` 测试入口（可 `--skip test`） |
| `package` | 产出 `target/<name>-<version>.<ext>` + `.xmeta` |
| `install` | 安装到本地仓库（可跳过） |

- `deploy`（远程发布）**1.x 否决**；
- 构建插件/扩展机制 **1.x 否决**（原因：插件引入任意构建逻辑，破坏输入穷举；依赖后果：需要额外步骤时用外部工具串联）。

### 5.2 构建选项

| 键 | 取值 | 语义 |
| --- | --- | --- |
| `build.mode` | `debug` / `release` / `size` | 优化档位，不改变语言语义；缺省 `debug` |
| `build.warnings` | `default` / `strict` | `strict` 把警告提升为错误 |
| `build.entry-file` / `build.entry-package` | 路径 / 包名 | 入口定位（§5.4）；`app` 必需，非 `app` 出现即失败 |

- 工程级定义，模块级覆盖（模块 > 父链）；环境变量不参与构建选项（`XNULL_REPO` 例外）。

### 5.3 产物与元数据

- `target/<name>-<version>.<ext>`：`app` → 可执行体，`library` → `.xlib`，`platform`/`starter` → 仅清单与元数据；
- 同名 `.xmeta`：GAV、kind、目标平台、`xdk-version`、`language-version`、锁摘要；
- 构建不写入清单目录以外位置（缓存写入 `target/.cache`）。

### 5.4 入口解析（落实第 1 部分 §11.4）

1. `build.entry-file` + `build.entry-package`：入口为该文件 `main`，且必须在 `entry-package` 内；
2. 仅 `build.entry-file`：入口为该文件 `main`；
3. 无入口键：默认 `src/main/x/main.x`；
4. 无清单：当前目录 `main.x`（第 1 部分 §11.4）。

失败集合：文件不存在、无匹配 `main`、多个匹配 `main`、`entry-package` 不匹配、非 `app` 声明入口。

## 6. 服务运行时配置（Spring Boot 式）

### 6.1 逐服务原则

- **配置只属于服务自己**：只有 `kind = "app"` 的模块拥有 `application.properties`；其他 kind 出现该文件 → 构建失败；
- 每个服务一份基线 `application.properties`（模块根），可选 `application-<profile>.properties`（profile 名与清单 `profiles.id` 同名）；
- 服务之间**不得隐式共享配置**；共享只能经父 `platform` 的 `[configuration]`（构建期冻结，§6.6）；
- 集中配置中心（Nacos 类）：**1.x 不做**，见 §10 演进方向。

### 6.2 格式

```properties
# application.properties —— UTF-8，flat properties
net.http.listen-port=8080
db.url=jdbc:sqlite:data/order.db
db.pool.max-size=8
feature.new-checkout=false
```

- 一行一键，`#` 注释；**值一律按字符串读入**，类型由绑定代码显式解析；
- YAML / JSON / 嵌套结构 **否决**（原因：隐式类型与缩进歧义；依赖后果：复杂结构在代码中构造）；
- 多行值、转义序列 1.x 否决。

### 6.3 键空间

| 前缀 | 归属 | 示例 |
| --- | --- | --- |
| `xnull.` | 工具链保留 | `xnull.profile` |
| `xdk.` | XDK 包（第 6 部分） | `xdk.log.level` |
| `app.` | 服务自身 | `app.name` |
| 自定义（小写点分，段内连字符） | 服务内部 | `net.http.listen-port` |

- 键名只允许小写字母、数字、点、连字符；大写、下划线、连续点 → 启动失败。

### 6.4 覆盖优先级（低 → 高，五层定案）

| 层 | 来源 | 说明 |
| --- | --- | --- |
| 1 | 内建缺省 | 绑定代码 / XDK 包声明 |
| 2 | `application.properties` | 服务基线 |
| 3 | `application-<profile>.properties` | `--profile` 指定，不读环境变量 |
| 4 | 环境变量 | **仅白名单键** `XNULL_OVERRIDE_<KEY>`（大写、点→下划线），白名单由清单 `[configuration]` 的 `env-overrides` 显式列出 |
| 5 | 命令行 | `--key=value`，覆盖一切；写入启动审计日志 |

- 同层重复键 → 启动失败；
- 白名单外的 `XNULL_*` 键被忽略（不报错）；白名单内键缺失不算错；
- 覆盖只能改值，**不能新增键**（新增即未知键，§6.5）。

### 6.5 严格校验

- **未知键 = 启动失败**（列出全部未知键；绑定代码必须声明所用键）；
- 必需键缺失 = 启动失败（点名）；
- 值解析失败（如 `listen-port=abc`）= 启动失败；
- 错误信息必须含：键名、所在层、文件路径（或"命令行"）。

### 6.6 跨服务共享（仅构建期）

```toml
# platform 的 xnull.toml
[configuration]
"db.pool.max-size" = "8"
env-overrides = ["db.url", "db.password"]
```

- `[configuration]` 作为所有子服务配置的**第 0 层**（低于 `application.properties`，可被覆盖）；
- 运行时不跨服务读取（否决"配置继承另一服务"）；外部配置服务 1.x 否决（§10）；
- 密钥不得写入 `[configuration]` 或 `application*.properties`：构建期检查疑似密钥键（`password`/`secret`/`token`/`key`）且值非占位 → 构建失败，要求改走白名单环境变量。

## 7. 链接与 FFI

- `[[link.libraries]]` 显式列出原生库：`name`、`link-kind`（`static`/`dynamic`）、`system`；
- 未声明的原生库不得链接；FFI 绑定引用未声明库 → 构建失败（第 7 部分 §2.2 可审计）；
- `link.unsafe` 缺省 `false`：是否允许 `@unsafe` 受控入口（第 7 部分 §8）；启用后构建日志必须记录；
- 运行时 ABI 符号（`xrt_*`，第 7 部分 §6.1）由工具链自动链接，不需声明，不允许改写。

## 8. 可复现性

- 同清单 + 同 `xnull.lock` + 同工具链版本 ⇒ 同产物（字节等价为目标，PROJ-08 按摘要比对）；
- 输入穷举：清单（含继承链）、锁文件、源码、工具链版本、目标平台、profile 集合。除此之外无输入（`XNULL_REPO` 只影响取件位置，不影响产物内容）；
- `.xmeta` 记录上述全部输入摘要。

## 9. 验收矩阵

| 编号 | 领域 | 验收内容 |
| --- | --- | --- |
| PROJ-01 | 继承 | 单父展开正确；深度 > 8 失败；环/缺失/非 platform parent 失败；`group` 被覆盖失败；`name` 必写 |
| PROJ-02 | 坐标与模块 | 坐标重复失败；modules 展开正确；`app` 作依赖失败；TOML 重复键解析失败 |
| PROJ-03 | 依赖仲裁 | depMgmt 就近提供版本；缺失版本失败；同深度冲突失败并列出路径；显式版本覆盖产生警告 |
| PROJ-04 | 版本规则 | 范围/`SNAPSHOT`/`LATEST` 被拒；`language-version` 范围校验正确 |
| PROJ-05 | 生命周期与产物 | 5 阶段顺序执行；`--skip test` 生效；`deploy`/插件不存在；产物与 `.xmeta` 正确 |
| PROJ-06 | 配置覆盖 | 五层优先级逐层验证；同层重复键失败；白名单外环境变量被忽略；命令行覆盖并留审计 |
| PROJ-07 | 配置严格性 | 未知键失败并列出；缺失必需键失败；类型解析失败报错含键与层级；非 app 出现 `application.properties` 失败；疑似密钥构建失败 |
| PROJ-08 | 可复现 | 两次构建摘要一致；`target/` 外无写入 |

## 10. 实现边界与演进方向

| 能力 | 1.x 状态 | 说明 |
| --- | --- | --- |
| 依赖版本范围 | 否决 | 可复现优先 |
| `SNAPSHOT` / `LATEST` | 否决 | 同上 |
| 构建插件/扩展机制 | 否决 | 隐式行为不可审计；需要时用外部工具 |
| `deploy` 到远程 | 否决 | 发布流程待生态定型 |
| 配置热重载 | 否决 | 配置以启动时五层快照为准 |
| **配置中心（Nacos 类）** | **否决（1.x）· 演进方向** | 后续可做两选一：① 兼容 Nacos 协议（`xnull.config.server=nacos://…`，仅替换第 1 层以上来源，五层顺序不变）；② 自研外部配置服务。准入条件：启动快照可审计、断连有明确降级规则（缺快照则启动失败） |
| YAML / 嵌套配置 | 否决 | 隐式类型与歧义 |
| 跨服务配置继承 | 否决 | 隐式耦合 |
| 环境变量激活 profile | 否决 | 不可复现 |
| 远程仓库签名验证 | 非承诺 | 原因：生态未定；后果：不得作为安全边界 |
| 增量编译 / 并行构建策略 | 非承诺 | 原因：实现自由；后果：只保证语义与产物摘要一致 |

## 附录 A：与 Maven / Spring Boot 的对应

| Maven / Spring Boot | 本部分 | 差异 |
| --- | --- | --- |
| `pom.xml` | `xnull.toml` | TOML 而非 XML；无插件、无 `deploy` |
| `<parent>` 继承 | `[project.parent]` 单父 | 可继承键白名单固定，深度 ≤ 8 |
| `dependencyManagement` | `[[dependency-management]]` | 缺失版本即失败 |
| `<packaging>pom</packaging>` | `kind = "platform"` | `platform` 同时承担父与聚合 |
| starter | `kind = "starter"` | 能力聚合包，无可执行码 |
| `mvn` 生命周期 | 5 阶段 | 无插件绑定、无 `deploy` |
| `~/.m2/repository` | `~/.xnull/repository` | 复用 Maven 2 布局 |
| `application.properties` | `application.properties` | 同格式；值恒字符串、类型显式解析 |
| `application-{profile}.properties` | `application-<profile>.properties` | profile 只由 `--profile` 指定 |
| 环境变量覆盖 | 白名单 `XNULL_OVERRIDE_*` | 默认关闭，须在清单登记 |
| `@ConfigurationProperties` 校验 | 键空间 + 严格校验 | 未知键启动失败（Spring 默认忽略） |
| Nacos 配置中心 | 1.x 无 | 演进方向见 §10 |

## 附录 B：决策留痕

1. **清单用 TOML**：需要结构化 + 可注释 + 无缩进歧义；TOML 的重复键天然是语法错误，与"重复即失败"零摩擦；Maven 的功能语义（继承/聚合/仲裁/生命周期）完整保留，只换序列化。
2. **单父继承、可继承键白名单**：多父的合并顺序是歧义源；单父 + 白名单让"值从哪来"唯一可答。
3. **版本精确、范围/SNAPSHOT 全否**：可复现是硬约束（§8）。
4. **同深度冲突失败而非取第一个**：Maven 的"先声明者胜"依赖声明顺序，属不可见输入。
5. **配置 flat properties、值恒字符串**：隐式类型（`on`/`08`/缩进）是歧义源；显式解析把类型错误提前到启动失败。
6. **未知键启动失败**：拼错静默生效是生产事故常见来源。
7. **环境变量白名单**：保留运维弹性的同时可审计。
8. **跨服务共享只走构建期 `[configuration]`**：运行时跨服务读配置是隐式耦合，破坏"逐服务"原则。
9. **5 阶段无插件**：插件机制与"输入穷举、失败快"冲突。
10. **配置中心列为演进方向而非当前能力**：用户明确"先不管集中配置，后续可做或直接支持 Nacos"；写入 §10 并给出两种准入路径与硬条件（快照可审计、断连缺快照即失败），避免未来实现时重新讨论方向。
