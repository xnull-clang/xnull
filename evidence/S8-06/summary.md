# S8-06（E5）：服务运行时配置

- 卡片：S8-06（S8 §6.1—§6.6；PROJ-07/PROJ-08）
- 基线：main `82d0158`
- 结论：新增 `impl/internal/config`，实现 `application[-profile].properties` 加载、
  五层覆盖、env 白名单、严格键/类型/密钥校验（XPD-600—XPD-608）

## 先红

`go test ./internal/config` 在实现前失败：`Spec`/`KeySpec`/`Kind*` 未定义
（`red.log`，包不存在）。

## 实现

### 入口

```go
config.Load(config.Options{...}) (*config.Result, []diag.Diagnostic)
config.ParseCLIOverrides([]string) (map[string]string, []diag.Diagnostic)
```

`Options`：`ResourcesDir`、`Profile`、`Packaging`、`Configuration`（层 0）、
`Builtin`（层 1）、`Environ`（层 4）、`CLI`（层 5）、`Spec`、`Audit`。
`Spec`：`Keys`（类型 + 必需）、`Profiles`、`EnvWhitelist`。

### 五层覆盖（§6.4）

| 层 | 来源 | 实现 |
| --- | --- | --- |
| 0 | 父 `configuration` | `Options.Configuration` |
| 1 | 内建缺省 | `Options.Builtin` |
| 2 | `application.properties` | `ResourcesDir` 顶层 |
| 3 | `application-<profile>.properties` | `Options.Profile` 选中 |
| 4 | `XNULL_OVERRIDE_<KEY>` | 仅 `EnvWhitelist`；点/连字符→下划线、大写 |
| 5 | `--key=value` | `Options.CLI` / `ParseCLIOverrides`；写审计 |

- 低层可被高层覆盖；同层重复键失败；
- 白名单外 `XNULL_*` 忽略；白名单键缺失不算错；
- 覆盖不能新增键（未知键失败）。

### 严格校验（§6.5，XPD-600—608）

| 码 | 场景 |
| --- | --- |
| XPD-600 | 非法 UTF-8 |
| XPD-601 | 键名非法（小写字母/数字/点/连字符，≤128，无连续/首尾点） |
| XPD-602 | 同层重复键 |
| XPD-603 | 未知键（逐键点名） |
| XPD-604 | 缺失必需键 |
| XPD-605 | 类型错误（Int/Bool/Float；含键/层/文件路径） |
| XPD-606 | 疑似密钥键（password/secret/token/key）字面值；`${...}` 占位允许 |
| XPD-607 | profile 文件名/`--profile` 与清单 profiles 不符 |
| XPD-608 | 非 app 出现配置；配置文件不在资源根顶层 |

### 格式（§6.2）

- UTF-8 flat properties；一行一键；`#` 注释（值内 `#` 也视为注释开始）；
- 值一律字符串；不支持多行/转义；
- 文件必须位于资源根顶层；`application.properties` 与 profile 文件分开加载。

## 后绿

- `go test ./internal/config -v`：15 个用例 PASS（`green-gotest.log`）；
- `go vet ./internal/config`：exit 0（`green-vet.log`）；
- 覆盖：五层优先级、env 白名单、未知/缺失/重复/非法键、类型错误、
  密钥字面值/占位、profile 不符、非 app、子目录放置、非法 UTF-8、CLI 解析/审计。

## 边界/下一步

- 本卡只交付配置加载与校验包；`xnull build/run` 的清单解析/生命周期与
  `main` 执行前启动校验需 S8-02/04 接入（把 `configuration`、profiles、packaging、
  绑定键表传给 `Options`）。
- 运行时配置以启动时快照为准；不实现热重载/配置中心（S8 §10 否决）。
- 疑似密钥检测按段名 `password|secret|token|key`（含 `-key` 后缀）；占位定义
  为值含 `${...}`；正式密钥必须走白名单环境变量。
