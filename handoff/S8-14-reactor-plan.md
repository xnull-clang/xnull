# S8-14 reactor 聚合构建设计（草案 v0.1）

- 日期：2026-11-08
- 性质：**只设计，不实现**
- 依据：S8 §2.1（packaging）、§3.3（继承）、§3.10（configuration）、§4.4（锁）、
  §5.1（生命周期）、§5.6（资源）、§9（PROJ-02/03/04/05/09）、附录 A.2/A.3；
  S9 模块 06（构建驱动）
- 结论：reactor 以聚合根 `pom` 的 `modules` 声明顺序为构建顺序；依赖图用于
  **拓扑校验**（不静默重排）；library/starter/pom 在依赖满足后构建，app 最后；
  install 为全 reactor 原子事务。

## 一、目标与非目标

### 目标

1. 从聚合根递归发现 `modules`，解析每个模块的清单/继承/GAV/packaging/依赖。
2. 建立模块图（包含、parent、依赖、starter 传递），做拓扑校验与环检测。
3. 按 S8 A.3 的“`modules` 声明顺序即构建顺序”执行；依赖不满足即失败，
   不偷偷重排。
4. library→app、starter→app 的构建顺序由依赖边保证；app 不先于其依赖。
5. 聚合构建的 package/install 有明确的失败边界与回滚规则。
6. 与单份 `xnull.lock`、本地仓库、`XNULL_REPO` 离线模式一致。

### 非目标

- 不实现并行构建（1.x 顺序执行；确定性优先）。
- 不实现远程 `deploy`（S8 §5.1 否决）。
- 不定义插件执行器本体（只规定跨模块执行顺序）。
- 不改变 `.xmeta`/`.xlib`/锁字段；沿用 S8-13 设计与 S8 §4.4。

## 二、输入与模块模型

### 2.1 聚合根

- 根 `xnull.project` 必须 `packaging = pom` 且可含非空 `modules`（S8 §2.1/§3.2）。
- 根目录是 **reactor 根**：`xnull.lock` 唯一位置；所有模块共享。
- 模块路径为相对根/父聚合目录的路径；每个模块目录必须有 `xnull.project`。
- 模块 GAV 必须显式书写（S8 §2.2：坐标不从 parent 继承）。

### 2.2 模块节点

```text
Module {
  path        // 规范化绝对路径（相对根；禁止逃逸）
  relPath     // 相对 reactor 根的 / 分隔路径
  groupId, artifactId, version, packaging
  parent      // 可空；reactor 内 parent 指向另一节点
  modules     // 子模块声明（仅 pom）
  deps        // 依赖坐标（groupId:artifactId，版本由仲裁/锁）
  plugins     // 插件坐标 + goal + phase
}
```

- `packaging` 四类：`pom` / `library` / `starter` / `app`（S8 §2.1）。
- `modules` 非空仅 `pom`；非 `pom` 出现 `modules` → 失败。
- `app` 不得作依赖、不得作 parent、不得作 starter 的传递依赖。
- `starter` 不得有 `src/` 源码目录；其 `dependencies` 一律传递。
- `pom` 不产代码；`starter` 只产清单/元数据；`library` 产 `.xlib`；`app` 产可执行体。

### 2.3 模块发现与扁平化

从 reactor 根开始按 `modules` **声明顺序**深度优先展开：

```text
flatten(aggregator):
  for module in aggregator.modules (声明顺序):
    visit(module)                  # 先访问模块自身
    if module.packaging == pom && module.modules 非空:
      flatten(module)              # 再递归其子模块
```

- 得到 `order[i]`；同一模块只出现一次；重复路径/重复坐标 → 失败。
- 嵌套聚合器自身（pom）排在其子模块之前；子模块声明顺序保持。
- 模块路径必须位于 reactor 根之内（规范化后检查前缀；禁止 `..` 逃逸）。
- 模块目录与根目录各自只允许一份 `xnull.project`；不跟随符号链接目录（或按
  S8 §5.6 的符号链接规则统一处理，首版建议拒绝目录链接）。

## 三、模块图与拓扑校验

### 3.1 节点与边

| 边类型 | 方向 | 含义 |
| --- | --- | --- |
| 包含 | 聚合器 → 子模块 | 仅用于扁平化，不单独作为构建依赖 |
| parent | parent → child | 子模块继承父配置；父必须先于子解析/构建 |
| 依赖 | dependency → consumer | 被依赖模块先构建 |
| starter 传递 | starter 的依赖 → starter；starter → 依赖它的 app/模块 | 依赖先于 starter，starter 先于消费者 |
| 插件跨模块 | 按 `modules` 声明顺序 | 插件在同一阶段按声明顺序执行（S8 A.3） |

- 依赖边以 `groupId:artifactId` 解析：
  - 若坐标在 reactor 内：必须与 reactor 模块的 `version` 一致；不一致 →
    失败（XPD-223 建议）。
  - 若不在 reactor 内：走锁/本地仓库/远程解析，不参与 reactor 拓扑。
- starter 的 `dependencies` 展开为传递边；starter 本身无源码，构建阶段只做
  validate/package 元数据。
- app 不提供依赖边入边（不能被依赖）；若清单出现 app 作依赖 → 失败。

### 3.2 拓扑校验（不重排）

S8 附录 A.3 明确：`modules` 声明顺序同时是构建顺序与插件跨模块执行顺序。
因此 reactor **不按拓扑排序重排**，而是：

```text
pos[node] = flatten 顺序
for each edge (from -> to):
    if pos[from] >= pos[to]:
        fail "模块声明顺序不是拓扑序：from 必须在 to 之前"
```

- 依赖图有环 → 失败，输出环路径（A → B → A）。
- parent 链有环/自父/深度 > 8 → 失败（S8 §3.3）。
- 缺失 parent/非 pom parent → 失败。
- 同坐标重复/同路径重复 → 失败。
- 若声明顺序不满足依赖，**不自动重排**：修复清单顺序或依赖关系；这保证
  构建顺序可审计、与插件顺序一致。

### 3.3 拓扑校验示例

```text
modules { core, codec, http, cli }   # 声明顺序
deps:    http -> core, http -> codec, cli -> http
```

- `core/codec` 先于 `http`，`http` 先于 `cli`：声明顺序合法。
- 若声明为 `{ http, core, codec, cli }`：`core` 在 `http` 之后 → 失败
  （提示把 core/codec 移到 http 之前），不自动重排。

## 四、构建顺序与阶段

### 4.1 阶段

reactor 构建按 `flatten` 顺序逐模块执行（S8 §5.1）：

| 阶段 | 行为 |
| --- | --- |
| `validate` | 全部模块清单/继承/变量/profile/入口/锁一致性；模块图与顺序；先于任何写盘 |
| `compile` | 按模块顺序编译；pom/starter 跳过 |
| `test` | 按模块顺序运行测试；`--skip test` 全局跳过 |
| `package` | 按模块顺序产出：library `.xlib`、starter/pom 清单+`.xmeta`、app 可执行体 |
| `install` | 全部 package 成功后统一安装到本地仓库（可 `--skip install`） |

- `validate` 失败：不写 `target/`、不写仓库、不动锁。
- `compile/test/package` 失败：停止后续模块；当前模块临时产物清理；
  已完成模块的 `target/` 保留（诊断/缓存），不视为成功 reactor。
- `install` 在任何模块 package 失败时完全不执行。

### 4.2 模块内构建

- **pom**：只做 validate；package 只产 `.xmeta`（可选）；install 安装
  `xnull.project` + `.xmeta` 供 parent/聚合定位。
- **starter**：validate + package 清单/`.xmeta`；不编译、不打包源码；
  其依赖已在前面构建；install 只安装清单/元数据。
- **library**：validate → compile → test → package `.xlib` + `.xmeta`；
  install 安装四件产物（S8-13 设计）。
- **app**：validate → compile → test → package 可执行体 + `.xmeta`；
  app 不进入依赖仓库；install 默认跳过（可选安装 `.xmeta` 作审计）。
- 模块内 `target/` 只在模块目录下；reactor 根只写聚合报告（§5）。

### 4.3 模块间消费

- reactor 内依赖 **直接使用 workspace 模块产物/源码闭包**，不先安装到本地
  仓库再取（避免同一次构建读到旧版本或半安装产物）。
- library 的资源按 S8 §5.6 合入 app 的 `resources/`；starter 的资源不合并。
- 外部依赖走锁/本地仓库/远程；`XNULL_REPO` 设置时只走本地且哈希必须匹配。
- 插件执行：同阶段内按 `modules` 声明顺序执行（S8 A.3）；插件不能改变模块图。

## 五、聚合产物

### 5.1 每模块产物

沿用 S8 §5.3：

```text
<module>/target/<artifactId>-<version>.<ext>
<module>/target/<artifactId>-<version>.xmeta
```

- `library`：`.xlib`；`app`：可执行体；`starter`/`pom`：清单 + `.xmeta`。
- `.xmeta` 的 `lockSha256` 均为 reactor 根锁的摘要；`profiles` 为本次生效集合。

### 5.2 聚合报告

根 `target/` 只写聚合构建报告（实现定义，不参与 install）：

```text
<reactor-root>/target/reactor.xpd
```

建议字段：

```xpd
reactor {
  lockSha256 = <64 位小写十六进制>
  modules    = [io.xnull:core, io.xnull:codec, io.xnull:http, io.xnull:cli]
  status     = success
  install    = [io.xnull:core, io.xnull:codec, io.xnull:http]
}
```

- 失败时不写 `status=success`；可写 `reactor-failure.xpd`（失败模块、阶段、诊断）
  供诊断，但不作为成功证据。
- 聚合报告不替代各模块 `.xmeta`；**不以文件数/报告数作为产出指标**。

## 六、失败与回滚

### 6.1 失败边界

| 失败点 | 处理 |
| --- | --- |
| validate（清单/图/顺序/锁） | 不写 target、不写仓库、不改锁；退出 1/2 |
| compile/test/package | 停止后续模块；当前临时产物清理；已完成模块 target 保留；不 install |
| install 预检 | 任一产物哈希/坐标/同版本冲突 → 全部不安装 |
| install 写盘 | 记录本次新建文件；异常时删除本次新建；不覆盖既有版本 |
| lock 更新 | 仅在全 reactor 成功且 install 成功后临时文件 + rename；失败保留旧锁 |

### 6.2 回滚语义

- **不删除**已完成模块的 `target/` 产物：它们是诊断/缓存，不是仓库状态；
  聚合报告标记失败。
- **安装事务**：先预检全部待安装文件（坐标、`.sha256`、同版本哈希），
  再逐个原子安装；任一步异常，删除本次已新建文件，保留旧仓库内容。
- 同版本不同哈希在预检阶段失败（同版本不可变，S8-13 §5.3）。
- 根锁、`reactor.xpd` 不参与 install；失败不写成功报告。

## 七、与锁/本地仓库的交互

### 7.1 单锁

- 全 reactor 一份 `xnull.lock`，位于聚合根（S8 §4.4）。
- 模块目录出现 `xnull.lock` → 失败（多锁会让“哪个锁生效”隐式化）。
- `--update-lock` 只在 reactor 根允许；子模块无独立锁更新入口。
- 锁条目覆盖**外部**依赖与插件；reactor 内模块不写锁（workspace 解析），
  安装后供外部消费者时再由其锁引用。

### 7.2 解析顺序

```text
1. reactor 内 workspace 模块（坐标 + 版本必须匹配）
2. 本地仓库 ~/.xnull/repository（坐标 + 锁 sha256 匹配）
3. 远程仓库（按 repositories 声明顺序；下载后校验锁 sha256）
```

- `XNULL_REPO` 设置：只允许第 2 步；缺件/哈希不符 → 失败，不访问网络。
- reactor 模块版本与依赖引用不符 → 失败（禁止靠锁“修正”成另一个版本）。
- starter 的传递依赖加入同一解析/锁；starter 自身不产代码。

### 7.3 install 顺序

- 全部 package 成功后按 `flatten` 顺序安装：
  - `pom`：清单 + `.xmeta`；
  - `starter`：清单 + `.xmeta`；
  - `library`：`.xlib` + `.xmeta` + `xnull.project` + `.sha256`；
  - `app`：默认不安装。
- 安装坐标/版本/哈希写入根锁（若本次为 `--update-lock`）；否则校验锁一致性。
- 安装不改变 reactor 内已构建产物；不把“安装成功”当作“构建成功”的替代。

## 八、诊断建议（码值待 S8-01/03 冻结）

| 建议码 | 场景 |
| --- | --- |
| XPD-220 | 模块路径缺失/逃逸/重复 |
| XPD-221 | 模块依赖/parent 环 |
| XPD-222 | `modules` 声明顺序不是拓扑序 |
| XPD-223 | reactor 模块版本与依赖引用不一致 |
| XPD-224 | 非 pom 出现 modules / app 被依赖 / starter 含源码 |
| XPD-225 | 重复坐标 |
| XPD-401 | 模块目录出现 `xnull.lock` |
| XPD-402 | 锁与清单/模块图不一致 |
| XPD-501 | 插件跨模块阶段/顺序非法 |

诊断必须含：模块相对路径、坐标、依赖坐标、声明顺序位置、环路径
（如 `core -> http -> core`）。

## 九、验收映射

| 锚点 | reactor 覆盖 |
| --- | --- |
| PROJ-02 继承 | parent 链/深度/环；父先于子；配置合并 |
| PROJ-03 依赖 | 模块图、版本匹配、starter 传递、外部锁解析 |
| PROJ-04 锁 | 单锁在根、外部依赖 `sha256`、`--update-lock` 唯一入口 |
| PROJ-05 生命周期 | 5 阶段顺序、`--skip test`、install、target 布局 |
| PROJ-09 可复现 | 声明顺序确定、锁/哈希稳定、两次构建一致 |

## 十、实现落点（后续 S8-14，不在本设计实现）

建议包与职责：

```text
internal/reactor
  parse.go       # 发现 modules、展开 parent、生成 Module 节点
  graph.go       # 包含/parent/依赖/starter 传递边
  order.go       # flatten 顺序 + 拓扑校验（不重排）
  plan.go        # 阶段计划、install 事务、回滚记录
  diag.go        # XPD-2xx/4xx/5xx 诊断
```

集成点：

- `internal/xpd`：清单 AST；
- `internal/lock`：根锁解析/生成/校验；
- `internal/artifact`：`.xlib`/`.xmeta` 读写与哈希；
- `internal/repository`：本地仓库安装/解析；
- `internal/cli`：`xnull build/install` 聚合入口。

测试建议：

1. 附录 A.2/A.3 夹具：声明顺序合法 → 全绿；`target`/install 顺序正确。
2. 声明顺序倒置（http 在 core 前）→ XPD-222，不自动重排。
3. 依赖环、parent 环、重复坐标、路径逃逸 → 对应诊断。
4. reactor 版本与依赖版本不一致 → XPD-223。
5. starter 传递依赖：app→starter→lib，构建顺序 lib→starter→app；starter 无源码。
6. package 失败：后续模块不构建、无 install、旧锁与仓库不变。
7. install 预检冲突：同版本不同哈希 → 全部不安装。
8. `XNULL_REPO` 离线：缺外部依赖/哈希不符 → 失败，不访问网络。
9. 两次构建：`.xlib`/`.xmeta`/`reactor.xpd` 摘要一致（PROJ-09）。

## 十一、待确认项

1. **声明顺序违反拓扑时**：本设计选择“失败、不重排”（S8 A.3 明确声明顺序即
   构建顺序）。若董事会希望自动拓扑重排，需要改规范，并同步插件跨模块顺序。
2. **嵌套聚合器**：本设计按“先聚合器自身（pom），再其 modules 声明顺序”扁平化；
   需与 S8-01 确认。
3. **多 app**：本设计允许一个 reactor 内多个 app，各自按依赖顺序构建；未要求唯一。
4. **app install**：默认不安装；若需审计元数据，是否允许 `install` app 的
   `.xmeta` 需确认。
5. **reactor 报告格式**：`target/reactor.xpd` 为实现定义，是否纳入 `.xmeta`
   规范字段或独立文档需 S8-04 确认。
