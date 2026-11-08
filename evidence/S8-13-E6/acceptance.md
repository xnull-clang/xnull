# S8-13 自检结论（.xlib + 本地仓库 + 依赖解析）

## 交付

`impl/internal/artifact`（新包）：
- **`.xlib` 格式**（确定性 zip，Store、零时间戳、条目名升序）：`xlib.meta`（GAV/packaging/依赖列表/逐文件 SHA-256）、`xnull.project`、`xnull.lock`（存在时）、源码根全部文件、资源根全部文件。三次构建 sha256 完全一致。
- **本地仓库布局**：`<repo>/<groupId 点转斜杠>/<artifactId>/<version>/<artifactId>-<version>.xlib` + 同级 `xnull.project`；`Install` 返回安装路径。
- **远程仓库**：只保留 `Remote` 接口与 `ErrRemoteUnimplemented`，不实现、不静默降级（S8 §4.7）。

`impl/internal/cli/manifest.go`：
- `library` 打包：跳过入口校验/编译/测试，package 阶段生成 `.xlib`；install 阶段安装到 `XNULL_REPO`（缺省 `~/.xnull/repository`），输出 sha256。
- 依赖解析沿用 S8-12 的图 + `ValidateLockForGraph`：锁摘要按 `.xlib` 字节校验（`artifactSHA` 命中 `<artifact>-<version>.xlib`）。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 `library` 构建被拒（validateBuildSpec 仅支持 app）：`red.txt` |
| 绿（产物） | `TestXlibDeterministicAndContents`：3 次 sha 一致；含 `xlib.meta`/清单/锁/源码/资源；元数据含依赖与逐文件哈希 |
| 绿（安装） | `TestInstallLayout`：路径 `repo/com/example/lib/1.0.0/lib-1.0.0.xlib` + `xnull.project` |
| 绿（端到端） | `TestLibraryBuildInstallAndConsume`：library 构建并安装 → app 依赖它构建成功；锁摘要=`.xlib` sha256；篡改锁摘要 → `XPD-406` |
| 远程接口 | `TestRemoteStub` |
| 包级 | `artifact`、`cli` 全绿 |
| 全量 `go test ./...` | **红**：`internal/codegen`、`internal/codegen/ffi`（与 S8-12 基线同一批且少 1 个，**新增 0**） |

## 缺口

1. `.xlib` 内暂不编译/链接：app 依赖 library 只做解析/锁校验，未链入产物（按当前阶段；S8-14 reactor 之后再定链接方式）。
2. parent 的「本地仓库 → 远程仓库」定位仍未接（本次只做 library 安装与依赖消费）。
3. app 的 install 阶段仍为空操作；`kind=plugin` 不入锁。
4. 本地仓库默认 `~/.xnull/repository` 未做目录权限/并发写保护。
