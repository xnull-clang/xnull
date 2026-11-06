# S0-25 D1 证据：资源子目录行为对齐 S8 §5.6

## 规范依据

`XNull解决方案-第8部分-工程配置-v5.2.0.md` §5.6「资源目录与打包」：

| 条款 | 原文 | 本卡落实 |
| --- | --- | --- |
| 收录 | 「目录内全部常规文件，按**相对该资源根的路径**收录；空目录不产生条目」 | 递归收录；资源名 = `/` 分隔的相对路径；空目录零条目 |
| 符号链接 | 「按目标内容读取；断链 → 失败」 | 文件链接按目标内容读；断链报错；另拒绝指向目录的链接（防环）与解析后越出资源根的链接 |
| 冲突 | 「两条来源映射到同一制品路径 → 失败」 | 重复资源名仍报错（单根下不可达，保留防御） |
| 制品位置 | 固定前缀 `resources/` + 相对路径 | 本生成器只产出资源表，前缀由打包层负责，不在本卡范围 |
| 运行时 | 「禁止绝对路径与 `..` 段」 | 资源名按段校验，拒绝绝对路径、空段、`.`/`..` 段 |
| 顶层配置 | `application*.properties` 只允许资源根顶层 | `dev res` 不感知 packaging，未做该项；留给打包/配置校验卡 |

旧行为（`resourceNameRe` 整体匹配、不允许 `/`）是 B-full 为逐字节一致而保留的临时偏差，现按规范修正。

## 规则（精确）

1. **资源名**：相对资源根的路径，`/` 分隔，每段 `[A-Za-z0-9_.-]+`（与旧实现同字符集，只是不再禁止 `/`）。
2. **拒绝**：空名、绝对路径、首尾 `/`、空段、`.`/`..` 段、反斜杠、空白与其他字符。
3. **排序**：按资源名**字节序**升序（Go 字符串比较 = C `memcmp/strcmp` 序，二分查表一致）。
4. **空目录**：不产生条目（不递归进入空目录也安全）。
5. **符号链接**：
   - 指向常规文件 → 收录，内容取目标内容（`alias.txt` 与 `real.txt` 各自成为条目）；
   - 断链 → 失败：`符号链接断链：<相对名>（<err>）`；
   - 指向目录 → 失败：`符号链接指向目录（拒绝递归，避免环）：<相对名>`；
   - 目标解析后落在资源根之外 → 失败：`符号链接指向资源根之外：<相对名> → <真实路径>`。
6. **退出码**：沿用 CLI 合同，输入/用法错误一律 2，stderr 前缀 `gen_resources: `。

## 实现

`impl/internal/devtool/resources.go`：
- `resourceNameRe` → `resourceSegmentRe` + `validateResourceName`（按段校验）；
- `collectResources` 增加符号链接分支（`os.Stat` 跟随、`EvalSymlinks` 取真实路径、`within` 判根）；
- `within(rootReal, target)` 防越界；资源根本身先 `EvalSymlinks`（兼容 macOS `/tmp` → `/private/tmp`）。

首行生成器署名**未改**（仍是 `impl/tools/gen_resources.py`），按董事会令 S0-27 §1.1 属 S0-27b 可选项，不并入本卡，因此本次 golden 差异只含子目录条目。

## 新基线

| 产物 | sha256 |
| --- | --- |
| `golden/res-with-subdir.c`（新规则基线，6 项资源） | 见 `sha.txt` |
| `golden/res-no-subdir.c`（旧 fixture 重生成） | `2f88b9314adf77fc9a731202627d042242f7ebfe71e76c244afa9326b3c95949`（与 S0-21a Python golden 逐字节相同） |

`golden/diff-vs-python-golden.diff`：旧 golden → 新基线，**只有 3 段新增条目**（`sub/multi/deep.bin`、`sub/x.txt`、`templates/mail/welcome.html`），原有 3 条与全文其余部分零改动。符合「预期仅子目录相关」。

## 自检结论

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| 子目录 fixture 正确收录 | 多级路径成为资源名，可按名查找 | 探针通过：6 项资源，`sub/x.txt`、`sub/multi/deep.bin`、`templates/mail/welcome.html` 均可 `xrt_resource_get` 命中 |
| 稳定排序 | 连续生成一致、按字节序 | 单测 `TestGenerateResourcesIncludesSubdirectories` + `TestGenerateResourcesDeterministic` |
| 非法名仍拒绝 | 退出码 2 + 点名相对路径 | `sub/bad name.txt` → 2 |
| 越界/断链/目录链接 | 退出码 2 + 明确诊断 | 3/3 通过（见 `negative/`） |
| 旧行为回归 | 无子目录 fixture 与 Python golden 逐字节一致 | sha256 相同 |
| build_rt | 退出码 0 | 0（含「资源表测试通过」） |
| devtool/cli 测试 | 全绿 | 两包 ok；`go vet ./...`=0；`go test ./...`=0 |
| 规范引用 | 文档写明 §5.6 | 本文件 + 代码注释 |

## 声明

执行侧自检，不构成 QA1 验收。未 push、未合并、未改公开仓、未碰 interp/codegen、未改台账状态。
