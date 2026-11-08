# S8-15 import 包根解析设计（只读设计稿）

- 卡号：S8-15（补卡计划 `收件箱/门/S8-12-15补卡计划-v1.0.0.md`）
- owner：E2（本稿由 E1 代拟，供 E2 实施）
- 日期：2026-11-08
- 性质：**只设计，不实现**。本稿不改 `impl/**`、不新增诊断码、不改规范。
- 依据：S8 v5.2.0 §2.3/§3.7/§5.3/§5.4/附录 C.5；S1 §3.1—§3.5；S6 §2；ADR-009。

## 0. 结论

用“**包名是身份，包根是来源**”替换当前“导入路径 = 同目录相对文件路径”的模型：

1. 包根分三类：项目源码根、依赖包根（`.xlib`）、标准库包根（`xdk`）。
2. 导入路径按**最长包名前缀**解析：命中的前缀是包，其余段是符号；不再按目录逐段拼 `.x`。
3. 同一包名只允许一个来源；冲突是构建错误，不按声明顺序/依赖顺序“就近取胜”。
4. 迁移分四阶段：双轨（包优先 + 同目录回退告警）→ 严格（回退报错）→ 清理（删除回退）。`xdk.*` 与单文件默认包语义不变。

## 1. 现状与问题

### 1.1 当前实现

| 位置 | 现状 |
| --- | --- |
| `impl/internal/codegen/multifile.go:34` | `LoadUnits(entryPath)` 从入口文件目录出发，`import p1.p2` 映射为 `<入口目录>/p1/p2.x`（`multifile.go:96`）。 |
| `multifile.go:83-90` | `xdk.<pkg>` 特判为 `impl/lib/xdk/<pkg>.x`；`xdk.net.http` 只装载 `net.x`。 |
| `multifile.go:119` | 所有单元声明合并成一个 `CompilationUnit`，只有入口的 `Package` 被保留；依赖包身份在合并后丢失。 |
| `impl/internal/sema/pkg.go:94` | `AnalyzeWithDeps` 依赖调用方显式传入 `[]*Package`；`LoadUnits` 并不产出它。 |
| `pkg.go:180` | `resolveUserImport` 已按“整段命中包 / 去掉末段命中包”解析，但依赖表来自调用方，且没有包根概念。 |
| `pkg.go:196` | `samePackage` 用 `package` 声明判断同包分片，但加载阶段已把不同包拍平。 |

### 1.2 与 S8 的冲突

1. S8 §2.3 规定源码根为 `src/main/x`（可覆盖），而当前导入相对入口文件目录，目录结构被迫等于包路径。
2. S8 §5.3 的 `library` 产物是 `.xlib`，当前没有任何“依赖包根”入口。
3. S1 §3.2 的导入对象是**包名/符号**，不是文件名；当前模型无法表达“文件位置与包名解耦”。
4. 当前 `LoadUnits` 合并后丢失包边界，`sema` 的跨包可见性、别名冲突、环检测只能靠调用方补依赖表，容易与 `build` 路径不一致。

## 2. 目标模型与不变量

### 2.1 术语

- **包名**：`package` 声明中的点分标识符序列；包的**唯一身份**。
- **包根**：一个物理目录 + 其下 `package` 声明的索引；包根不要求目录层级等于包名。
- **包单元**：同一包根内声明同一包名的全部 `.x` 文件；它们互为同包分片（S1 §3.4）。
- **依赖包根**：由已解析依赖（`.xlib`）提供的只读包根。
- **标准库包根**：`xdk` 命名空间对应的只读包根。

### 2.2 不变量

1. **包名唯一**：一次编译内，一个包名只能来自一个包根。项目根与依赖根、两个依赖根之间出现同名包 → 构建错误。
2. **`xdk` 独占**：用户包名不得以 `xdk` 开头（S1 §3.1）；标准库根不参与用户包名冲突。
3. **默认包不可导入**：无 `package` 的文件只用于单文件程序/入口；其他包导入默认包 → `RES-111`。
4. **解析确定性**：同一清单 + 同一锁 + 同一源码根，解析结果与文件系统枚举顺序、依赖声明顺序无关。
5. **包名与目录解耦**：目录只影响包根的物理位置，不参与包身份；包名以 `package` 声明为准。
6. **导入不执行代码**：建索引只读文件头，不求值、不初始化（S1 §3.2）。

## 3. 包根设计

### 3.1 三类包根

| 类型 | 来源 | 可见范围 | 优先级 |
| --- | --- | --- | --- |
| `project` | 当前模块 `build.sourceRoot`（缺省 `src/main/x`）；测试编译再加 `build.testRoot` | 当前模块 | 唯一，不与其他根同名 |
| `dependency` | S8-13 解析出的 `.xlib` 包根，按 GAV 去重 | `compile` / `provided`（测试编译另加 `test`） | 平级；同名即冲突 |
| `stdlib` | 工具链 XDK 根（源码树为 `impl/lib/xdk`，安装态为工具链自带目录） | 全局，仅 `xdk.*` | 独占 `xdk` 前缀 |

- 作用域按 S8 §3.7：编译可见 = `compile` + `provided`；测试编译再加 `test`；`runtime` 不进入编译类路径。
- reactor 内其他模块**不直接暴露源码根**：模块间依赖走 GAV/`.xlib`，避免跨模块源码泄漏与构建顺序耦合。
- `testRoot` 只在测试编译加入；生产编译若索引到测试包 → `XPD-411`。主根与测试根声明同名包也视为冲突（不静默覆盖）。

### 3.2 包索引

每个包根构建一个只读索引：

```text
PackageEntry {
    Name      []string   // package 声明
    Root      RootID     // project / GAV / xdk
    Files     []string   // 相对包根的 .x 路径（确定性排序）
    Symbols   map[string]bool // 公开顶层符号（sema.NewPackage 口径）
}
```

建索引规则：

1. 递归扫描包根下 `.x`，跳过 `target/`、隐藏目录、符号链接断链（S8 §5.6 同款）。
2. 只解析文件头的 `package` 与顶层公开符号；不运行语义分析。
3. 同一包根内同一包名多文件 → 合并为一个 `PackageEntry`（同包分片）。
4. 同一包根内同文件重复声明/空段 → 沿用 `SYN-101`。
5. 索引缓存键 = `(根路径, 文件列表摘要)`；缓存不改变可见语义。

### 3.3 `.xlib` 合同（与 S8-13 的接口）

本设计不定义 `.xlib` 容器格式，只冻结解析器需要的最小接口。S8-13 交付时必须提供：

```text
ResolvedLibrary {
    GroupId, ArtifactId, Version string
    Scope                        string   // compile/runtime/test/provided
    RootDir                      string   // 解包后的只读包根
    Packages                     []PackageEntry
}
```

强制要求：

1. `.xlib` 内每个 `.x` 必须有 `package` 声明；默认包文件 → 构建失败。
2. 包名不得以 `xdk` 开头（用户库不得占用标准库命名空间）。
3. 索引中登记的文件必须存在；缺文件 → `XPD-412`。
4. 同一 `.xlib` 内同名包按同包分片合并；跨 `.xlib` 同名包 → `XPD-411`。
5. `.xlib` 不得包含 `target/`、绝对路径、`..` 段（解包安全）。

## 4. 解析算法

### 4.1 输入

```text
Resolve(importerPkg []string, importPath []string) (Resolution, []diag.Diagnostic)
```

上下文包含：三类包根索引、当前模块坐标、入口包名、是否测试编译、是否严格模式。

### 4.2 标准库优先

1. `importPath[0] == "xdk"`：
   - 取 `pkg = importPath[1]`，在标准库根找 `xdk.<pkg>`；
   - 若存在已登记子包（如 `xdk.net.http`），按**最长标准库包名**匹配（`xdk.net.http` 优先于 `xdk.net`）；
   - 其余段为符号；多余段 → `RES-106`；
   - 用户包名以 `xdk` 开头在解析前已由 S1 §3.1 拒绝。
2. 标准库根缺失对应 `.x` → `RES-106`（不是 XPD；这是语言导入错误）。

### 4.3 用户包：最长前缀匹配

对 `import p1.p2...pn`：

```text
for k = n down to 1:
    key = join(p1..pk, ".")
    if key exists in any user root:
        package = key
        symbol  = join(p(k+1)..pn, ".")   // 0 或 1 段
        break
if no match: fail
```

- `symbol` 为空 → 包导入（全部公开顶层符号进入文件作用域）。
- `symbol` 恰 1 段 → 符号导入。
- `symbol` ≥ 2 段 → `RES-106`（S1 只允许 `P.S`）。
- 候选包名若同时命中多个包根 → `XPD-411`，不按顺序选第一个。
- 命中后校验符号是否在 `PackageEntry.Symbols`；不在 → `RES-106`。
- `as` 别名规则保持 S1 §3.2/§3.3：只在简单名冲突时允许；包导入禁止 `as`。

### 4.4 完全限定名

表达式/类型位置的 `com.acme.common.helper` 按同一索引做最长包名前缀解析：

1. 若首段是当前作用域内的局部名/顶层名 → 按成员访问处理（S1 §3.3 第 1/2 级）。
2. 否则用包索引匹配最长包名，剩余段作为成员链。
3. 包名命中但符号不存在 → `RES-106`；包名不存在且不是值 → 维持现有“未定义名称”诊断。
4. 该规则要求 sema 在 `resolveUserImport` 之外增加 `lookupQualified`；当前 sema 只处理 import，不处理表达式里的完全限定名，这是 S8-15 的必改点。

### 4.5 环检测

- 图节点是**包名**，不是文件路径；边是包内所有文件的 `import`。
- 环检测在索引完成后、语义分析前执行；`xdk.*` 不参与用户包环。
- 环诊断保持 `RES-108`，消息列出包名链。

## 5. 命名与冲突规则

### 5.1 包身份冲突

| 场景 | 结果 |
| --- | --- |
| 同一包根内同名包、多文件 | 允许；同包分片 |
| 项目根 vs 依赖根同名包 | 错误 `XPD-411`（不遮蔽） |
| 两个依赖同名包 | 错误 `XPD-411`（点名两个 GAV） |
| 依赖包名以 `xdk` 开头 | 错误 `XPD-411` |
| 主根 vs 测试根同名包 | 错误（测试不得覆盖生产包） |
| 同一 GAV 重复出现 | 依赖解析去重，非包冲突 |

### 5.2 符号冲突

沿用 S1 §3.3，不新增规则：

- 当前包顶层声明遮蔽同名导入。
- 两个导入提供同一简单名且未消歧 → `RES-104`；对新导入用 `as` 或改用完全限定名。
- 包导入不能给单个符号建别名；需要时改 `import P.S as A`。
- `private` / `protected` 顶层符号不进包索引。
- 两个包末段同名不构成冲突；冲突只在简单符号层判定。

### 5.3 与预定义类型/关键字的冲突

- 导入别名不得与关键字、预定义类型名、当前文件顶层声明冲突（S1 §3.3）。
- 包名本身不绑定命名空间，因此 `com.acme.common` 与 `com.other.common` 可并存。

## 6. 与 sema / codegen 的接口

### 6.1 新入口

```text
LoadProject(ctx ProjectContext) (*Program, []diag.Diagnostic)

Program {
    Entry     *xfront.CompilationUnit   // 入口包单元（含同包分片）
    Packages  map[string]*PackageUnit   // 全部参与编译的包
    Order     []string                  // 依赖优先的确定性顺序
}
```

- `PackageUnit` 保留 `Name`、`Files`、`Unit`（同包分片合并后的编译单元）、`Imports`。
- `LoadUnits(entryPath)` 保留为过渡 API，内部可委托 `LoadProject` 的“单文件默认包”模式。

### 6.2 与现有调用方

| 调用方 | 迁移方式 |
| --- | --- |
| `impl/internal/cli` build 路径 | 有 `xnull.project` 时用 `LoadProject`；无清单的 `check single.x` 保持 `LoadUnits` |
| `impl/internal/codegen` | 新增 `EmitProgram` 适配器：按 `Order` 合并声明后走现有 `EmitC`，避免一次性重写 codegen |
| `impl/internal/sema` | `AnalyzeWithDeps` 保持不变；由 `LoadProject` 产出 `[]*Package`，并新增 `lookupQualified` |
| `impl/internal/interp` | 同 codegen，按 `Order` 合并后运行；入口包必须是默认包或 `entryPackage` |
| `cmd/xnpt` | 不受影响（单表达式） |

### 6.3 入口校验

S8 §5.4：有 `entryPackage` 时，入口文件声明的包必须等于 `entryPackage`；否则 `XPD-4xx`（建议 `XPD-413`，需规范登记）。无 `entryPackage` 时保持现状。

## 7. 迁移路径

### 阶段 0（当前）

- `LoadUnits` 相对路径模型是唯一行为；`xdk.*` 特判；无依赖包根。

### 阶段 1：双轨（S8-15 首版）

- `xnull build` 有清单时走 `LoadProject`：包优先；
- 未命中包索引时回退同目录 `.x`，并给 `RES-112` 警告（提案码，见 §8）；
- `xnull check file.x`、`cmd/xnpt` 保持旧行为；
- `xdk.*` 解析路径不变（仅把根定位抽成 `stdlib` 根）。

迁移规则：旧树中 `import a` 对应 `a.x`，给 `a.x` 加 `package a` 即可；`import lib.text` 对应 `lib/text.x`，加 `package lib.text`。包名与旧导入路径一致，不需要移动文件。

### 阶段 2：严格

- `--strict-import-roots`（或清单 `build.strictImportRoots = true`）下回退直接报错；
- 全仓 `examples/`、`tests/`、`difftest/` 完成 `package` 声明迁移；
- 仍保留回退代码但默认关闭。

### 阶段 3：清理

- 删除同目录回退与 `RES-112`；`LoadUnits` 只保留“单文件默认包”语义；
- S8 重新签发 PROJ-01/02 导入面。

### 兼容矩阵

| 场景 | 阶段 1 | 阶段 2 | 阶段 3 |
| --- | --- | --- | --- |
| `xdk.*` | 不变 | 不变 | 不变 |
| 单文件默认包 | 不变 | 不变 | 不变 |
| 旧相对导入（同目录 `.x`） | 警告可用 | 默认可用，严格模式报错 | 报错 |
| 包名导入（项目根） | 可用 | 可用 | 唯一方式 |
| 依赖 `.xlib` 包 | 可用 | 可用 | 唯一方式 |

## 8. 诊断码

语言导入错误沿用 S1 §3.5 的 `RES-1xx`；工程/包根错误建议落在 S8 `XPD-4xx`（依赖与锁段位）。**新增码需 S8 版本化登记，本稿只提案，不直接落码。**

| 场景 | 建议码 | 段位 | 说明 |
| --- | --- | --- | --- |
| 包/符号不存在 | `RES-106` | S1 | 已有 |
| 未消歧简单名 | `RES-104` | S1 | 已有 |
| 别名冲突/非冲突别名 | `RES-103` / `RES-107` | S1 | 已有 |
| 包导入环 | `RES-108` | S1 | 已有 |
| 默认包被导入 | `RES-111` | S1 | 已有 |
| 过渡期相对导入 | `RES-112`（提案） | S1 | 仅阶段 1/2 |
| 依赖未声明/未解析 | `XPD-4xx` 现有码 | S8 | 复用依赖图诊断 |
| 同名包多来源 | `XPD-411`（提案） | S8-4xx | 点名两个 GAV/根 |
| `.xlib` 索引缺文件/非法 | `XPD-412`（提案） | S8-4xx | 构建期 |
| `entryPackage` 不匹配 | `XPD-413`（提案） | S8-4xx | 入口校验 |
| 测试根覆盖生产包 | `XPD-411` | S8-4xx | 复用同名冲突 |

## 9. 验收用例（S8-15 实施卡）

### 正例

1. 项目根 `src/main/x/com/acme/common/util.x` 声明 `package com.acme.common`；`src/main/x/app/main.x` `import com.acme.common.Util`，解析到项目根。
2. 同一包名拆两个文件（`a.x`/`b.x` 均 `package com.acme.common`），符号合并可见。
3. 依赖 `.xlib` 提供 `com.acme.common`，另一工程 `import com.acme.common.Util` 成功。
4. `import xdk.net.http` 仍解析到标准库子包。
5. `import com.acme.common.Util as U` 在冲突场景通过；非冲突场景报 `RES-107`。
6. 表达式完全限定名 `com.acme.common.helper(1)` 解析成功。

### 负例

1. 两个依赖都导出 `com.example.common` → `XPD-411`，消息含两个 GAV。
2. 声明依赖但 `.xlib` 缺失/无包索引 → `XPD-412`。
3. 依赖中 `package xdk.foo` → 构建失败。
4. 默认包被 `import` → `RES-111`。
5. 包存在但符号不存在 → `RES-106`。
6. 两个包同名符号未消歧 → `RES-104`。
7. 包导入环（A→B→A）→ `RES-108`，链为包名。
8. 严格模式下旧同目录导入 → 报错；阶段 1 仅警告 `RES-112`。
9. `entryPackage = com.acme.app` 但入口文件声明 `com.acme.other` → `XPD-413`。
10. 主根与测试根同名包 → `XPD-411`。

### 确定性

- 打乱依赖声明顺序、文件系统枚举顺序、并发索引顺序，解析结果与诊断顺序不变（DET-01 口径）。

## 10. 风险与开放点

1. **S8-13 未落地**：`.xlib` 容器与包索引格式未冻结。本设计要求先冻结 `ResolvedLibrary` 接口，再由 E6 实现；否则 E2 会被格式细节阻塞。
2. **sema 完全限定名缺口**：当前 `resolveUserImport` 只覆盖 import，不覆盖表达式里的点分名称；S8-15 必须同时补 `lookupQualified`，否则“包根解析”只完成一半。
3. **同包分片合并**：当前 `LoadUnits` 把所有包拍平；新模型要保留 `PackageUnit`，codegen 侧需要 `EmitProgram` 适配器，避免一次性改发射器。
4. **旧测试迁移量**：`impl/internal/codegen/multifile_test.go:34-119`、`examples/multi/*`、`tests/**` 均使用相对导入；迁移规则是“给文件补 `package <旧导入路径>`”，不改目录。
5. **测试根隔离**：测试编译把 `testRoot` 加入索引，生产编译不得看到；需要在索引层按编译目标过滤，而不是在 sema 层事后过滤。
6. **性能**：包索引只读文件头；缓存按根+摘要键控；不得因索引引入全量解析。
7. **规范版本**：新增 `RES-112` / `XPD-411..413` 必须走 S1/S8 新版本 + 新哈希，不能在本卡直接改定版文件。

## 11. 实施顺序建议（给 E2）

1. 冻结 `ProjectContext` / `ResolvedLibrary` / `PackageRoot` 内部接口（仅文档 + Go 类型，不接入 CLI）。
2. 实现包索引与最长前缀解析，先接 `LoadProject`，保持 `LoadUnits` 行为。
3. 接 `sema.lookupQualified` 与 `AnalyzeWithDeps` 的依赖表。
4. 迁移 `examples/`、`tests/` 的 `package` 声明，开启双轨回退告警。
5. 打开严格模式，补负例；最后删除回退。
