# S6-04（E5）：资源读取 XDK-10

- 卡片：S6-04（S6 §4.8 五 API + 七条强制约束；S8 §5.6 资源表）
- 基线：`59ba435`（S6-03-E5）；分支 `pod/e5-runtime`
- 结论：5 API 的 C 面与资源表访问面落地，`rt_std_res.c` 进运行时构建；只读、无句柄、无 close

## 先红

旧树（`59ba435`）无资源 API：`test_res_api.c` 编译报 `xdkc_read_resource`、
`xdkc_read_resource_text`、`xdkc_list_resources`、`xdkc_resource_exists`、
`xdkc_resource_size` 未声明（`red.log`）。旧生成器也不暴露按索引枚举，
`listResources` 无法实现。

## 实现

### `impl/runtime/rt_std_res.c`

| API | C 签名 | 语义 |
| --- | --- | --- |
| `resourceExists` | `int32_t xdkc_resource_exists(const char *path, size_t len)` | 1/0；非法与缺失同为 0 |
| `resourceSize` | `int32_t xdkc_resource_size(const char *path, size_t len, int64_t *out)` | 1=存在、0=缺失/非法（`Int?`） |
| `readResource` | `int32_t xdkc_read_resource(xrt_context*, const char*, size_t, xrt_bytes_buf**, int32_t *error_kind)` | 复制全部字节；NotFound/InvalidArgument/Cancelled |
| `readResourceText` | `int32_t xdkc_read_resource_text(xrt_context*, const char*, size_t, xrt_text**, int32_t *error_kind)` | UTF-8 解码；非法字节 → DataCorrupted |
| `listResources` | `int32_t xdkc_list_resources(xrt_context*, const char*, size_t, const char***, size_t*, int32_t *error_kind)` | 字典序；前缀非目录 → Ok(空列表) |

- **Result 不跨 FFI**：成功返回 `1`，失败返回 `0` 并写 `*error_kind`。不使用“0=成功”是因为
  `XRT_ERR_INVALID_ARGUMENT` 本身为 0，会与成功冲突。
- `xdkc_list_resources_free` 只释放数组；元素指向静态表。
- 只查静态表，**不触碰文件系统**；不提供写入/删除/重命名；返回值不是句柄，**无 close**。
- 入口与 `listResources` 逐条枚举都检查 `xrt_context_check_cancel`；取消返回 `Cancelled`。

### 资源表访问面

- `impl/internal/devtool/resources.go` 在 Python golden 原文之后**追加**
  `xrt_resource_at(size_t, ...)`（按名称升序枚举），供 `listResources` 使用。
- golden 校验只比对追加标记之前的原文（`resources_test.go: baseTable`），
  保持迁移期逐字节一致约束不被新增接口破坏。
- `build_rt.sh` 用同一批样例资源生成表，并与 `rt_std_res.c` 一起编译进
  `xnull_test_res_api`（资源表进运行时构建）。

## 后绿（七条约束逐条）

| # | 约束 | 用例 |
| --- | --- | --- |
| 1 | 绝对路径/`..`/空段/反斜杠 → InvalidArgument | `test_path_invalid`（含 `dir1//x`、`dir1/`、内嵌 NUL） |
| 2 | 只读、返回值非句柄、无 close | `test_no_close_and_no_cache`（无句柄 API；Bytes 为 GC 值） |
| 3 | 挂起点可取消 | `test_cancel`（过期 Context → Cancelled，非 NotFound） |
| 4 | 不隐式缓存 | `test_no_close_and_no_cache`（两次读取是不同对象） |
| 5 | 不回退文件系统 | `test_no_fs_fallback`（CWD 同名文件不生效） |
| 6 | 缺失是 `Result` 错误、不 panic | `test_missing`/`test_read`（NotFound；非法 UTF-8 → DataCorrupted） |
| 7 | 不得用文件 API 读内嵌资源 | `test_no_fs_fallback`（`xdkc_file_open_read` 对 `a.txt`/`dir1/x.txt` 失败） |

- `test_res_api` PASS（`green-res-api.log`）。
- `build_rt.sh` 九套件 exit 0（`green-build_rt.log`）。
- `go test ./internal/devtool -run 'TestGenerateResources|TestValidateResourceName'` PASS
  （`green-devtool.log`）。`TestBuildLedgerRepoGoldenScale` 在基线 `59ba435` 同样红
  （台账 PASS 73/74，非本卡引入）。

## 对齐与转出

- **E2 签名**：`impl/internal/sema/xdksig.go:55-59` 已有 5 API 签名，无需改。
- **E4 发射面**：需按上表 C ABI 发射（`Result` → 返回 1/0 + `error_kind` 出参；
  `List<String>` 从 `const char**` + count 复制到语言列表；`String?`/`Int?` 由 NULL/0 表达）。
  注意 FFI emitter 当前对 `Bytes` 返回尚未编组（`ffi/emit.go` 的返回通道只有
  void/scalar/String/handle），E4 需为资源 5 API 增补内建发射。
- **E6 构建**：`rt_std_res.c` 未加入 `impl/internal/codegen/build.go` 的
  `runtimeCSources`（静态清单）；生成资源表是工程级路径，需在 `buildCCArgs` 追加。
  运行时的 `build_rt.sh` 已按最终形态把两者一起构建，可作为接线样例。
- **E4 绑定**：本次未改 `bindings/`；E4 可按 C ABI 追加（或走内建发射面）。
- 资源规模上限（设计建议单资源 ≤8 MiB/总量 ≤64 MiB）未在本卡执行，属 E6/P1-5。
