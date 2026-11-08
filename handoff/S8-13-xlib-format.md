# `.xlib` 产物格式设计（S8-13，草案 v0.1）

- 日期：2026-11-08
- 性质：**只设计，不实现**
- 依据：S8 §4.4（`xnull.lock`）、§4.7（仓库布局）、§5.3（产物与 `.xmeta`）、
  §5.6（资源）、§9（PROJ-05/09/11）；S9 模块 06 §3
- 结论：`.xlib` 是 **library 的确定性源码包**，不是预编译库；容器用
  “ZIP + Store（不压缩）”冻结字节；本地仓库按 GAV 三级目录安装；
  锁文件以 `.xlib` 全文 SHA-256 引用。

## 一、目标与非目标

### 目标

1. 一个 `.xlib` 自包含：源码包、资源、绑定声明、清单、元数据、依赖声明、文件哈希。
2. 可复现：同一输入两次构建得到**逐字节相同**的 `.xlib`；锁 `sha256` 稳定。
3. 可审计：解包即可看到源码/资源/依赖/哈希，不依赖外部数据库。
4. 可安装：本地仓库按 `groupId/artifactId/version/` 放置，离线（`XNULL_REPO`）可用。
5. 与 S8 现有 `.xmeta`、资源 `resources/` 前缀、锁 `sha256` 模型兼容。

### 非目标

- 不定义预编译对象/字节码格式；XNull 在消费侧从源码编译。
- 不做签名/加密（S8 §4.7：签名验证非承诺）。
- 不做远程 `deploy`（S8 §5.1 否决）。
- 不定义插件包格式（`.xplugin` 独立）。
- 不定义 starter 的代码包；starter 永远不产 `.xlib`。

## 二、容器格式

### 2.1 选择：确定性 ZIP（Store）

| 项 | 规定 |
| --- | --- |
| 容器 | ZIP（`PK\x03\x04`），只使用 `Store` 方法（method=0，不压缩） |
| 压缩 | 不压缩；避免 zlib 版本差异导致字节漂移 |
| 条目顺序 | 按 ZIP 条目路径的**字节序升序**（`/` 分隔，大小写敏感） |
| 时间戳 | 固定 DOS 时间 `1980-01-01 00:00:00` |
| 权限 | 普通文件 `0644`；不写目录条目；不写可执行位 |
| 额外字段 | 禁止 ZIP extra field、comment、数据描述符 |
| 路径 | 只用 `/`；禁止绝对路径、`..`、空段、反斜杠、NUL |
| 符号链接 | 禁止；全部按普通文件存储 |
| 重复条目 | 禁止（同名两次即失败） |
| 大小 | 1.x 不设规范上限（S8 §10 口径）；由工具链资源策略决定 |

理由：Go 标准库 `archive/zip` 可直接生成/读取；Store 模式在固定条目顺序、
固定时间戳、固定权限下可逐字节复现；随机访问元数据方便安装前校验。

### 2.2 归档根布局

```text
xlib-archive/
├── xnull.project                  # 规范化 library 清单（XPD）
├── META-INF/
│   ├── xmeta.xpd                  # 产物元数据（含 xlibVersion/dependencies）
│   ├── hashes.xpd                 # 每个 payload 文件 path/size/sha256
│   └── xlib-format.xpd            # 容器版本/规范版本（可选，见 §2.3）
├── src/main/x/**.x                # 源码包（不含测试源码）
├── src/main/resources/**          # library 自身资源（保持相对路径）
├── bindings/**.xfb                # FFI 声明（若有）
└── native/<platform>/**           # 原生库（若有；见 §2.4）
```

- **源码包**：`src/main/x/**` 只收 `.x` 源码；`src/test/x/**` 不进 `.xlib`。
- **资源**：`src/main/resources/**` 保持资源根相对路径；消费侧 app 打包时
  按 S8 §5.6 合并到制品 `resources/` 前缀。
- **清单**：`xnull.project` 是构建时生效后的 library 清单（继承已展开、
  变量已替换、profile 已生效），但**去掉** `target/` 路径与 `build.entry*`
  （library 不得声明入口，S8 §5.4）。
- **绑定**：`bindings/**.xfb` 原样收录；消费侧编译时合并/校验。
- **原生库**：`native/<platform>/**` 仅当清单声明 `link.libraries` 时出现；
  `system=true` 的库不入包（由宿主提供）。1.x 未冻结跨平台原生 ABI，
  该目录为**保留区**；不声明即不出现。
- **禁止**：`target/`、`.cache/`、`.git/`、签名文件、构建日志、凭据文件。

### 2.3 格式版本

`META-INF/xlib-format.xpd`（可选但推荐）：

```xpd
xlibFormat {
  version    = 1
  container  = zip-store
  hashAlg    = sha256
}
```

- 消费侧遇到 `version > 1` → 失败（不猜测兼容）。
- 若省略该文件，按 `version = 1` 处理；但仍校验 `xmeta.xpd.xlibVersion`。

## 三、元数据与哈希

### 3.1 `META-INF/xmeta.xpd`

```xpd
xmeta {
  xlibVersion       = 1
  groupId           = io.xnull
  artifactId        = http
  version           = 3.1.0
  packaging         = library
  platform          = macos-amd64
  xdkVersion        = 1.1.0
  languageVersion   = [3.3, 4.0)
  toolchainVersion  = 0.1.0
  profiles          = [prod]
  plugins           = []
  lockSha256        = <64 位小写十六进制>
  inputs            = <64 位小写十六进制>

  dependencies {
    dependency io.xnull:core {
    }
    dependency io.xnull:codec {
    }
  }
}
```

- **必需字段**：`xlibVersion`/坐标/`packaging=library`/`platform`/
  `xdkVersion`/`languageVersion`/`toolchainVersion`/`profiles`/`plugins`/
  `lockSha256`/`inputs`。
- **依赖**：只列**声明坐标**（groupId/artifactId），不写版本；版本由
  消费方 `xnull.lock` 仲裁（S8 §4.2/§4.4）。这与 library 清单“不带版本”
  的规则一致。
- `lockSha256`：构建该 library 时所用 `xnull.lock` 的内容摘要；无锁时写全 0
  并记录 `lockPresent=false`（可选字段）。
- `inputs`：清单链、源码根、锁文件、工具链版本、平台、profile 集合的汇总摘要
  （S8 §5.3/§8）；用于可复现审计。
- **不写**完整锁文件：锁是 app 工程级唯一一份（S8 §4.4），`.xlib` 只带
  依赖坐标与 `lockSha256`，避免"包内锁"与工程锁双源。

### 3.2 `META-INF/hashes.xpd`

```xpd
hashes {
  algorithm = sha256
  file "xnull.project" {
    size = 512
    sha256 = <64 位小写十六进制>
  }
  file "src/main/x/http.x" {
    size = 2048
    sha256 = <64 位小写十六进制>
  }
}
```

规则：
- 覆盖除 `META-INF/hashes.xpd` 自身外的全部 payload 文件（含 `xmeta.xpd`、
  `bindings/**`、资源）。
- 条目按路径字节序升序；`size` 为原始字节数；`sha256` 小写十六进制。
- 读取时逐文件校验；任一不符 → 失败（不自动修复）。

### 3.3 制品哈希（锁引用）

- **`artifactSha256` = SHA-256(完整 `.xlib` 字节)**，唯一外部引用值。
- 本地仓库同时写 `<artifactId>-<version>.sha256`（64 位小写十六进制 + 换行）。
- 锁文件 `entry.sha256` 使用该值（S8 §4.4）。
- 哈希计算在安装前完成；安装后再次读取校验，防止写盘损坏。
- `.xmeta` 不包含自身归档哈希（避免自引用）；归档哈希只存在于锁/`.sha256`。

## 四、与 app / library / starter 的关系

| packaging | 产物 | 是否 `.xlib` | 本地仓库安装 | 依赖消费方式 |
| --- | --- | --- | --- | --- |
| `library` | `.xlib` + `.xmeta` | **是** | `.xlib`/`.xmeta`/`xnull.project`/`.sha256` | 消费侧从源码编译；资源合并 |
| `app` | 可执行体 + `.xmeta` | 否 | 可选安装 `.xmeta`/`.sha256` 作审计；不作为依赖 | 最终产物，不被依赖 |
| `starter` | 清单 + `.xmeta` | **否** | `xnull.project`/`.xmeta`/`.sha256` | 依赖传递；自身无代码、资源不合并给消费者（S8 §5.6） |
| `pom` | 清单 + `.xmeta` | 否 | `xnull.project`/`.xmeta` | 父/聚合定位；不作为代码依赖 |

- **app**：依赖 `.xlib` 与 starter；构建时把 library 源码纳入编译闭包，
  资源按 §5.6 合并；app 自身不产 `.xlib`。
- **library**：可再依赖其他 library；`.xlib` 的 `dependencies` 只列坐标，
  版本由 app 锁统一仲裁；避免库内自带版本导致双源。
- **starter**：只有清单/元数据；其依赖在 app 构建时传递展开；资源**不合并**
  给使用者（S8 §5.6）。因此 starter 不能用 `.xlib` 伪装“空库”。
- **pom**：只提供 parent/聚合语义；不参与代码编译。

## 五、本地仓库目录结构

### 5.1 根目录

- 默认：`~/.xnull/repository/`
- 环境变量：`XNULL_REPO` 指向的目录**直接作为仓库根**；设置后视为离线唯一来源
  （S8 §4.7：缺件/哈希不符 → 失败，不回落网络）。
- 仓库根下不写全局索引数据库；坐标到路径是纯函数映射，便于审计/复制。

### 5.2 路径

```text
<repository-root>/
└── <groupId 点转斜杠>/
    └── <artifactId>/
        └── <version>/
            ├── <artifactId>-<version>.xlib
            ├── <artifactId>-<version>.xmeta
            ├── xnull.project
            └── <artifactId>-<version>.sha256
```

示例（`io.xnull:http:3.1.0`）：

```text
~/.xnull/repository/io/xnull/http/3.1.0/
├── http-3.1.0.xlib
├── http-3.1.0.xmeta
├── xnull.project
└── http-3.1.0.sha256
```

- groupId 每段只允许 `[a-z0-9-]`（沿用坐标规则）；artifactId/version 原样。
- 目录名不含坐标分隔符；不做 URL 编码。
- `.xmeta` 是 S8 §5.3 字段的**外部副本**；`xnull.project` 是归档内清单的
  同字节副本（便于父定位与人工审计）；`.sha256` 是归档哈希。
- starter/pom 安装不含 `.xlib`，目录内只有 `xnull.project`/`.xmeta`/`.sha256`。

### 5.3 安装原子性

1. 在目标目录同级创建临时目录（`.<artifact>-<version>.tmp-<pid>`）。
2. 写入四件产物 + 计算/校验哈希。
3. `fsync`（实现允许）后 `rename` 原子替换目标目录。
4. 已存在同版本：
   - 哈希相同 → 幂等成功（不重写）；
   - 哈希不同 → **失败**（同版本不可变；不静默覆盖）。
5. 失败清理临时目录；不留下半安装状态。
6. 安装只写仓库根；不写工程 `target/` 以外位置。

## 六、锁文件如何引用

```xpd
lock {
  version = 1

  entry io.xnull:http 3.1.0 {
    kind       = dependency
    repository = local          # 或 central 等逻辑仓库 id
    sha256     = <http-3.1.0.xlib 的 SHA-256>
  }
}
```

- `sha256` 只指向 **`.xlib` 全文哈希**；不写内部文件哈希（内部由 `hashes.xpd`
  自校验）。
- `repository` 是**逻辑仓库 id**，不是路径：
  - 本地安装写 `local`（保留 id）；
  - 远程解析写远程仓库 id（如 `central`）。
- 解析顺序（S8 §4.7 + 本地缓存）：
  1. `XNULL_REPO` 设置 → 只查该根；坐标存在且哈希匹配 → 用；否则失败。
  2. 未设置 → 先查 `~/.xnull/repository` 同坐标；哈希匹配 → 用；
     不匹配/缺失 → 按 `repository` 声明查远程；远程命中后校验锁哈希。
- 锁是唯一版本权威：`.xlib` 的 `dependencies` 不带版本；app 构建按锁逐坐标
  锁定，库内声明只提供坐标与传递关系。
- `xnull lock` 生成/更新时：安装 `.xlib` 计算 `sha256` → 写入/更新锁；
  `--update-lock` 是唯一重生成入口（S8 §4.4）。
- 锁与清单不一致 → 失败；锁内坐标在清单不存在 → 失败。

## 七、校验与安全

读取 `.xlib` 时按顺序失败（任一失败即拒绝）：

1. ZIP 结构合法；条目顺序/时间戳/权限符合 §2.1（不满足视为非规范产物）。
2. 路径合法：无绝对路径、`..`、空段、反斜杠、NUL；无符号链接/重复条目。
3. `META-INF/xlib-format.xpd` 的 `version` 为 1；`xmeta.xlibVersion` 为 1。
4. `xmeta` 必需字段齐全；`packaging=library`；坐标与仓库路径一致。
5. `hashes.xpd` 覆盖全部 payload 文件；逐文件 size/sha256 匹配。
6. 归档全文 SHA-256 与锁/`.sha256` 一致。
7. 依赖坐标合法；不要求 `.xlib` 自带版本。
8. 不允许额外顶层文件（除 §2.2 白名单）；未知顶层目录 → 失败，避免隐式载荷。

安全边界：
- 不执行包内脚本/插件；`.xlib` 是数据。
- 不信任包内路径；解包只写安装临时目录。
- 签名/加密非承诺；哈希只保证完整性，不保证来源可信。

## 八、可复现规则（PROJ-09）

同一清单链 + 锁 + 工具链 + 平台 + profile 集合 ⇒ 同一 `.xlib` 字节：

- 归档条目顺序固定、时间戳固定、权限固定、Store 不压缩；
- `xmeta` 字段顺序固定（XPD 字段按规范顺序；列表升序）；
- `hashes.xpd` 路径升序；数字十进制无前导零；
- `inputs`/`lockSha256` 为确定性摘要；
- 不写入构建时间、主机名、用户、临时路径；
- 构建两次比对 `artifactSha256`，不一致 → 失败（PROJ-09 验收）。

## 九、版本与兼容

| 项 | v1 |
| --- | --- |
| `.xlib` 容器 | ZIP Store，`xlibFormat.version=1` |
| `xmeta` | `xlibVersion=1`，S8 §5.3 字段 |
| 锁 | `lock.version=1`，`sha256` 为归档哈希 |
| 工具链 | 更高 `xlibVersion` → 拒绝；同版本字段只增不改语义 |

格式变更走主版本；不得在同一 `xlibVersion` 下改变字段语义或归档字节规则。

## 十、实现落点（后续 S8-13，不在本设计实现）

1. `impl/internal/artifact/xlib`（建议）：写/读/校验/哈希。
2. `impl/internal/cli`：`package` 生成 `.xlib` + `.xmeta`；`install` 写本地仓库。
3. `impl/internal/lock`：`sha256` 取 `.xlib` 全文；本地优先解析。
4. 测试：
   - 两次构建字节一致（sha256）；
   - 归档路径/顺序/时间戳/权限；
   - 缺哈希/坏哈希/重复条目/路径穿越/未知版本拒绝；
   - 本地仓库安装原子性与同版本不同哈希失败；
   - `XNULL_REPO` 离线解析与锁哈希不匹配失败。

## 十一、待董事会/规范确认项

1. 本地仓库默认根 `~/.xnull/repository` 是否为最终路径（当前 S8 只写
   `XNULL_REPO` 与 `~/.xnull/settings.xpd`，未冻结仓库默认根）。
2. `native/<platform>/**` 是否进入 1.x `.xlib`（当前 S8 未定义原生库打包）。
3. 本地仓库逻辑 id 是否固定为 `local`（锁 `repository` 字段语义）。
4. starter/pom 的本地仓库文件集是否与 §5.2 三件一致（本设计按三件）。
