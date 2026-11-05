# XNull 解决方案 第 8 部分：工程配置

| 项目 | 内容 |
| --- | --- |
| 文档编号 | 第 8 部分（S9） |
| 文档版本 | 5.2.0 |
| 规范状态 | 正式（已审定 2026-11-05） |
| 发布日期 | 2026-11-05 |
| 上游依赖 | 第 1 部分 §11.2/§11.4/§12；第 4 部分 §7.2；第 6 部分 §4.8/§5；第 7 部分 §2.2/§6.1/§8 |

> **版本说明**：5.2.0 由实现（`impl/internal/xpd`）反向校验附录 C，修补四处"示例能写、文法读不通"的缺口：① `language-version` 用 `[3.3, 4.0)`，原文法只有方括号列表 → 补**范围字面量**产生式；② `module platform`、`exclusion org.old:legacy` 等**无体条目**原文法强制要求 `{ }` → 块体改为可选（C.2、C.3 第 6 条）；③ `db.pool.max-size` 这类**点分键**不属于标识符 → 增「键名」记法并限定只出现在 `configuration` 段（C.3 第 4 条）；④ 资源 glob `**/*.psd` 的 `*` `?` 不在裸词字符集 → 补入。另明确**换行是语句终止符**（叶子条目的结束靠行尾判定），列表/范围不得跨行、条目未换行收尾即报错。新增诊断码 `XPD-105/106/107`。全部规范示例已由自动化用例逐块解析通过。
>
> **版本说明**：5.1.0 追加**资源目录设计**——`src/main/resources` / `src/test/resources`、收录与排除、制品内 `resources/` 前缀、依赖库资源合并与冲突失败、构建期过滤否决、运行时经 `xdk.sys` 资源读取 API 访问（第 6 部分 §4.8）；服务配置文件随之定位到资源根。5.0.0 的其余内容不变。
>
> **定稿说明**：本部分规定 XNull 工程的完备配置：清单段落树与继承、坐标、属性与变量、依赖管理、依赖与插件、仓库与凭据、生命周期与产物、资源目录与打包、服务运行时配置、链接与 FFI 声明、可复现性、诊断码段位，并在附录 A 给出单体工程、多服务工程、聚合工程三类完整实例。草案 v1.0.0（JSON）、v2.0.0（XML）、v3.0.0（TOML）、v4.0.0（扁平 XPD）已归档，其语义结论均被本版吸收。

## 0. 核心立场

- **同一骨架、坐标自显**：每个工程与模块的清单段落结构完全相同；`groupId`/`artifactId`/`version`/`packaging` 必须每个模块自己写，不从 parent 补齐——坐标一眼可见，父工程改版本不会让子模块"改名换姓"。
- **继承只继承配置**：parent 继承 `properties`/`dependencyManagement`/`dependencies`/`repositories`/`build`（含 `plugins`）/`configuration`；**不继承坐标**。
- **版本精确**：依赖与插件版本必须是精确语义化版本；范围、`SNAPSHOT`、最新版一律拒绝。
- **配置逐服务、可覆盖、必校验**：配置只在服务自己名下；覆盖顺序固定五层；未知键与缺失必需键都启动失败。
- **失败快于降级**：清单拼错、变量未解析、冲突无法唯一仲裁——全部构建失败，不静默修正。

## 1. 定位与范围

### 1.1 范围

工程结构与骨架一致性、`xnull.project` 清单（坐标/继承/属性/依赖管理/依赖/仓库/构建/插件/条件覆盖/配置基线/链接）、依赖与插件解析仲裁、作用域、本地与远程仓库、凭据文件、profile 激活、打包类型、生命周期与产物、**资源目录与打包（§5.6）**、锁文件与元数据格式、服务运行时配置文件、链接与 FFI 声明、可复现性、诊断码段位、XPD 文法（附录 C）。

### 1.2 不规定

- 命令行工具的参数拼写（语义等价即可，本部分行为是判定依据）；
- 远程仓库的运营、镜像治理、签名体系（签名验证非承诺，§4.7）；
- IDE 集成、CI 平台适配（编辑器高亮/格式化属工具链，非承诺，§10）；
- 配置热重载与配置中心：1.x 否决，演进方向见 §10。

### 1.3 与其他部分的分界

| 维度 | 规定者 | 本部分的角色 |
| --- | --- | --- |
| 入口签名与语义 | 第 1 部分 §11.2 | 只规定"入口如何被找到"（§5.4） |
| 退出码映射 | 第 4 部分 §7.2 | 引用（编译产物运行期退出码）；构建工具自身退出码见 §5.1 |
| XDK 版本声明机制 | 第 6 部分定案 4-3 | 给出清单字段与校验语义（§3.9） |
| FFI 原生库与 `@unsafe` 闸门 | 第 7 部分 §2.2/§6.1/§8 | 给出清单段落与链接合同（§7） |

## 2. 工程模型

### 2.1 打包类型（`packaging`）

| packaging | 职责 | 产物 | 可否被依赖 |
| --- | --- | --- | --- |
| `pom` | 父工程或聚合工程：只含清单与元数据，可承载 `modules`、`configuration` | 清单 + `.xmeta` | 仅作 parent / 聚合入口 |
| `library` | 库：可被依赖的代码单元 | `.xlib` | 是 |
| `starter` | 能力聚合包：只含依赖声明，引入即传递其 `dependencies` | 清单 + `.xmeta` | 是（传递依赖） |
| `app` | 服务：有入口与自己的运行时配置 | 可执行体 + `.xmeta` | 否 |

**语义约束**：

- 四类使用**同一套段落骨架**（§3.2）；差异只用约束表达，不做"换 packaging 就换一套段落"的分叉；
- `modules` 仅 `pom` 可非空；`configuration` 仅 `pom` 可声明；`entryFile`/`entryPackage` 仅 `app` 可用；`link` 仅 `app`/`library` 可非空；
- `app` 不得作依赖、不得作 parent、不得作 starter 的传递依赖；
- `starter` 的 `dependencies` 一律以 `compile` 声明并传递给使用者；`starter` 出现源码目录（`src/`）→ 失败；
- 父工程必须 `packaging = pom`。

### 2.2 GAV 坐标

```text
groupId    反向域名，小写点分（com.example）
artifactId 小写字母/数字/连字符（order-service）
version    语义化版本，精确（1.4.0）
```

- **三个坐标字段与 `packaging` 必须每个模块显式书写**，包括子模块；
- 同一次构建内 `groupId:artifactId:version` 重复 → 失败；
- 子模块 `groupId` 与父不同是允许的（组织嵌套、适配层），但必须写在清单里——这正是"坐标自显"的收益。

### 2.3 目录布局

```text
order-system/
├── xnull.project           # packaging = pom
├── xnull.lock              # 锁文件（构建生成，纳入版本控制）
├── platform/
│   └── xnull.project       # packaging = pom（父：properties/dependencyManagement/build/plugins）
├── common/
│   ├── xnull.project
│   ├── src/main/x/         # 源码根
│   └── src/main/resources/ # 资源根
├── order-service/
│   ├── xnull.project
│   ├── src/main/x/                 # 源码根
│   └── src/main/resources/         # 资源根
│       ├── application.properties       # 服务配置（§6）
│       ├── application-dev.properties   # profile 覆盖
│       └── templates/                   # 任意资源子树
└── target/                 # 产物根（勿提交）
```

- 源码根缺省 `src/main/x`，测试根缺省 `src/test/x`；可在 `build.sourceRoot` / `build.testRoot` 覆盖；
- 资源根缺省 `src/main/resources`，测试资源根缺省 `src/test/resources`；可在 `build.resources` 覆盖或追加（§5.6）；
- 产物根固定 `target/`，不得作为源码来源，也不得作为资源来源；
- 锁文件位于**聚合根**（无聚合时为工程根），全工程一份（§4.4）。

## 3. 清单 `xnull.project`

### 3.1 每个模块的完整骨架

所有工程与模块使用同一骨架。段落书写顺序不影响语义；格式化工具按下列顺序输出。

```xpd
project {
  groupId    = com.example
  artifactId = order-service
  version    = 1.4.0
  packaging  = app

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  modules {
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency com.example:common {
        version = 1.4.0
      }
    }
  }

  dependencies {
    dependency com.example:common {
    }

    dependency com.example:xdk-web-starter {
      version  = 3.2.1
      scope    = compile
      optional = false
      exclusions {
        exclusion org.old:legacy
      }
    }
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }

  build {
    mode         = release
    warnings     = strict
    entryFile    = src/main/x/main.x
    entryPackage = com.example.order

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
        configuration {
          output = target/gen
        }
      }
    }
  }

  link {
    unsafe = false
    libraries {
      library sqlite3 {
        kind   = dynamic
        system = true
      }
    }
  }

  profiles {
    profile dev {
      activation {
        platform = macos
      }
      properties {
        build-mode = debug
      }
    }
  }

  configuration {
    db.pool.max-size = 8
    envOverrides     = [db.url, db.password]
  }
}
```

### 3.2 段落总表（全部 packaging 通用）

| 段落 | 必需 | 适用 | 可重复 | 内容 |
| --- | --- | --- | --- | --- |
| `project` | 是 | 全部 | 否 | 根块，文件内唯一 |
| `groupId` / `artifactId` / `version` / `packaging` | 是 | 全部 | 否 | 根块字段（§2.2、§2.1） |
| `parent` | 否 | 全部 | 否 | 单父（§3.3） |
| `modules` | 否 | 全部（非空仅 `pom`） | `module` 可重复 | 聚合子目录 |
| `properties` | 否 | 全部 | 键可重复（键唯一） | 变量（§3.4） |
| `dependencyManagement` | 否 | 全部 | 内部结构固定 | 版本仲裁（§3.5） |
| `dependencies` | 否 | 全部 | `dependency` 可重复 | 依赖（§3.6） |
| `repositories` | 否 | 全部 | `repository` 可重复 | 远程仓库（§4.7） |
| `build` | 否 | 全部 | 否 | 编译选项、入口、资源根（§5.2、§5.6） |
| `plugins` | 否 | 全部（位于 `build` 内） | `plugin` 可重复 | 构建插件（§5.5） |
| `link` | 否 | `app` / `library`（非空） | 否 | 原生库与 `@unsafe`（§7） |
| `profiles` | 否 | 全部 | `profile` 可重复 | 条件覆盖（§3.8） |
| `configuration` | 否 | 仅 `pom` | 键可重复（键唯一） | 服务配置基线（§3.10） |

**通用规则**：

- 未知段落、未知字段、未知块名 → 失败；
- 单次段落重复出现 → 失败；同段内字段重复 → 失败；
- 容器段落只能包含其规定的条目段落：`dependencies`→`dependency`、`exclusions`→`exclusion`、`repositories`→`repository`、`plugins`→`plugin`、`modules`→`module`、`libraries`→`library`、`profiles`→`profile`；
- 空段落等价于省略，但出现即必须合法。

### 3.3 继承规则

- **单父**：`parent` 至多一个；不写即根工程；
- parent 定位：`relativePath`（缺省 `../xnull.project`）→ 本地仓库 → 远程仓库（§4.7）；
- **继承**：`properties`（子覆盖父）、`dependencyManagement`（合并，子优先）、`dependencies`（合并，同坐标子覆盖父）、`repositories`（按 id 合并，子覆盖父）、`build`（字段级覆盖，`plugins` 按坐标合并）、`configuration`（按键合并，子覆盖父）；
- **不继承**：`groupId`/`artifactId`/`version`/`packaging`、`parent`、`modules`、`profiles`；
- 继承深度上限 8；环、self-parent、缺失 parent、parent 非 `pom` → 失败。

### 3.4 properties 与变量替换

- `properties` 段内为 `键 = 值`，键名 kebab-case，值恒字符串；
- 变量形式 `${name}`，可出现在裸词或字符串内部；
- 替换在**解析期**执行（清单载入后、依赖解析前），单次替换，不递归展开替换结果；
- 内置变量（只读）：`project.groupId`、`project.artifactId`、`project.version`、`project.basedir`、`xnull.version`（工具链版本）；
- 子覆盖父；**未解析变量 → 失败**（不保留原文、不替换为空串）；
- 变量可用于任意字段值（含 `parent.relativePath`、依赖 `version`、插件版本）；
- **不得用于枚举字段**（`packaging`、`scope`、`phase`、`kind`）：枚举值必须字面可见，变量化即失败——否则"这个工程是什么类型"要看两处才能答。

### 3.5 dependencyManagement

```xpd
dependencyManagement {
  dependencies {
    dependency com.example:common {
      version = 1.4.0
      exclusions {
        exclusion org.old:legacy
      }
    }
  }
}
```

- 只声明 `version`（必需）与可选 `exclusions`；**出现 `scope`/`optional` → 失败**（使用点的决定不在此处）；
- 子模块依赖不写 `version` 时由最近的管理项唯一提供（就近：本模块 > 父链近端 > 远端）；
- 依赖内显式写 `version` 覆盖管理版本：允许，产生构建警告；
- 声明了依赖却无人提供版本 → 失败（点名 `groupId:artifactId`）；
- 同一管理表内坐标重复 → 失败。

### 3.6 dependencies

```xpd
dependencies {
  dependency com.example:common {
  }

  dependency com.example:xdk-web-starter {
    version  = 3.2.1
    scope    = compile
    optional = true
    exclusions {
      exclusion org.old:legacy
    }
  }
}
```

| 字段 | 缺省 | 说明 |
| --- | --- | --- |
| `version` | 由 dependencyManagement 提供 | 两者都无 → 失败 |
| `scope` | `compile` | `compile` / `runtime` / `test` / `provided`（§3.7） |
| `optional` | `false` | `true` 不传递 |
| `exclusions` | 空 | 精确坐标删除传递依赖 |

### 3.7 作用域

| scope | 编译可见 | 运行时可见 | 传递 |
| --- | --- | --- | --- |
| `compile` | 是 | 是 | 是（compile） |
| `runtime` | 否 | 是 | 是（runtime） |
| `test` | 测试可见 | 测试运行 | 否 |
| `provided` | 是 | 否（宿主提供） | 否 |

- 作用域传播只有 `compile`→`compile`、`runtime`→`runtime` 两种，其余不传递；
- `test` 依赖不得出现在 `app` 的产物依赖清单中；
- `provided` 由宿主（运行时/平台）提供，构建期不打包、不传递。

### 3.8 profiles

```xpd
profiles {
  profile dev {
    activation {
      platform = macos
    }
    properties {
      build-mode = debug
    }
    dependencies {
      dependency com.example:dev-tools {
        version = 0.9.0
      }
    }
  }
}
```

- 激活（定案两种）：显式 `-Pdev`；`activation.platform` 匹配当前构建平台。**环境变量激活 → 否决**（不可复现）；
- 可覆盖：`properties`、`dependencies`、`build`（含 `plugins`）、`configuration`；
- 不可覆盖（出现即失败）：`groupId`/`artifactId`/`version`/`packaging`、`parent`、`modules`、`repositories`；
- 多个 profile 同时激活且改同一键 → 失败（不静默取后者）；
- 同时激活的 profile 集合必须**显式确定**：`-P` 与 `activation.platform` 的并集，写入 `.xmeta`。

### 3.9 版本声明（落实第 6 部分定案 4-3）

- `properties.xdk-version`：所需 XDK 版本（精确）；工具链 XDK 不匹配 → 失败；
- `properties.language-version`：语言版本范围，**唯一允许范围表达式的位置**（`[3.3, 4.0)`）；范围外 → 失败；
- 两者必须由**根 `pom`** 定义；子模块重复定义 → 失败。

### 3.10 configuration（服务配置基线）

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| 任意运行时键 | 否 | 键名必须符合 §6.3；值恒字符串；作为所有子服务配置的第 0 层（§6.6） |
| `envOverrides` | 否 | 列表；声明白名单键（运行时键名），决定哪些键可被环境变量覆盖（§6.4） |

- 仅 `pom` 可声明；其他 packaging 出现 → 失败；
- **禁止 `xnull.` 前缀键**（工具链保留）；
- 疑似密钥键（`password`/`secret`/`token`/`key`）且值非占位 → 构建失败（§6.6）；
- 值不得包含变量占位以外的动态内容；变量在此段同样按 §3.4 替换。

## 4. 依赖与插件解析

### 4.1 解析顺序

1. 展开继承链 → 合并六类配置（§3.3）；
2. 变量替换；
3. 逐模块确定依赖与插件坐标版本（§3.5、§5.5）；
4. 构建依赖图（传递 + 作用域传播 + exclusions）；
5. 冲突仲裁（§4.2）；
6. 写入锁文件（§4.4）；
7. 仓库拉取（§4.7）。

### 4.2 冲突仲裁

- **最近优先**（nearest-wins）：依赖树中路径最短者胜；
- 同深度多处出现 → **失败并列出全部路径**（不取第一个，避免声明顺序成为不可见输入）；
- `dependencyManagement` 版本恒优先于最近优先；
- 仲裁结果必须唯一，否则失败。

### 4.3 版本规则

| 形态 | 状态 |
| --- | --- |
| 精确 `1.4.0` | 定案 |
| 预发布 `1.2.3-rc.1` | 定案（精确即允许） |
| 范围 `[1.0,2.0)` | 否决（依赖与插件中）；仅 `language-version` 可用 |
| `SNAPSHOT` | 否决 |
| `LATEST` / `RELEASE` / `*` | 否决 |
| 工作区模块 | 定案：`modules` 聚合或 `relativePath` 覆盖，不靠版本号变通 |

### 4.4 锁文件 `xnull.lock`

格式为 XPD。**全工程一份**，位于聚合根（无聚合时为工程根），纳入版本控制。

```xpd
lock {
  version = 1

  entry com.example:common 1.4.0 {
    kind       = dependency
    repository = central
    sha256     = 0000000000000000000000000000000000000000000000000000000000000000  # 64 位小写十六进制
  }

  entry com.example:codegen 1.2.0 {
    kind       = plugin
    repository = central
    sha256     = 1111111111111111111111111111111111111111111111111111111111111111
  }
}
```

| 规则 | 内容 |
| --- | --- |
| 条目 | 每个解析到的依赖与插件各一条，`kind` 取值 `dependency` / `plugin` |
| 排序 | 按 `groupId:artifactId` 字典序升序，同一坐标只有一条（保证字节稳定） |
| 摘要 | 制品内容 SHA-256，64 位小写十六进制；下载后校验，不符 → 失败 |
| 来源 | `repository` 为仓库 id |
| 一致性 | 锁与清单不一致 → **失败**（提示重新生成），不自动更新 |
| 生成 | 无锁首次构建生成并警告提交；`--update-lock` 显式重生成（唯一的重生成入口） |
| 读取 | 构建以锁为准（先锁后网）；锁中坐标在清单中不存在 → 失败 |

### 4.5 传递性约束

- 环依赖 → 失败；`app` 作为依赖 → 失败；
- 依赖声明的 `xdk-version` 与本工程不一致的大版本 → 失败；
- 插件不得依赖 `app`（插件不得引入服务代码）；
- `starter` 的传递依赖不得含 `app`。

### 4.6 仓库选择与默认仓库

- **声明了 `repositories`**：只使用声明的仓库，按声明顺序尝试，首个命中即用；不会隐式追加任何仓库；
- **全链未声明 `repositories`**：使用内置默认仓库 `central` = `https://repo.xnull.dev/repository`；
- 脱网环境：`XNULL_REPO` 指向本地仓库目录即为唯一来源，此时构建不访问网络（缺件 → 失败）。

### 4.7 仓库、镜像与凭据

```xpd
repositories {
  repository central {
    url = https://repo.xnull.dev/repository
  }
  repository mirror {
    url      = https://mirror.internal/repository
    mirrorOf = central
  }
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `url` | 是 | HTTP(S)；制品按 `groupId/artifactId/version/` 三级目录存放，文件名 `<artifactId>-<version>.<ext>` |
| `mirrorOf` | 否 | 被替代的仓库 id；同 id 只能有一个 mirror；mirror 自身不得再被 mirror 替代 |

**凭据文件** `~/.xnull/settings.xpd`（不属工程，不入版本控制）：

```xpd
settings {
  credentials central {
    username   = deployer
    tokenEnv   = XNULL_TOKEN_CENTRAL
  }
}
```

- 凭据只从该文件读取，**不得写入工程清单**；
- 密码/令牌**只能以环境变量名出现**（`tokenEnv`），文件内不存明文——构建日志与 `.xmeta` 均不得出现其值；
- 缺失凭据且仓库需要认证 → 失败（不匿名重试降级）；
- 签名验证：非承诺（原因：生态未定；依赖后果：不得作为安全边界，1.x 不做）。

## 5. 生命周期、构建与插件

### 5.1 阶段与工具链退出码

| 阶段 | 动作 |
| --- | --- |
| `validate` | 词法/文法/未知段落校验、继承展开、变量替换、入口存在性、锁一致性 |
| `compile` | 编译 `src/main/x` |
| `test` | 运行 `src/test/x` 测试入口（可 `--skip test`） |
| `package` | 产出 `target/<artifactId>-<version>.<ext>` + `.xmeta` |
| `install` | 安装到本地仓库（可跳过） |

**工具链退出码（定案，与第 4 部分 §7.2 的运行期退出码互不影响）**：

| 码 | 含义 |
| --- | --- |
| `0` | 全部阶段成功 |
| `1` | 构建失败（编译/测试/插件/校验不通过） |
| `2` | 清单或用法错误（词法/文法/未知段落/参数拼写） |
| `130` | 被中断（收到 SIGINT） |

- `deploy`（远程发布）1.x 否决（见索引 §9 工程层候补）；
- 插件只能绑定上述 5 阶段，不得新增阶段。

### 5.2 build 字段

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `mode` | `debug` / `release` / `size` | 优化档位，不改变语言语义；缺省 `debug` |
| `warnings` | `default` / `strict` | `strict` 把警告提升为错误 |
| `sourceRoot` / `testRoot` | 路径 | 覆盖缺省 `src/main/x` / `src/test/x` |
| `resources` | 容器（`resource`） | 资源根与收录规则（§5.6）；缺省 `src/main/resources` |
| `entryFile` / `entryPackage` | 路径 / 包名 | 入口定位（§5.4）；`app` 必需，非 `app` 出现 → 失败 |
| `plugins` | 容器 | §5.5 |

- 工程级定义，模块级覆盖；环境变量不参与构建选项（`XNULL_REPO` 例外）；
- `sourceRoot` 不得等于或包含 `target/`。

### 5.3 产物与元数据 `.xmeta`

- `target/<artifactId>-<version>.<ext>`：`app` → 可执行体，`library` → `.xlib`，`pom`/`starter` → 仅清单与元数据；
- 构建不写入清单目录以外位置（缓存写入 `target/.cache`）；
- `.xmeta` 必需字段（格式 XPD）：

| 字段 | 内容 |
| --- | --- |
| `groupId` / `artifactId` / `version` / `packaging` | 完整坐标 |
| `platform` | 目标平台标识 |
| `xdkVersion` / `languageVersion` | 来自 `properties` 的生效值 |
| `toolchainVersion` | `xnull.version` |
| `profiles` | 本次生效的 profile id 列表（升序） |
| `plugins` | 生效插件坐标 + goal + phase 列表（按执行顺序） |
| `lockSha256` | 本次构建所用锁文件的内容摘要 |
| `inputs` | 清单链、源码根、锁文件摘要的汇总摘要 |

### 5.4 入口解析（落实第 1 部分 §11.4）

1. `entryFile` + `entryPackage`：入口为该文件 `main`，且必须位于 `entryPackage` 内；
2. 仅 `entryFile`：入口为该文件 `main`；
3. 无入口字段：默认 `src/main/x/main.x`；
4. 无清单：当前目录 `main.x`（第 1 部分 §11.4）。

失败集合：文件不存在、无匹配 `main`、多个匹配 `main`、`entryPackage` 不匹配、非 `app` 声明入口。

### 5.5 插件

```xpd
build {
  plugins {
    plugin com.example:codegen 1.2.0 {
      phase = validate
      goal  = check
      configuration {
        output = target/gen
      }
    }
  }
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| 块头坐标 `groupId:artifactId` + 版本参数 | 是 | 版本必须精确（§4.3），与依赖同一套仓库与锁 |
| `phase` | 是 | `validate` / `compile` / `test` / `package` / `install` 之一 |
| `goal` | 是 | 插件声明的 goal 名 |
| `configuration` | 否 | 插件自定义键值；键必须由插件元数据 `configKeys` 声明，未声明 → 失败 |

**插件合同（规范性）：**

| 约束 | 内容 |
| --- | --- |
| 阶段 | 只能绑定 5 阶段之一；同阶段内按声明顺序执行，跨模块按 `modules` 声明顺序 |
| goal | 必须显式声明；插件未声明的 goal 不得执行 |
| 文件系统 | 只读：清单、`src/`、依赖；只写：`target/`。越界写 → 构建失败 |
| 网络 | **禁止网络访问**（原因：网络使构建不可复现；依赖后果：需要联网的步骤必须放在构建之外） |
| 环境变量 | 只读访问限于 `XNULL_REPO` 与 `configuration.envOverrides` 白名单；其余不可见 |
| 语义 | 不得改变语言语义：不得改写 `src/`、不得注入运行时行为；允许产物变换、检查/报告、生成到 `target/` |
| 失败 | 非零退出 = 构建失败（不降级为警告） |
| 隔离 | 插件自身 `dependencies` 走同一套仲裁，但不进入被构建工程的编译类路径 |
| 可复现 | 坐标、goal、phase 全部入锁与 `.xmeta`；同锁 ⇒ 同插件行为 |

**插件包元数据 `.xplugin`**（位于插件制品根，格式 XPD）：

```xpd
plugin {
  groupId          = com.example
  artifactId       = codegen
  version          = 1.2.0
  toolchainVersion = 5.0.0

  goals {
    goal check {
      phase      = validate
      configKeys = [output, strict]
    }
  }
}
```

- 元数据缺失或与清单不符（坐标、phase、goal、configKeys、工具链版本）→ 失败；
- `toolchainVersion` 为主版本兼容约束：主版本不同 → 失败；
- **与运行时动态模块无关**：本节插件是构建期执行体，不进入产物；程序运行期动态装载/卸载托管模块按第 3 部分定案（首发基线不包含）。

### 5.6 资源目录与打包

**定义**：资源 = 随产物发布、不参与编译的非 `.x` 文件——模板、静态页面、图标、SQL、schema、默认数据、本地化文本等。

```xpd
build {
  resources {
    resource src/main/resources {
    }
    resource assets {
      includes = [images/**, fonts/**]
      excludes = [**/*.psd]
    }
  }
}
```

| 规则 | 内容 |
| --- | --- |
| 缺省资源根 | `src/main/resources`（唯一缺省根，不声明 `resources` 时生效）；测试资源根 `src/test/resources` |
| 追加资源根 | `resource <dir>` 可重复；未声明任何 `resource` 时只有缺省根；**声明了 `resource` 就只用声明的**（不叠加缺省根，避免"到底收录了什么"两处判断） |
| 收录 | 目录内全部常规文件，按**相对该资源根的路径**收录；空目录不产生条目 |
| 过滤 | `includes` 缺省 `**`；`excludes` 优先于 `includes`；`/` 分隔的 glob（`*` 单段、`**` 跨段、`?` 单字符），不支持正则与字符类 |
| 制品内位置 | 固定前缀 `resources/`，其后保持相对路径：`src/main/resources/templates/a.html` → 制品内 `resources/templates/a.html` |
| 冲突 | 两条来源映射到同一制品路径 → **失败**（点名两个来源路径）；不静默后者覆盖前者 |
| 构建期过滤/变量替换 | **否决**（原因：资源字节随清单变化后无法按文件审查，且与运行时配置职责重叠；依赖后果：需按环境变化的内容必须走运行时配置，§6） |
| 符号链接 | 按目标内容读取；断链 → 失败 |
| 权限位、时间戳 | 不保留（产物摘要只含内容） |
| 资源根内的 `.x` 文件 | 不编译，按数据打包（定案；要参与编译必须放源码根） |
| 适用 packaging | `library` / `app` / `starter`；`pom` 出现非空资源根或 `build.resources` → 失败 |
| 测试资源 | 仅 `test` 阶段可见，不进入产物 |

**依赖库资源合并**：

- `app` 打包时，把自身资源与全部 `compile`/`runtime` 依赖（含 `starter` 传递）的资源合并到同一 `resources/` 前缀；
- 同路径冲突 → **失败**（点名两个 `groupId:artifactId`）；
- `starter` 的资源随其元数据发布，**不合并**给使用者（starter 无代码产物）；
- `library` 的 `.xlib` 只含自身资源。

**运行时访问**：只读；路径以 `resources/` 为根（如 `templates/a.html`）；禁止绝对路径与 `..` 段；不存在 → `NotFound` 错误。API 见第 6 部分 §4.8（`xdk.sys`）。资源与文件系统分离：资源不支持写入、删除、重命名。

**与配置的关系**：`application.properties` / `application-<profile>.properties` 是**资源根下的固定文件名资源**（§6.1），只允许位于资源根顶层，不得放子目录；构建期读取并计入 `.xmeta` 输入摘要。

## 6. 服务运行时配置

### 6.1 逐服务原则

- **配置只属于服务自己**：只有 `packaging = app` 的模块拥有 `application.properties`；其他 packaging 出现该文件 → 构建失败；
- 配置文件是**资源根顶层的固定文件名资源**：`src/main/resources/application.properties`（基线），可选 `src/main/resources/application-<profile>.properties`；放在资源子目录或模块根 → 构建失败（§5.6）；
- 文件名中的 profile 必须与 `profiles.profile` 的 id 之一同名，否则失败；
- 服务之间**不得隐式共享配置**；共享只能经父 `pom` 的 `configuration` 段（构建期冻结，§6.6）；
- 集中配置中心：1.x 不做，见 §10 演进方向。

### 6.2 格式

```properties
# application.properties —— UTF-8，flat properties
net.http.listen-port=8080
db.url=jdbc:sqlite:data/order.db
db.pool.max-size=8
feature.new-checkout=false
```

- 一行一键，`#` 注释；**值一律按字符串读入**，类型由绑定代码显式解析；
- 清单用段落式 XPD（需要结构：段落树、条目容器、继承），配置用平面键值（只需要键值）——两者共享注释与值规则，不构成第二套心智模型；
- YAML / JSON / 嵌套结构 **否决**（原因：隐式类型与缩进歧义；依赖后果：复杂结构在代码中构造）；
- 多行值、转义序列 1.x 否决；值内 `#` 无转义，需 `#` 时写在其后的注释位置之外（键值内出现 `#` → 视为注释开始）。

### 6.3 键空间

| 前缀 | 归属 | 示例 |
| --- | --- | --- |
| `xnull.` | 工具链保留 | `xnull.profile` |
| `xdk.` | XDK 包（第 6 部分） | `xdk.log.level` |
| `app.` | 服务自身 | `app.name` |
| 自定义（小写点分，段内连字符） | 服务内部 | `net.http.listen-port` |

- 键名只允许小写字母、数字、点、连字符；大写、下划线、连续点、首尾点 → 启动失败；
- 键长度上限 128 字符。

### 6.4 覆盖优先级（低 → 高，五层定案）

| 层 | 来源 | 说明 |
| --- | --- | --- |
| 0 | 父 `pom` 的 `configuration` | 构建期冻结，§6.6 |
| 1 | 内建缺省 | 绑定代码 / XDK 包声明 |
| 2 | `resources/application.properties` | 服务基线（资源根顶层） |
| 3 | `resources/application-<profile>.properties` | `--profile` 指定，不读环境变量 |
| 4 | 环境变量 | **仅白名单键** `XNULL_OVERRIDE_<KEY>`（大写、点→下划线），白名单由 `configuration.envOverrides` 列出 |
| 5 | 命令行 | `--key=value`，覆盖一切；写入启动审计日志 |

- 同层重复键 → 启动失败；
- 白名单外的 `XNULL_*` 被忽略（不报错）；白名单内键缺失不算错；
- 覆盖只能改值，**不能新增键**（新增即未知键，§6.5）；
- 层 0 与层 2 冲突时层 2 胜（第 0 层只是基线）；层 0 的键若无人覆盖则生效。

### 6.5 严格校验

- **未知键 = 启动失败**（列出全部未知键；绑定代码必须声明所用键）；
- 必需键缺失 = 启动失败（点名）；
- 值解析失败（如 `listen-port=abc`）= 启动失败；
- 错误信息必须含：键名、所在层、文件路径（或"命令行"）；
- 配置校验发生在 `main` 执行前；校验失败 → 退出码按第 4 部分 §7.2 初始化失败处理。

### 6.6 跨服务共享（仅构建期）

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

- `configuration` 作为所有子服务配置的**第 0 层**（低于 `application.properties`，可被覆盖）；
- 运行时不跨服务读取（否决"配置继承另一服务"）；外部配置服务 1.x 否决（§10）；
- 密钥不得写入 `configuration` 或 `application*.properties`：构建期检查疑似密钥键（`password`/`secret`/`token`/`key`）且值非占位 → 构建失败，要求改走白名单环境变量。

## 7. 链接与 FFI

```xpd
link {
  unsafe = false
  libraries {
    library sqlite3 {
      kind   = dynamic
      system = true
    }
  }
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `unsafe` | 否 | 缺省 `false`；`true` 表示允许 `@unsafe` 受控入口（第 7 部分 §8），启用后构建日志必须记录 |
| `library <name>` | 是（非空时） | 原生库名 |
| `kind` | 是 | `static` / `dynamic` |
| `system` | 否 | 缺省 `false`；`true` 表示系统库（由宿主提供，不打包） |

- 未声明的原生库不得链接；FFI 绑定引用未声明库 → 构建失败（第 7 部分 §2.2 可审计）；
- 同名库重复声明 → 失败；
- 运行时 ABI 符号（`xrt_*`，第 7 部分 §6.1）由工具链自动链接，不需声明，不允许改写；
- 非 `app`/`library` 声明非空 `link` → 失败。

## 8. 可复现性

- 同清单 + 同锁文件 + 同工具链版本 ⇒ 同产物（PROJ-09 按摘要比对）；
- 输入穷举：清单（含继承链）、锁文件、源码、工具链版本、目标平台、profile 集合、生效插件集合。除此之外无输入（`XNULL_REPO` 只影响取件位置；插件禁网、禁环境读取，§5.5）；
- `.xmeta` 记录上述全部输入摘要；
- 锁文件字节稳定（§4.4 排序规则），同一解析结果两次生成内容相同。

## 9. 验收矩阵

| 编号 | 领域 | 验收内容 |
| --- | --- | --- |
| PROJ-01 | 骨架与坐标 | 段落顺序无关；未知段落/字段失败；单次段落重复失败；容器段落只含规定条目；四字段缺任一失败；坐标重复失败；子模块 `groupId` 可与父不同 |
| PROJ-02 | 继承 | 单父展开正确；深度 > 8 失败；环/缺失/非 pom parent 失败；**坐标不从父继承**；`properties`/`dependencyManagement`/`repositories`/`configuration` 合并规则正确 |
| PROJ-03 | 依赖仲裁 | 管理表就近提供版本；缺失版本失败；同深度冲突失败并列出路径；显式版本覆盖产生警告；管理表出现 `scope`/`optional` 失败 |
| PROJ-04 | 版本与锁 | 范围/`SNAPSHOT`/`LATEST` 被拒（依赖与插件）；锁条目排序与摘要正确；锁与清单不一致失败；锁内多余坐标失败；`--update-lock` 为唯一重生成入口 |
| PROJ-05 | 生命周期与产物 | 5 阶段顺序执行；`--skip test` 生效；`deploy` 不存在；工具链退出码 0/1/2/130 正确；`.xmeta` 字段完整 |
| PROJ-06 | 插件 | 版本精确；phase 合法性；未声明 goal 拒绝；`configuration` 键未声明失败；写 `target/` 之外失败；网络被拒；非零退出即失败；插件依赖不进编译类路径；`.xplugin` 缺失或字段不符失败 |
| PROJ-07 | 配置覆盖 | 层 0—5 逐层验证；同层重复键失败；白名单外环境变量被忽略；命令行覆盖并留审计；profile 文件名与清单 id 不符失败 |
| PROJ-08 | 配置严格性 | 未知键失败并列出；缺失必需键失败；类型解析失败报错含键与层级；非 app 出现 `application.properties` 失败；疑似密钥构建失败；键名非法失败 |
| PROJ-09 | 可复现 | 两次构建摘要一致；锁字节稳定；`target/` 外无写入 |
| PROJ-10 | 文法 | 附录 C 全部错误规则有对应用例；诊断含行号/列号/段落路径；诊断码落在规定段位 |
| PROJ-11 | 资源 | 缺省资源根收录正确；`includes`/`excludes` 优先级与 glob 匹配正确；制品内 `resources/` 前缀与相对路径保持；多来源同路径冲突失败并点名；依赖库资源合并进 `app`、冲突失败；`starter` 资源不合并给使用者；`pom` 出现资源根失败；`.x` 文件按数据打包；符号链接跟随、断链失败；无过滤（清单变量不改变资源字节）；资源配置放子目录或模块根失败 |

## 10. 实现边界与演进方向

| 能力 | 1.x 状态 | 说明 |
| --- | --- | --- |
| 插件机制 | 定案（受控） | 约束见 §5.5 |
| 插件新增阶段 | 否决 | 阶段集固定 5 个 |
| 插件访问网络 | 否决 | 可复现优先 |
| 依赖/插件版本范围 | 否决 | 可复现优先 |
| `SNAPSHOT` / `LATEST` | 否决 | 同上 |
| `deploy` 到远程 | 否决 | 发布流程待生态定型；见索引 §9 工程层候补 |
| 配置热重载 | 否决 | 配置以启动时五层快照为准 |
| 配置中心（类 Nacos 服务） | 否决（1.x）· 演进方向 | 两条路径：① 兼容 Nacos 协议（只替换第 2 层以上来源，五层顺序不变）；② 自研外部配置服务。硬准入：启动快照可审计；断连且无快照 → 启动失败 |
| YAML / 嵌套配置 | 否决 | 隐式类型与歧义 |
| 跨服务配置继承 | 否决 | 隐式耦合 |
| 环境变量激活 profile | 否决 | 不可复现 |
| 远程仓库签名验证 | 非承诺 | 原因：生态未定；后果：不得作为安全边界 |
| 增量编译 / 并行构建策略 | 非承诺 | 原因：实现自由；后果：只保证语义与产物摘要一致 |
| 编辑器高亮/格式化 | 非承诺（工具链交付） | `xnull fmt` 与高亮插件不属规范 |
| 构建产物加密/混淆 | 否决 | 不属 1.x 语言工程范围 |
| 资源构建期过滤/变量替换 | 否决 | 原因：资源字节随清单变化后无法按文件审查；依赖后果：按环境变化的内容必须走运行时配置 |
| 资源体积上限 | 非承诺 | 原因：资源体量由使用方决定；后果：超大资源会拉长构建时间与内存占用，不设规范上限 |

**资源目录能力归属（定案）**：资源打包规则归本部分 §5.6；资源读取 API 归第 6 部分 §4.8（`xdk.sys`）；工具链只负责按 §5.6 组装制品，不解释资源内容。

## 附录 A：三类工程完整实例

### A.1 单体工程（一个服务，无父、无聚合）

```text
single-app/
├── xnull.project
├── xnull.lock
├── src/main/x/main.x
└── src/main/resources/
    ├── application.properties
    └── templates/page.html
```

`xnull.project`（`packaging = app`，无 `parent`、无 `modules`、无 `repositories` → 使用默认仓库）：

```xpd
project {
  groupId    = com.example
  artifactId = single-app
  version    = 0.1.0
  packaging  = app

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencies {
    dependency com.example:xdk-web-starter {
      version = 3.2.1
    }
  }

  build {
    mode         = release
    warnings     = strict
    entryFile    = src/main/x/main.x
    entryPackage = com.example.app

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }

  link {
    unsafe = false
    libraries {
      library sqlite3 {
        kind   = dynamic
        system = true
      }
    }
  }

  profiles {
    profile dev {
      activation {
        platform = macos
      }
      properties {
        build-mode = debug
      }
    }
  }
}
```

`src/main/resources/application.properties`：

```properties
app.name=single-app
net.http.listen-port=8080
db.url=jdbc:sqlite:data/app.db
db.pool.max-size=8
```

`src/main/resources/templates/page.html`（普通资源，运行期以 `templates/page.html` 读取）：

```html
<!doctype html>
<title>single-app</title>
```

要点：单文件即工程；`modules`/`configuration`/`parent` 全部省略（骨架允许省略空段落）；缺省资源根 `src/main/resources` 无需在清单声明即生效；锁文件与清单同级。

### A.2 多服务工程（聚合根 + 父工程 + 公共库 + 两个服务）

```text
order-system/
├── xnull.project              # pom：聚合（modules）+ 仲裁根
├── xnull.lock
├── platform/
│   └── xnull.project          # pom：父（properties / dependencyManagement / build.plugins / configuration）
├── common/
│   ├── xnull.project          # library
│   └── src/main/
│       ├── x/
│       └── resources/         # 库资源（合并进使用方产物）
│           └── templates/mail/order-created.html
├── order-service/
│   ├── xnull.project          # app
│   └── src/main/
│       ├── x/
│       └── resources/
│           ├── application.properties
│           ├── application-dev.properties
│           └── static/index.html
├── payment-service/
│   ├── xnull.project          # app
│   └── src/main/
│       ├── x/
│       └── resources/
│           └── application.properties
└── target/
```

**聚合根 `xnull.project`**：

```xpd
project {
  groupId    = com.example
  artifactId = order-system
  version    = 2.0.0
  packaging  = pom

  modules {
    module platform
    module common
    module order-service
    module payment-service
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }
}
```

**父工程 `platform/xnull.project`**（统一版本与产物规范，供各服务继承）：

```xpd
project {
  groupId    = com.example
  artifactId = platform
  version    = 2.0.0
  packaging  = pom

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency com.example:common {
        version = 2.0.0
      }
      dependency com.example:xdk-web-starter {
        version = 3.2.1
      }
      dependency com.example:xdk-metrics {
        version = 1.6.0
      }
    }
  }

  build {
    warnings = strict
    mode     = release

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }

  configuration {
    db.pool.max-size = 16
    xdk.log.level    = info
    envOverrides     = [db.url, db.password]
  }
}
```

**公共库 `common/xnull.project`**：

```xpd
project {
  groupId    = com.example
  artifactId = common
  version    = 2.0.0
  packaging  = library

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  dependencies {
    dependency com.example:xdk-metrics {
    }
  }
}
```

**服务 `order-service/xnull.project`**（坐标自己写，不从父继承；依赖版本由父的管理表提供）：

```xpd
project {
  groupId    = com.example
  artifactId = order-service
  version    = 2.0.0
  packaging  = app

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  dependencies {
    dependency com.example:common {
    }
    dependency com.example:xdk-web-starter {
    }
  }

  build {
    entryFile    = src/main/x/main.x
    entryPackage = com.example.order
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }
}
```

`order-service/src/main/resources/application.properties`（本服务专属）：

```properties
app.name=order-service
net.http.listen-port=8081
db.url=jdbc:sqlite:data/order.db
```

`order-service/src/main/resources/application-dev.properties`（dev profile 覆盖，仅覆盖值，不新增键）：

```properties
xdk.log.level=debug
db.url=jdbc:sqlite:/tmp/order-dev.db
```

**服务 `payment-service/xnull.project`** 与前者同构（`artifactId`、`entryPackage`、端口不同），其 `application.properties` 只含支付侧键（`app.name`、`net.http.listen-port=8082`、`payment.gateway.url`）。

要点：聚合根只负责 `modules` 与仲裁根；父工程负责版本与构建规范；**每个服务各自一份配置，互不读取**；`db.pool.max-size` 来自父 `configuration`（层 0），`db.url` 由各服务自己的 `application.properties` 覆盖（层 2），`db.password` 只能经白名单环境变量（层 4）注入。

资源要点：`common` 的 `templates/mail/order-created.html` 在打包 `order-service` 时合并进 `resources/templates/mail/order-created.html`，运行期用 `templates/mail/order-created.html` 读取；`payment-service` 不引用该模板，其产物内不含该文件（合并只按依赖关系，不按工作区）。若 `common` 与 `order-service` 各有一份同名模板 → 打包失败并点名两个来源（§5.6）。

### A.3 聚合工程（多库统一发布，无服务）

```text
sdk-suite/
├── xnull.project          # pom：聚合 + 仲裁
├── xnull.lock
├── core/
│   ├── xnull.project      # library
│   └── src/main/x/
├── codec/
│   ├── xnull.project      # library（依赖 core）
│   └── src/main/x/
├── http/
│   ├── xnull.project      # library（依赖 core、codec）
│   └── src/main/x/
└── cli/
    ├── xnull.project      # app（依赖 http）
    └── src/main/x/
```

**聚合根 `xnull.project`**：

```xpd
project {
  groupId    = io.xnull
  artifactId = sdk-suite
  version    = 3.1.0
  packaging  = pom

  modules {
    module core
    module codec
    module http
    module cli
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency io.xnull:core {
        version = 3.1.0
      }
      dependency io.xnull:codec {
        version = 3.1.0
      }
      dependency io.xnull:http {
        version = 3.1.0
      }
    }
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }
}
```

**`http/xnull.project`**（库依赖不带版本，全部由聚合根的仲裁表决定；`install` 后四件产物进本地仓库）：

```xpd
project {
  groupId    = io.xnull
  artifactId = http
  version    = 3.1.0
  packaging  = library

  dependencies {
    dependency io.xnull:core {
    }
    dependency io.xnull:codec {
    }
  }

  build {
    warnings = strict
  }
}
```

**`cli/xnull.project`**（唯一的 `app`，产出可执行体）：

```xpd
project {
  groupId    = io.xnull
  artifactId = cli
  version    = 3.1.0
  packaging  = app

  dependencies {
    dependency io.xnull:http {
    }
  }

  build {
    entryFile    = src/main/x/main.x
    entryPackage = io.xnull.cli
  }
}
```

要点：聚合工程不带 `parent`（各模块坐标自写、版本统一由根仲裁表约束）；`modules` 声明顺序同时是构建顺序与插件跨模块执行顺序；升级全组版本 = 改四个模块的 `version` 与根仲裁表（改哪里一目了然，无隐式继承版本）。

## 附录 B：决策留痕

1. **段落骨架全 packaging 统一**：只需记住一种结构；差异用语义约束表达（`modules` 仅 pom、`entryFile` 仅 app），不做"换 packaging 就换一套段落"的分叉。
2. **坐标不从 parent 继承**：若允许继承，改父版本会让一批模块"悄悄改版本"，仓库里数不清谁是谁；要求每个模块明写，代价是几行冗余，收益是可审计。
3. **容器段落 + 条目段落**（`dependencies` 内嵌 `dependency` 等）：避免同名同层的歧义，也让"哪些东西可重复"在结构上可见。
4. **插件从否决转为受控定案**：保留能力，同时用九条合同锁死不确定性——精确版本、显式 goal、固定 5 阶段、只写 `target/`、禁网、禁环境读取、禁改语义、失败即崩、入锁入元数据。
5. **版本精确、范围/SNAPSHOT 全否**：可复现是硬约束（§8）。
6. **同深度冲突失败而非取第一个**：取第一个等于让声明顺序成为不可见输入，构建结果随文件行数变化。
7. **清单与配置分用两套语法**：清单要结构，配置只要平面键值；强行统一会让一方长出无意义语法。
8. **值恒字符串**：不在格式层做类型推断，类型错误统一在 schema 校验处报，可定位到段落/字段。
9. **跨服务共享只走构建期 `configuration`**：运行时跨服务读配置是隐式耦合，破坏"逐服务"原则。
10. **配置中心列为演进方向**：先不做集中配置，未来可兼容既有配置中心协议或自研外部服务；§10 已给出两条路径与硬准入条件，避免届时重新讨论方向。
11. **锁文件单份、排序固定**：多份锁会让"哪个锁生效"变成隐式问题；排序固定保证字节稳定，可直接纳入代码评审。
12. **诊断码按段位划分**（附录 C.5）：让错误从"文本描述"升级为可被工具与文档索引的稳定标识。
13. **资源单独成根、制品内加 `resources/` 前缀**：不与源码混放、不与清单/元数据争路径；前缀让"哪些是用户资源"在制品里一眼可辨（§5.6）。
14. **资源不做构建期过滤**：过滤会让同一文件的字节随清单改变，"产出的这行 HTML 是哪来的"无法按文件回答；需要按环境变化的只能是运行时配置。
15. **依赖库资源合并、冲突即失败**：不合并则库里的模板在服务里找不到；静默覆盖则"谁的模板生效"取决于依赖顺序——两者都不可接受，故取合并 + 显式失败。
16. **配置文件定位到资源根顶层**：配置文件本身就是随产物发布的资源，若允许放在模块根或资源子目录，"打包后运行时读哪份"会出现第二套路径规则。

## 附录 C：XPD 文法（规范性）

### C.1 词法

| 记号 | 定义 |
| --- | --- |
| 空白 | 空格、制表符；**换行是独立记法**（见下） |
| 换行 | 语句终止符：字段、叶子条目都到行尾结束；`{`/`}` 前后可与换行相邻 |
| 注释 | `#` 到行尾，可独占一行或在语句后 |
| 标点 | `{` `}` `=` `[` `]` `(` `)` `,` |
| 标识符 | `[A-Za-z][A-Za-z0-9-]*` |
| 键名 | 小写字母/数字/点/连字符，不以点开头或结尾（配置键，§6.3；只允许出现在 `configuration` 段） |
| 裸词 | `[A-Za-z0-9._:/\\*?\-]` 与 `${…}` 组成的连续串，不以 `"` 开头，不含空白与上述标点（`*` `?` 供资源 glob 使用，§5.6） |
| 字符串 | `"` … `"`，仅允许 `\"` 与 `\\` 两种转义，其他 `\x` 为词法错误 |
| 变量 | `${` 标识符 `}`，可出现在裸词或字符串内部 |

- UTF-8，禁止 BOM；制表符与空格等价，**缩进不具语义**。

### C.2 文法（EBNF）

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

**块体可省略**：`条目块` 末尾的 `{ … }` 可选，故 `module platform`、`exclusion org.old:legacy`、`repository central { … }` 都合法。要判断"这条写到哪结束"，只看行尾——这也是换行必须进文法的原因。

### C.3 语义约束

1. 根层只允许一个 `project` 块（清单）、一个 `lock` 块（锁文件）或一个 `plugin` 块（插件元数据）、一个 `settings` 块（凭据文件），且必须存在；根层其他段落 → 错误；
2. 段落嵌套与字段合法组合由 §3.2、§4.4、§4.7、§5.3、§5.5 规定，未列出的组合 → 错误；
3. 每个标识符的可重复性由对应表格规定，不可重复者出现两次 → 错误；
4. **名称形态**：段落名与条目名用标识符；**键名只允许出现在 `configuration` 段**（配置键），其他位置出现键名 → 错误；
5. 块头参数：`dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials` 一个参数；`plugin` 两个参数（坐标 + 版本）；`project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings`/`plugin`（元数据根）零参数；
6. **块体可省略**：`dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials`/`plugin` 允许无体（`module platform`）；`project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings` 必须带体；
7. 值一律按字符串处理；列表字段（`envOverrides`、`configKeys`、`profiles`）必须给列表，其余字段不得给列表；
8. **范围是独立值形态**：`language-version` 必须给范围（`[`/`(` 起、`]`/`)` 止，两端为版本号裸词）；其他字段出现范围或列表字段出现范围 → 错误；`[a, b]` 两端闭合时按两元素列表处理，语义由字段决定；
9. 列表与范围不得跨行；字段或条目未以换行或 `}` 收尾 → 错误；
10. 未闭合块、缺 `=` 的字段、空值 → 错误；
11. 错误必须报告：行号、列号、段落路径（如 `project/dependencies/dependency[2]/optional`）。

### C.4 错误信息格式（规范要求）

```text
xnull.project:12:3: error[XPD-204]: unknown field "optonal" in dependency
  12 |   optonal = true
     |   ^^^^^^^ 未知字段；可用字段：version, scope, optional, exclusions
```

### C.5 诊断码段位

| 段位 | 类别 |
| --- | --- |
| `XPD-0xx` | 词法（非法字符、字符串未闭合、非法转义、BOM） |
| `XPD-1xx` | 文法与结构（缺 `}`、缺 `=`、块头参数个数、空值、根层重复、列表跨行 `106`、条目未换行收尾 `107`、范围端点不为 2 `105`） |
| `XPD-2xx` | 段落与字段语义（未知段落/字段、不可重复段落重复、容器含非法条目） |
| `XPD-3xx` | 坐标与继承（缺坐标字段、坐标重复、深度超限、环、parent 非 pom） |
| `XPD-4xx` | 依赖与锁（缺版本、同深度冲突、锁不一致、摘要不符、锁定坐标多余） |
| `XPD-5xx` | 插件（phase 非法、goal 未声明、`.xplugin` 缺失/不符、越界写、网络访问） |
| `XPD-6xx` | 配置（未知键、缺必需键、键名非法、疑似密钥、profile 文件名不符） |
| `XPD-7xx` | 元数据（`.xmeta` 字段缺失/不符、工具链版本不符） |
| `XPD-8xx` | 资源与打包（资源根非法、glob 语法错、来源同路径冲突、`pom` 声明资源、配置文件位置非法、符号链接断链） |

- 每个诊断码对应固定类别与固定文案模板；新增码须落在既有段位内，跨段位新增属规范修订。
