# 验收：S8-PROJ-05（生命周期与产物）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `e1cdf78`（含 `3756faf` cli 冲突修复、S8-04；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-05/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 5 阶段 `validate→compile→test→package→install` | **PASS**：`manifest.go` 顺序执行；`TestS804ManifestBuildLifecycle` |
| `--skip test` | **PASS**：失败测试 rc=1；`--skip test` rc=0 |
| 产物 `target/<artifactId>-<version>` | **PASS**：`target/app-1.2.3` |
| `.xmeta` 字段完整 | **PASS**：groupId/artifactId/version/packaging/platform/xdkVersion/languageVersion/toolchainVersion/profiles/plugins/lockSha256/inputs |
| 退出码 0/1/2/130 | **PASS**：0（成功）、1（编译失败）、2（清单/用法）、130（SIGINT） |
| `deploy` 不存在 | **PASS**：`CLI-001 unknown command "deploy"` rc=2 |
| 阶段失败不进入后续 | **PASS**：`TestS804SkipTestStage` |

**判定：PASS。** cli 冲突修复后，清单模式生命周期、`--skip`、产物、`.xmeta` 与退出码全部可执行并通过。

---

## 二、实测

### 2.1 构建与产物

```text
build1_rc=0
target/app-1.2.3
target/app-1.2.3.xmeta
```

`.xmeta` 示例（`evidence/S8-QA/PROJ-05/`）：包含 `xmeta {`、坐标、`packaging=app`、`platform=macos`、`xdkVersion=1.1.0`、`languageVersion=[3.3, 4.0)`、`toolchainVersion=0.1.0-dev`、`profiles=[]`、`plugins=[]`、`lockSha256`、`inputs`。

### 2.2 `--skip test`

- 放入失败测试 `src/test/x/main.x`（return 3）：`build` rc=1。
- `build --skip test` rc=0，产物生成。

### 2.3 退出码

| 场景 | rc |
|---|---:|
| 成功构建 | 0 |
| 编译失败 | 1 |
| 清单文法/用法错误 | 2 |
| SIGINT | 130（stderr `xnull: 已中断`） |
| `xnull deploy` | 2（unknown command） |

### 2.4 官方用例

`TestS804ManifestBuildLifecycle`、`TestS804SkipTestStage`、`TestS804ManifestFieldValidation`、`TestS804EntryResolution`、`TestS804ExitCodes`、`TestS804RunManifest` 全 PASS。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-05/cli-tests.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-05/build1.out`、`build2.out`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-05/skip.txt`、`sigint.txt`、`deploy.err`
- 断言依据：S8 §5.5/§10 PROJ-05；`收件箱/门/S8验收计划-QA.md`
