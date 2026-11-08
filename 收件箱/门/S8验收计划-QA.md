# S8 验收计划（QA1）：PROJ-05..11

> **版本**：v0.1（准备版）　**日期**：2026-11-08
> **基线**：main `7fa5cfd`（S8 批量合入中；本文只列用例/命令/证据，不签 PASS）
> **范围**：S8 §9 的 PROJ-05..11（PROJ-01..04 已另签；PROJ-07/08 已 PASS，保留复验命令）
> **依据**：`XNull解决方案-第8部分-工程配置-v5.2.0.md` §5.5/§5.6/§9/§10；`收件箱/门/S8盘点-E3.md`
> **证据约定**：逐锚点 `evidence/S8-QA/PROJ-0X/`；根验收 `收件箱/回执箱/验收-S8-PROJ-0X.md`
> **纪律**：本计划不运行 git、不写生产代码；实现落地后按本表执行并签字。

---

## 0. 当前状态（准备时）

| 锚点 | 现状 | 阻塞/归属 |
|---|---|---|
| PROJ-05 生命周期与产物 | **BLOCKED**：`xnull build` 清单模式仍 `notImplemented`；无 5 阶段/`--skip`/`.xmeta` | S8-04（E6，依赖 S8-01/03） |
| PROJ-06 插件 | **部分**：`impl/internal/plugin` 已有 metadata/declaration/run policy 测试；未接构建期阶段 | S8-05 + S8-04 接线 |
| PROJ-07 配置覆盖 | **PASS（已签）**：`验收-S8-PROJ-07.md` | 复验 config/manifest |
| PROJ-08 配置严格性 | **PASS（已签）**：`验收-S8-PROJ-08.md` | 复验 config |
| PROJ-09 可复现 | **BLOCKED**：无 `.xmeta`/摘要比对；锁字节已验证 | S8-09 + S8-04 |
| PROJ-10 文法诊断 | **部分**：XPD-0xx/1xx + 2xx/3xx 已落地；2xx–8xx 全表/段落路径未全 | S8-10 + S8-01..08 |
| PROJ-11 资源 | **BLOCKED**：`resman` 清单侧收割器尚未合入 main；当前仅 `dev res` 单根 | S8-08 + S8-04 |

**执行顺序**：S8-04 生命周期 → PROJ-05/06/09/10/11 逐项；PROJ-07/08 直接复验。

---

## 1. PROJ-05 生命周期与产物

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ05-A01 | build | 单 app 工程 | 5 阶段 `validate→compile→test→package→install` 顺序执行 |
| PROJ05-A02 | build | 同上 + `--skip test` | test 阶段跳过，其余阶段执行 |
| PROJ05-A03 | CLI | `xnull deploy` | 命令不存在（非 0；无 deploy 实现） |
| PROJ05-A04 | CLI | 成功/编译失败/用法错误/SIGINT | 退出码 0/1/2/130 |
| PROJ05-A05 | artifact | app 工程 | `target/<artifactId>-<version>/` 产物与入口可执行 |
| PROJ05-A06 | meta | app 工程 | `.xmeta` 含 groupId/artifactId/version/packaging/mode/entry/lockDigest/toolchain，字段完整 |
| PROJ05-R01 | build | 阶段中失败 | 非零退出，不进入后续阶段；错误带位置 |

### 命令（S8-04 落地后）

```bash
cd impl && go test ./internal/cli -run 'TestBuildLifecycle|TestXMeta|TestExitCodes' -count=1 -v
X=/tmp/xnull-s8; (cd impl && go build -o "$X" ./cmd/xnull)
D=$(mktemp -d); "$X" new app demo "$D/demo"; cd "$D/demo"
"$X" build --skip test; echo rc=$?
"$X" build; test -f target/demo-0.1.0.xmeta
"$X" deploy; echo rc=$?          # 期望非 0/不存在
```

### 证据

`evidence/S8-QA/PROJ-05/<case>/{cmd,stdout,stderr,exit_code,sha}.txt` + `.xmeta`/target 清单。

---

## 2. PROJ-06 插件

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ06-A01 | plugin | `.xplugin` 完整元数据 | 加载通过；版本精确 |
| PROJ06-A02 | plugin | `phase=validate/test/...` | 合法 phase 通过；非法 phase → XPD-501 |
| PROJ06-A03 | plugin | 未声明 goal | XPD-501 |
| PROJ06-A04 | plugin | `configuration` 键未在 configKeys | XPD-501 |
| PROJ06-A05 | sandbox | 插件写 `target/` | 通过 |
| PROJ06-A06 | sandbox | 插件写 `target/` 之外 | XPD-502 |
| PROJ06-A07 | sandbox | 插件访问网络 | 拒绝（XPD-505/合同） |
| PROJ06-A08 | exit | 插件非零退出 | XPD-503，构建失败 |
| PROJ06-A09 | classpath | 插件依赖 | 不进编译类路径 |
| PROJ06-A10 | meta | `.xplugin` 缺失/字段不符 | XPD-504 |

### 命令

```bash
cd impl && go test ./internal/plugin -count=1 -v
# 构建期接线（S8-04 后）：
X=/tmp/xnull-s8; (cd impl && go build -o "$X" ./cmd/xnull)
"$X" build <plugin-fixture>; echo rc=$?
```

### 证据

`evidence/S8-QA/PROJ-06/<case>/` + plugin 测试日志 + 构建日志。

---

## 3. PROJ-07 配置覆盖（已 PASS，复验）

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ07-A01 | config | configuration/builtin/application/profile/env/CLI 六层 | 覆盖顺序与来源层正确 |
| PROJ07-R01 | config | 同层重复键 | XPD 重复键 |
| PROJ07-R02 | config | 白名单外 env | 忽略，不覆盖 |
| PROJ07-A02 | CLI | `--key=value` | 覆盖生效，审计只记 key/层/来源 |
| PROJ07-R03 | config | `application-staging.properties` 未在 profiles | XPD-6xx |

### 命令

```bash
cd impl && go test ./internal/config -count=1 -v
go test ./internal/manifest -run 'TestProfiles' -count=1 -v
```

### 证据

`evidence/S8-QA/PROJ-07/`（已有 config-tests/manifest-profiles）。

---

## 4. PROJ-08 配置严格性（已 PASS，复验）

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ08-R01 | config | 未知键 | 失败并逐键列出 |
| PROJ08-R02 | config | 缺必需键 | 失败并点名 |
| PROJ08-R03 | config | 类型解析失败 | 含键 + 层级/文件 |
| PROJ08-R04 | config | library 出现 application.properties | 失败 |
| PROJ08-R05 | config | 明文密钥 | 失败；`${...}` 允许 |
| PROJ08-R06 | config | 非法键名 | 失败（6 类） |
| PROJ08-R07 | config | 子目录/非 UTF-8 | 失败 |

### 命令

```bash
cd impl && go test ./internal/config -count=1 -v
```

### 证据

`evidence/S8-QA/PROJ-08/`（已有 config-tests）。

---

## 5. PROJ-09 可复现

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ09-A01 | build×2 | 同清单+锁+工具链 | 两次 `.xmeta` digest 一致；产物摘要一致 |
| PROJ09-A02 | lock | 同一锁写入 | 字节稳定（坐标升序） |
| PROJ09-R01 | fs | 构建 | `target/` 外无写入（mtime/快照） |
| PROJ09-R02 | lock | 清单/锁/工具链变化 | digest 变化且可解释 |

### 命令（S8-09 落地后）

```bash
X=/tmp/xnull-s8
D=$(mktemp -d); cp -R fixture "$D/a"; cp -R fixture "$D/b"
"$X" build "$D/a"; "$X" build "$D/b"
sha256sum "$D"/a/target/*.xmeta "$D"/b/target/*.xmeta   # digest 一致
sha256sum "$D"/a/target/* "$D"/b/target/*               # 产物一致
find "$D/a" -newer "$D/a/xnull.project" -not -path '*/target/*'  # 应为空
```

### 证据

`evidence/S8-QA/PROJ-09/{build-a,b}/`、`digests.txt`、`outside-target.txt`。

---

## 6. PROJ-10 文法与诊断

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ10-A01 | check | 附录 C 每条错误规则各一例 | 全部命中对应码，含 `line:col` + 段落路径 |
| PROJ10-A02 | diag | 码表 | 段位符合：0xx/1xx 词法文法、2xx schema、3xx 坐标继承、4xx 版本锁、5xx 插件、6xx 配置、7xx/8xx 其余 |
| PROJ10-A03 | fmt | `xnull fmt` 清单/锁/元数据 | 幂等；语法错误保留 |
| PROJ10-R01 | diag | 同一错误多位置 | 不合并、不漏报；顺序稳定 |

### 命令

```bash
cd impl && go test ./internal/diag ./internal/xpd ./internal/manifest -count=1 -v
go test ./internal/cli -run TestFmt -count=1 -v
```

### 证据

`evidence/S8-QA/PROJ-10/<rule>/{source,diag,exit,section-path}.txt` + 码表清单。

---

## 7. PROJ-11 资源

### 用例

| ID | 模式 | 夹具 | 期望 |
|---|---|---|---|
| PROJ11-A01 | res | 缺省 `src/main/resources` | 收录；制品内 `resources/<相对路径>` |
| PROJ11-A02 | res | includes/excludes + glob | 优先级与匹配正确 |
| PROJ11-A03 | res | 多来源同路径 | 冲突失败并点名双来源 |
| PROJ11-A04 | res | 依赖库资源 | 合并进 app；冲突失败 |
| PROJ11-A05 | res | starter | 资源不合并给使用者 |
| PROJ11-A06 | res | `.x` 文件 | 按数据打包，不编译 |
| PROJ11-A07 | res | symlink | 跟随；断链失败 |
| PROJ11-R01 | res | `pom` 出现资源根 | 失败 |
| PROJ11-R02 | res | 资源配置在子目录/模块根 | 失败 |
| PROJ11-R03 | res | 清单变量 | 资源字节不变（无过滤） |

### 命令（S8-08 合入后）

```bash
cd impl && go test ./internal/resman -count=1 -v
X=/tmp/xnull-s8; (cd impl && go build -o "$X" ./cmd/xnull)
"$X" build <resource-fixture>; echo rc=$?
unzip -l <artifact> | grep '^.*resources/'
```

### 证据

`evidence/S8-QA/PROJ-11/<case>/` + 制品清单 + 冲突/断链/字节比对日志。

---

## 8. 判定口径

- **PASS**：正例 + 负例 + 诊断码/位置 + 运行时或产物行为；跨层锚点需两层证据。
- **FAIL**：已可执行但行为不符，或关键负例未拒绝。
- **BLOCKED**：依赖卡未合入；不得以“未支持”诊断记 PASS。
- 每个锚点签字文件：`收件箱/回执箱/验收-S8-PROJ-0X.md`；证据目录 `evidence/S8-QA/PROJ-0X/`。
- 本计划不更新 `status.tsv`；QA 独立执行后由 SSOT 翻转。

---

## 9. 当前缺口汇总（给 E6）

| 锚点 | 缺口 | 依赖 |
|---|---|---|
| PROJ-05 | 清单模式 build/run/test、5 阶段、`--skip`、`.xmeta`、target 布局 | S8-04 |
| PROJ-06 | 插件接构建期阶段、沙箱执行入口 | S8-05 + S8-04 |
| PROJ-09 | `.xmeta` digest、两次构建比对、target 外写入检查 | S8-09 + S8-04 |
| PROJ-10 | 附录 C 全表、2xx–8xx 码位/段落路径 | S8-10 + 各语义卡 |
| PROJ-11 | `resman` 清单侧收割器、glob/冲突/依赖合并/starter/symlink | S8-08 + S8-04 |
