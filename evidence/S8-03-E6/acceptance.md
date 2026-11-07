# S8-03 自检结论（依赖管理 / 版本仲裁 / 锁文件）

## 交付

`impl/internal/manifest/deps.go`：
- `ResolveDependencies`：依赖自身版本 > 最近 `dependencyManagement`（继承链子优先）；都无 → `XPD-401`；`XPD-402` 拒绝范围/`SNAPSHOT`/`LATEST`/`RELEASE`/`*`（预发布精确版本如 `1.2.3-rc.1` 允许）；显式版本覆盖管理版本 → 警告（`Resolved.Warnings`）。
- `dependencyManagement` 解析：`scope`/`optional` → `XPD-407`；同表坐标重复 → `XPD-403`。
- `Lock`/`LockEntry`：`LoadLock` 校验 lock 块/版本=1/`sha256` 64 位小写十六进制/坐标升序/坐标唯一（`XPD-404/405/406`）；`ValidateLock` 校验锁与清单一致（缺条目/版本不一致→404，多余坐标→405，摘要不符→406，本地仓库可用时比对实际制品）；`GenerateLock` 摘要沿用旧锁或本地仓库 `XNULL_REPO`（`group/artifact/version/artifact-version.ext`）；`WriteLock` 按坐标升序写稳定字节。

`impl/internal/cli/lock.go`：
- `xnull lock [工程目录]`：只校验（缺锁/不一致 → 1，诊断 XPD-4xx 带位置）；
- `xnull lock --update-lock [工程目录]`：唯一重生成入口。

## 验证

| 项 | 结果 |
|---|---|
| `go test ./internal/manifest` | **ok**（管理版本/缺版本/非法形态/预发布允许/覆盖告警/管理表 scope/锁生成排序/缺条目/多余坐标/摘要不符/版本不一致/排序稳定） |
| `go test ./internal/cli -run TestLockCommand` | ok（缺锁→失败；`--update-lock` 生成且摘要正确；校验通过；清单变更→`XPD-404`） |
| `go test ./internal/cli`（全包） | ok（43.6s） |

## 缺口

1. 冲突仲裁只做「管理表优先 + 继承就近」；依赖树「同深度多处出现→失败」与传递依赖/exclusions/scope 传播未实现（无依赖图）。
2. 仓库仅支持本地 `XNULL_REPO`；HTTP 拉取、镜像、凭据未实现。
3. 锁生成依赖本地制品摘要；纯清单无仓库时按规范拒绝生成（`XPD-404` 提示）。
4. `kind=plugin` 条目未生成（插件未接入）。
