# XNull 解决方案 第 8 部分：工程配置

| 项目 | 内容 |
| --- | --- |
| 文档编号 | 第 8 部分（S9） |
| 文档版本 | 2.0.0 |
| 规范状态 | 草案（待审定） |
| 发布日期 | 2026-11-05 |
| 上游依赖 | 第 1 部分 §11.2/§11.4/§12；第 4 部分 §7.2；第 6 部分 §5；第 7 部分 §2.2/§6.1/§8 |

> **版本说明**：v2.0.0 为全面重设计——工程管理采用 **Maven 式**（`xnull.xml` 清单、单父继承、聚合模块、GAV 坐标、dependencyManagement 仲裁、生命周期与仓库），运行时配置采用 **Spring Boot 式**（每个服务一份 `application.xconf`、按 profile 分层覆盖、严格校验）。v1.0.0 草案（严格 JSON + 仅 path 依赖）已归档，其可复现性原则沿用。

## 0. 核心立场

- **继承显式、坐标唯一**：一个模块只有一个父，父为谁写在清单里；GAV 坐标在全仓库内唯一标识一个模块版本。
- **版本精确**：依赖版本必须是精确语义化版本；范围、`SNAPSHOT`、最新版一律拒绝（可复现优先于便利）。
- **配置逐服务、可覆盖、必校验**：配置只在服务自己名下；覆盖顺序固定五层；未知键和缺失必需键都启动失败。
- **失败快于降级**：清单拼错、变量未解析、依赖冲突未能在仲裁规则下唯一确定——全部构建失败，不静默修正。

## 1. 定位与范围

### 1.1 范围

工程结构（聚合/父/模块）、`xnull.xml` 清单与继承规则、GAV 坐标、属性与变量替换、依赖管理与仲裁、作用域、仓库与本地仓库、profile 激活、打包类型、生命周期与产物、服务运行时配置文件（格式/键空间/覆盖优先级/严格性）、链接与 FFI 声明、可复现性。

### 1.2 不规定

- 命令行工具的具体参数拼写（语义等价即可，但本部分给出的行为是判定依据）；
- 远程仓库的运营、镜像治理策略、签名体系（首版采用 Maven 2 布局，签名验证非承诺，§4.5）；
- IDE 集成、CI 平台适配；
- 配置热重载、配置中心（1.x 否决，§10）。

### 1.3 与其他部分的分界

| 维度 | 规定者 | 本部分的角色 |
| --- | --- | --- |
| 入口签名与语义 | 第 1 部分 §11.2 | 只规定"入口如何被找到"（§5.4） |
| 退出码映射 | 第 4 部分 §7.2 | 引用 |
| XDK 版本声明机制 | 第 6 部分定案 4-3（§5） | 给出清单元素与校验语义（§3.9） |
| FFI 原生库与 `@unsafe` 闸门 | 第 7 部分 §2.2/§6.1/§8 | 给出清单元素与链接合同（§7） |

## 2. 工程模型

### 2.1 三层结构

| 层 | 清单 `packaging` | 职责 | 可否被继承 |
| --- | --- | --- | --- |
| **聚合工程** | `pom` | 列 `<modules>`，统一构建多模块；本身无源码 | 否（聚合不参与继承） |
| **父工程** | `pom` | 定义 properties、dependencyManagement、公共 build/link、公共 configuration 基线 | 是（单父） |
| **模块** | `library` / `app` / `starter` | 实际产物；`app` 为服务（§6） | 可被继承（但被继承的模块必须是 `pom`，§3.2） |

- 一个 `pom` 模块可以同时是父和聚合（列 modules 又被引用为 parent），Maven 同构；
- 继承链深度上限 8 层（防止意外长链）；
- 继承环、self-parent、跨聚合环一律构建失败。

### 2.2 GAV 坐标

```text
groupId: 反向域名，小写点分（com.example）
artifactId: 小写字母/数字/连字符（order-service）
version: 语义化版本，精确（1.2.3）；-SNAPSHOT 否决（§4.3）
```

- `groupId` / `version` 可从 parent 继承（不写则用父值）；`artifactId` 必须每个模块自己声明；
- 坐标 + 打包类型唯一确定一个模块；同一构建中坐标重复 → 失败。

### 2.3 目录布局

```text
order-system/                 # 聚合工程
├── xnull.xml                 # packaging=pom，列 modules，定义 dependencyManagement
├── xnull.lock                # 解析结果锁（构建生成，纳入版本控制）
├── common/                   # 公共 library 模块
│   ├── xnull.xml
│   └── src/main/x/
├── order-service/            # 服务模块（app）
│   ├── xnull.xml
│   ├── application.xconf     # 本服务配置（§6）
│   ├── application-dev.xconf # profile 覆盖
│   └── src/main/x/
└── target/                   # 聚合构建产物（Maven 风格，勿提交）
```

- 源码根缺省 `src/main/x`，测试根 `src/test/x`；可在 `<build>` 覆盖；
- 产物根固定 `target/`（Maven 同构）；`target/` 不得作为源码来源。

## 3. 清单 `xnull.xml`

### 3.1 元素总表

```xml
<xnull xmlns="https://xnull.dev/schema/v2">
  <parent>
    <groupId>com.example</groupId>
    <artifactId>platform-parent</artifactId>
    <version>2.0.0</version>
  </parent>

  <groupId>com.example</groupId>
  <artifactId>order-service</artifactId>
  <version>1.4.0</version>
  <packaging>app</packaging>

  <properties>
    <xdk.version>1.0.0</xdk.version>
    <language.version>[3.3,4.0)</language.version>
  </properties>

  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>common</artifactId>
        <version>${project.version}</version>
      </dependency>
    </dependencies>
  </dependencyManagement>

  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>common</artifactId>
    </dependency>
  </dependencies>

  <build>
    <mode>release</mode>
    <warnings>strict</warnings>
    <entryFile>src/main/x/main.x</entryFile>
    <entryPackage>com.example.order</entryPackage>
  </build>

  <link>
    <libraries>
      <library>
        <name>sqlite3</name>
        <kind>dynamic</kind>
        <system>true</system>
      </library>
    </libraries>
    <unsafe>false</unsafe>
  </link>

  <repositories>
    <repository>
      <id>central</id>
      <url>https://repo.xnull.dev/maven2</url>
    </repository>
  </repositories>

  <profiles>
    <profile>
      <id>dev</id>
      <activation><platform>macos</platform></activation>
      <properties><build.mode>debug</build.mode></properties>
    </profile>
  </profiles>
</xnull>
```

| 元素 | 必需 | 说明 |
| --- | --- | --- |
| `parent` | 否 | 单父继承（§3.2） |
| `groupId` / `artifactId` / `version` | 见 §2.2 | GAV；`artifactId` 必写 |
| `packaging` | 是 | `pom` / `library` / `app` / `starter` |
| `properties` | 否 | 变量定义（§3.3） |
| `dependencyManagement` | 否 | 版本仲裁表（§3.4） |
| `dependencies` | 否 | 依赖声明（§3.5） |
| `build` | 否 | 编译选项与入口（§5） |
| `link` | 否 | 原生库与 `@unsafe`（§7） |
| `repositories` | 否 | 远程仓库（§4.5） |
| `profiles` | 否 | 条件覆盖（§3.8） |
| `modules` | 仅 `pom` | 聚合子模块（§2.1） |
| `configuration` | 否 | 服务配置基线（§6.6，`pom`/`starter` 可定义） |

- **未知元素或未知属性是构建失败**（不静默忽略）；
- 清单内不支持脚本、条件表达式、任意命令（需要时用外部工具生成静态清单）。

### 3.2 继承规则

- **单父**：`<parent>` 至多一个；不写 `<parent>` 即根工程；
- parent 定位：先 `.mvn` 同级 `xnull.xml`（同目录），再本地仓库，再远程仓库（§4.5）；
- **可继承**：`properties`（子覆盖父）、`dependencyManagement`（合并，子优先）、`dependencies`（合并）、`build`（子覆盖父）、`link`（合并，子覆盖同名 library）、`repositories`（合并）、`configuration`（合并，子覆盖同键）；
- **不可继承**：`artifactId`、`packaging`、`modules`、`profiles`、`groupId`（可继承但不可被子覆盖为不同值，覆盖即失败）；
- 继承链上 `packaging` 必须为 `pom`（父不是 pom → 失败）；
- 继承深度 > 8、环、缺失 parent → 失败。

### 3.3 properties 与变量替换

- 变量形式 `${name}`；替换发生在**解析期**（清单载入后、依赖解析前），一次替换、不递归展开二次替换结果；
- 内置变量（只读，不可覆盖）：`project.groupId`、`project.artifactId`、`project.version`、`project.basedir`、`xnull.version`（工具链版本）；
- 自定义变量由 `properties` 定义；子覆盖父；`<properties>` 中的值可引用内置变量；
- **未解析的变量是构建失败**（不保留原样、不空串替换）。

### 3.4 dependencyManagement 仲裁

- 子模块声明依赖时**不给版本**，版本由最近的 `dependencyManagement` 唯一提供（就近优先：当前模块 > parent 链近端 > 远端）；
- 子模块在 `dependencies` 里显式写版本**覆盖**管理版本（允许，但产生一条构建警告，记入日志）；
- 声明了依赖但无人提供版本 → 失败（点名 groupId:artifactId）；
- 同一 `dependencyManagement` 中坐标重复 → 失败。

### 3.5 dependencies

```xml
<dependency>
  <groupId>com.example</groupId>
  <artifactId>common</artifactId>
  <scope>compile</scope>      <!-- compile(默认) / runtime / test / provided -->
  <optional>false</optional>
  <exclusions>
    <exclusion><groupId>org.old</groupId><artifactId>legacy</artifactId></exclusion>
  </exclusions>
</dependency>
```

- 版本必须精确（§4.3）；`optional=true` 表示不传递（语义与 Maven 一致，定案）；
- `exclusions` 精确匹配坐标，删除该传递依赖（定案）。

### 3.6 作用域

| scope | 编译可见 | 运行时可见 | 传递 |
| --- | --- | --- | --- |
| `compile`（默认） | 是 | 是 | 是 |
| `runtime` | 否 | 是 | 是（runtime） |
| `test` | 测试可见 | 测试运行 | 否 |
| `provided` | 是 | 否（由宿主/运行时提供） | 否 |

- 作用域传播：`compile`→`compile`、`runtime`→`runtime`、其余不传递（定案，Maven 同构的最小集）。

### 3.7 packaging 语义

| packaging | 产物 | 可否被依赖 |
| --- | --- | --- |
| `pom` | 无（仅元数据与继承） | 仅作 parent/聚合 |
| `library` | `.xlib`（模块归档） | 是 |
| `app` | 服务可执行体（§6） | 否（app 不可作依赖） |
| `starter` | 元数据 + 依赖聚合（pom 级） | 是（引入即传递其 `dependencies`） |

- `starter` 是"能力聚合包"：一个 `<dependency>` 引入一组经过版本仲裁的库（Spring Boot starter 同构，定案）；starter 不产生可执行码。

### 3.8 profiles

```xml
<profile>
  <id>dev</id>
  <activation><platform>macos</platform></activation>
  <properties><build.mode>debug</build.mode></properties>
  <dependencies>...</dependencies>
</profile>
```

- 激活方式（定案，两种）：显式 `-Pdev`；`<activation><platform>` 匹配当前构建平台。**按环境变量隐式激活否决**（不可复现）；
- profile 只允许覆盖：`properties`、`dependencies`、`build`、`link`。改变 `packaging`/GAV/`modules` 否决；
- 多个 profile 同时激活且改同一键 → 失败（要求唯一，不静默取后者）。

### 3.9 版本声明（落实第 6 部分定案 4-3）

- `xdk.version`：所需 XDK 版本（精确）；工具链 XDK 不匹配 → 失败；
- `language.version`：语言版本范围，唯一允许范围表达式的位置（语义化版本比较，`[3.3,4.0)` 形式）；范围外 → 失败；
- 二者必须由**根父工程**定义（子模块不重复声明；重复即失败）——保证全组织唯一。

## 4. 依赖解析

### 4.1 解析顺序

1. 解析继承链 → 合并 `dependencyManagement` / `dependencies` / `properties`；
2. 变量替换；
3. 逐模块解析依赖坐标与版本（§3.4）；
4. 构建依赖图（传递依赖 + 作用域传播 + exclusions）；
5. 冲突仲裁（§4.2）；
6. 写入 `xnull.lock`；
7. 仓库拉取（§4.5）。

### 4.2 冲突仲裁

- **最近优先**（nearest-wins）：依赖树中路径最短者胜；同深度多处出现 → **失败并列出全部路径**（不取第一个，避免顺序依赖）；
- `dependencyManagement` 版本始终优先于最近优先（管理表钉死）；
- 仲裁结果必须唯一；不能唯一确定即失败。

### 4.3 版本规则

| 形态 | 状态 |
| --- | --- |
| 精确 `1.2.3` | 定案 |
| 预发布 `1.2.3-rc.1` | 定案（精确即允许） |
| 范围 `[1.0,2.0)` | 否决（依赖里）；仅 `language.version` 可用（§3.9） |
| `SNAPSHOT` | 否决 |
| `LATEST` / `RELEASE` / `*` | 否决 |
| 本地工作区模块 | 定案：用 `<modules>` 聚合或 `relativePath` 覆盖，不靠版本号变通 |

### 4.4 锁文件

- `xnull.lock` 记录：每个坐标的解析版本、内容摘要（SHA-256）、来源仓库 id；
- 纳入版本控制；清单变化后重新生成；**锁与清单不一致 → 构建失败**（提示重新生成），不自动更新；
- 构建以锁文件为准（先锁后网），无锁首次构建生成并警告提交。

### 4.5 仓库

- 本地仓库：`~/.xnull/repository`（Maven 2 布局：`groupId/artifactId/version/`），可用 `XNULL_REPO` 覆盖（唯一允许的构建期环境变量，§0）；
- 远程仓库：`<repositories>` 声明，HTTP(S)，**复用 Maven 2 仓库布局**（不发明新协议）；
- 镜像与优先序：按声明顺序尝试，第一个命中即用；`<repository>` 可设 `<mirrorOf>` 替代；
- 认证：凭据只从 `~/.xnull/settings.xml` 读取，**不得写入工程清单**；
- 签名验证：非承诺（原因：生态未定；依赖后果：不得把签名验证作为安全边界，1.x 不做）。

### 4.6 依赖图约束

- 环依赖 → 失败；
- app 作为依赖 → 失败；
- 依赖的 `xdk.version` 下限低于本工程声明 → 失败（避免混用 XDK 大版本）。

## 5. 生命周期与构建

### 5.1 阶段（定案，5 个，顺序不可变）

| 阶段 | 动作 | 失败即中止 |
| --- | --- | --- |
| `validate` | 清单校验、继承展开、变量替换、入口存在性 | 是 |
| `compile` | 编译 `src/main/x`（及 `src/test/x` 的测试可见部分） | 是 |
| `test` | 运行 `src/test/x` 的测试入口 | 是（可 `--skip test`） |
| `package` | 产出 `target/<artifactId>-<version>.<ext>` + `.xmeta` | 是 |
| `install` | 安装到本地仓库 | 否（可跳过） |

- `deploy`（发布到远程）**1.x 否决**；
- 插件/扩展机制 **1.x 否决**（原因：插件引入隐式行为与不确定性；依赖后果：需要额外构建步骤时用外部工具串联，不得依赖构建器内插件）。

### 5.2 构建选项

| 元素 | 取值 | 语义 |
| --- | --- | --- |
| `build/mode` | `debug` / `release` / `size` | 优化档位，不改变语言语义；缺省 `debug` |
| `build/warnings` | `default` / `strict` | `strict` 把警告提升为错误 |
| `build/entryFile` / `entryPackage` | 路径 / 包名 | 入口定位（§5.4）；`app` 必需，`library` 出现即失败 |

- 选项工程级定义，模块级覆盖（模块 > 父链）；
- **环境变量不得参与构建选项**（仅 `XNULL_REPO` 例外）；可复现性优先。

### 5.3 产物与元数据

- `target/<artifactId>-<version>.<ext>`：`app` → 可执行体，`library` → `.xlib`，`pom`/`starter` → 仅 `xnull.xml` 与元数据；
- 同名 `.xmeta`：GAV、packaging、目标平台、`xdk.version`、`language.version`、锁文件摘要；
- 构建不得写入清单目录以外位置（缓存写入 `target/.cache`）。

### 5.4 入口解析（落实第 1 部分 §11.4）

解析顺序（前者优先，冲突即失败）：

1. `build/entryFile` + `build/entryPackage`：入口为该文件 `main`，且必须位于 `entryPackage` 内；
2. 仅 `build/entryFile`：入口为该文件 `main`；
3. 无入口元素：默认 `src/main/x/main.x`；
4. 无清单：当前目录 `main.x`（第 1 部分 §11.4）。

失败集合：文件不存在、无匹配 `main`、多个匹配 `main`、`entryPackage` 不匹配、`library` 声明入口。

## 6. 服务运行时配置（Spring Boot 式）

### 6.1 逐服务原则

- **配置只在服务自己名下**：只有 `packaging=app` 的模块拥有 `application.xconf`；`library` / `starter` / `pom` 出现 `application.xconf` → 构建失败；
- 每个服务一份基线 `application.xconf`（模块根），可选 `application-<profile>.xconf`（profile 名与清单 `profiles/id` 同名）；
- 服务之间**不得隐式共享配置**；共享走父工程 `<configuration>`（构建期冻结的静态键值，§6.6）。

### 6.2 格式

```properties
# application.xconf —— UTF-8，flat properties
net.http.listen-port=8080
db.url=jdbc:sqlite:data/order.db
db.pool.max-size=8
feature.new-checkout=false
```

- 格式：`key=value` 一行一键，`#` 注释；**值一律按字符串读入**，类型由绑定代码显式解析（不做隐式类型推断）；
- YAML / JSON / 嵌套结构 **否决**（原因：隐式类型与缩进歧义违反"行为唯一确定"；依赖后果：复杂结构在代码中构造）；
- 多行值、转义序列 1.x 否决；需要时拆键。

### 6.3 键空间

| 前缀 | 归属 | 示例 |
| --- | --- | --- |
| `xnull.` | 工具链保留 | `xnull.profile` |
| `xdk.` | XDK 包（第 6 部分） | `xdk.log.level` |
| `app.` | 服务自身 | `app.name` |
| 自定义（小写点分，段内连字符） | 服务内部约定 | `net.http.listen-port` |

- 键名只能是小写字母、数字、点、连字符；大写、下划线、连续点 → 启动失败。

### 6.4 覆盖优先级（低 → 高，五层定案）

| 层 | 来源 | 说明 |
| --- | --- | --- |
| 1 | 内建缺省 | 由绑定代码/Xdk 包声明 |
| 2 | `application.xconf` | 服务基线 |
| 3 | `application-<profile>.xconf` | 启动参数 `--profile` 指定，不读环境变量 |
| 4 | 环境变量 | **仅白名单键**：`XNULL_OVERRIDE_<KEY>`（`<KEY>` 大写、点→下划线），白名单由清单 `<configuration><env-overrides>` 显式列出 |
| 5 | 命令行 | `--key=value`，覆盖一切；写入启动审计日志 |

- 同层内重复键 → 启动失败（不静默取后者）；
- 白名单外的 `XNULL_*` 键被忽略（不报错），白名单内的键缺失不算错；
- 覆盖只能改值，**不能新增键**（新增键 = 未知键，§6.5）。

### 6.5 严格校验

- **未知键 = 启动失败**（列出全部未知键；绑定代码必须在代码中声明所用键）；
- 必需键缺失 = 启动失败（点名键）；
- 值解析失败（如 `listen-port=abc`）= 启动失败；
- 错误信息必须含：键名、所在层、文件路径（或"命令行"）。

### 6.6 跨服务共享（显式、构建期）

```xml
<!-- 父工程 -->
<configuration>
  <key name="db.pool.max-size">8</key>
  <key name="xdk.log.level">info</key>
</configuration>
```

- 父工程的 `<configuration>` 作为所有子服务配置的**第 0 层**（低于 `application.xconf`，可被覆盖）；
- 运行时不跨服务读取（否决"配置继承另一服务"）；服务间共享只能经此构建期基线或外部配置服务（后者 1.x 否决，§10）；
- 密钥不得写入 `<configuration>` 或 `application*.xconf`（构建期检查：疑似密钥键名 `password`/`secret`/`token` 出现且值非占位 → 构建失败，要求改走白名单环境变量）。

## 7. 链接与 FFI

- `<link><libraries>` 显式列出原生库：`name`、`kind`（`static`/`dynamic`）、`system`（是否系统库）；
- 未在清单声明的原生库不得链接；FFI 绑定引用未声明库 → 构建失败（第 7 部分 §2.2 可审计）；
- `<link><unsafe>` 缺省 `false`：是否允许 `@unsafe` 受控入口（第 7 部分 §8）；启用后构建日志必须记录；
- 运行时 ABI 符号（`xrt_*`，第 7 部分 §6.1）由工具链自动链接，不需声明，也不允许改写。

## 8. 可复现性

- 同清单 + 同 `xnull.lock` + 同工具链版本 ⇒ 同产物（字节等价为目标，PROJ-08 按摘要比对）；
- 影响产物的输入**穷举**：清单（含继承链）、锁文件、源码、工具链版本、目标平台、profile 集合；除此之外无输入（环境变量仅 `XNULL_REPO` 且不影响产物内容）；
- 产物 `.xmeta` 记录上述全部输入的摘要。

## 9. 验收矩阵

| 编号 | 领域 | 验收内容 |
| --- | --- | --- |
| PROJ-01 | 继承 | 单父展开正确；深度 > 8 失败；环/缺失 parent 失败；`groupId` 被覆盖失败；`artifactId` 必写 |
| PROJ-02 | 坐标与模块 | 坐标重复失败；聚合 modules 展开正确；`pom` 父校验；app 作依赖失败 |
| PROJ-03 | 依赖仲裁 | dependencyManagement 就近提供版本；缺失版本失败；同深度冲突失败并列出路径；显式版本覆盖产生警告 |
| PROJ-04 | 版本规则 | 范围/`SNAPSHOT`/`LATEST` 依赖被拒；`language.version` 范围校验正确 |
| PROJ-05 | 生命周期与产物 | 5 阶段顺序执行；`--skip test` 生效；`deploy`/插件机制不存在；产物与 `.xmeta` 内容正确 |
| PROJ-06 | 配置覆盖 | 五层优先级逐层验证；同层重复键失败；白名单外环境变量被忽略；命令行覆盖并留审计 |
| PROJ-07 | 配置严格性 | 未知键失败并列出；缺失必需键失败；类型解析失败报错含键与层级；`library` 出现 `application.xconf` 失败；疑似密钥构建失败 |
| PROJ-08 | 可复现 | 两次构建摘要一致；`target/` 外无写入 |

## 10. 实现边界（1.x 否决清单）

| 能力 | 状态 | 理由 |
| --- | --- | --- |
| 依赖版本范围 | 否决 | 可复现优先 |
| `SNAPSHOT` / `LATEST` | 否决 | 同上 |
| 构建插件/扩展机制 | 否决 | 隐式行为不可审计；需要时用外部工具 |
| `deploy` 到远程 | 否决 | 发布流程待生态定型 |
| 配置热重载 / 配置中心 | 否决 | 服务配置以启动时五层快照为准 |
| YAML / 嵌套配置 | 否决 | 隐式类型与歧义 |
| 跨服务配置继承 | 否决 | 隐式耦合 |
| 按环境变量激活 profile | 否决 | 不可复现 |
| 远程仓库签名验证 | 非承诺 | 原因：生态未定；后果：不得作为安全边界 |
| 增量编译 / 并行构建策略 | 非承诺 | 原因：实现自由；后果：只保证语义与产物摘要一致 |

## 附录 A：与 Maven / Spring Boot 的对应

| Maven / Spring Boot | 本部分 | 差异 |
| --- | --- | --- |
| `pom.xml` | `xnull.xml` | 元素集更小：无插件、无 `deploy` |
| `parent` 继承 | 单父继承（§3.2） | 可继承字段白名单固定，深度 ≤ 8 |
| `dependencyManagement` | 同构（§3.4） | 缺失版本即失败（Maven 报错同） |
| starter | `<packaging>starter</packaging>` | 同构：能力聚合包 |
| `mvn lifecycle` | 5 阶段（§5.1） | 无插件绑定；无 `deploy` |
| 本地仓库 | `~/.xnull/repository` | Maven 2 布局复用 |
| `application.properties` | `application.xconf`（flat） | 值恒为字符串，类型显式解析；禁 YAML |
| profile 覆盖 | `application-<profile>.xconf` | profile 只由 `--profile` 指定，不读环境 |
| 环境变量覆盖 | 白名单 `XNULL_OVERRIDE_*` | 默认不开放，须在清单登记 |
| spring-boot-configuration | 键空间 + 严格校验 | 未知键启动失败（Spring 默认忽略） |

## 附录 B：决策留痕

1. **单父继承而非多继承**：多父的合并顺序是歧义源；单父 + 白名单字段让"值从哪来"唯一可答。
2. **版本精确、范围/SNAPSHOT 全否**：可复现是硬约束（§8），任何"随最新漂移"的机制都与之冲突。
3. **同深度冲突失败而非取第一个**：Maven 的"先声明者胜"依赖声明顺序，属于不可见输入；失败并列出路径逼迫显式 `dependencyManagement`。
4. **配置 flat properties、值恒字符串**：Spring 的 YAML 隐式类型（`on`、`08`、缩进）是歧义源；显式解析把类型错误提前到启动失败。
5. **未知键启动失败**：Spring 默认忽略未知键，拼错静默生效是生产事故常见来源；本规范选择失败。
6. **环境变量白名单**：Spring 允许全量覆盖，等于"部署环境可改变程序行为且不可审计"；白名单保留运维弹性同时可审计。
7. **跨服务共享只走构建期 `<configuration>`**：运行时跨服务读配置是隐式耦合，且破坏"逐服务"原则。
8. **5 阶段无插件**：插件机制引入任意构建逻辑，与"失败快、输入穷举"冲突；1.x 用外部工具替代。
