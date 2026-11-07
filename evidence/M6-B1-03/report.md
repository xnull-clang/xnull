# M6-B1-03 xnfmt 差分验收报告

> 基线：main `f63fcba52a763eb6176c2fabe7aedd80352f72a2`
> Go oracle：`8ed0153` 干净导出构建 → `impl/cmd/xnfmt`（sha256 `9d20e51787fd98c1af561805a3a3eefe799d47b1c3ec928d2f5ef0d98af94cf9`）
> XNull 版：`65d54ce` 干净导出 + 同树 `xnull` 编译 `impl/xnfmt/xnfmt.x`（sha256 `03e408feb02b1432487bbe862ac3c47801d9576cb5ba4e714109c1d6c458de19`）
> 方式：逐文件复制到临时目录，分别就地格式化，`cmp` 逐字节比较；随后各自二次格式化验幂等

## 结论：FAIL

| 指标 | 值 |
|---|---|
| 语料文件数（main `f63fcba` 全仓库 `git ls-tree '*.x'`） | **155** |
| 逐字节差异数 | **4** |
| 工具失败（任一侧非 0） | 0 |
| 幂等失败（Go / XNull） | 0 / 0（各 155/155 二次格式化不变） |
| 分支专属 `.x` 追加（union） | 11 个，其中差异 1 → union 166 文件 / **5 差异** |
| 异常输入诊断 | Go 4/4 合规；XNull **0/4**（缺文件与目录段错误 rc=139，非法 UTF-8 静默接受 rc=0，无参数无诊断文本） |

判据「0 差异」不成立 → **FAIL**。

## 差异清单

| # | 文件 | 差异 | 归属 | 严重度 |
|---|---|---|---|---|
| 1 | `evidence/M1-TUPLE-01/cli/tuple-ok.x` | `$"pair={pair}"` → `$ "pair={pair}"`；`===` → `== =` | XNull 缺陷：插入空格破坏 token（格式化结果 `LEX-101` + `SYN-101`，不可编译） | P0 |
| 2 | `evidence/M1-TUPLE-01/cli/tuple-switch.x` | `case (1, 2):` → `case(1, 2):` | XNull 缺陷：违反 R6.15/R6.17（关键字后 1 空格） | P2 |
| 3 | `evidence/M6-B0-05/before/branch-tuple-recv.x` | 原始 `p.1.length()`；Go `p.1. length()`；XNull `p.1.length ()` | **双向缺陷**：Go 违反 R6.4（`.` 两侧 0 空格），XNull 违反 R6.5（`)`/`(` 前 0 空格） | P1 |
| 4 | `impl/lib/xdk/text.x` | Go 删除注释与函数之间的单个空行 | Go oracle 缺陷：R5 仅授权删 R5.1–R5.5 的空行，单个空行应保留 | P1 |
| 5 | `impl/xnfmt/xnfmt.x`（分支专属，union） | `!(...)` → `! (...)` | XNull 缺陷：违反 R6.8（一元前缀与操作数 0 空格） | P2 |

差异 1 已实证：XNull 格式化后的文件用 `xnull run --interp` 报 `LEX-101 无法识别的字符 "$"`、`SYN-101 期望表达式，遇到 =`。
交付方自带 `evidence/M6-B1-02/xnfmt.bin` 复现同样的破坏，排除「构建差异」因素。

## 幂等与诊断

- 幂等：155 文件 × 两实现各自二次格式化，`cmp` 全同（0 违约），见 `idempotence.txt`。
- 诊断（`diag.txt`）：

```text
Go  缺文件      rc=2  FMT-104 参数不是可读文件
Go  目录        rc=2  FMT-104
Go  非法UTF-8   rc=2  FMT-102 输入不是合法 UTF-8
Go  无参数      rc=2  FMT-104（stderr 有诊断）
XN  缺文件      rc=139（SIGSEGV），stderr 0 字节
XN  目录        rc=139（SIGSEGV），stderr 0 字节
XN  非法UTF-8   rc=0（静默接受）
XN  无参数      rc=2，stderr 0 字节（无 FMT-104 文本）
```

## 根因提示（只登记，不修）

1. B1-02 的「122 文件 0 差异」是对其分支内 **Go oracle 占位**（`65d54ce:impl/internal/xnfmt`，无 `scan.go`）达成的；与 B1-01 真 oracle（`8ed0153`，含 `scan.go`/FMT 诊断）不是同一实现。
2. XNull 词法/空格判定未覆盖 `$"..."` 插值、`===`、`case` 关键字、`!(...)`、`p.1` 元组选择器；属 token 级误判。
3. Go oracle 的空行规则多删了注释后的单个空行；属 R5 过度归约。

## sha256

| 对象 | sha256 |
|---|---|
| Go 版 xnfmt 二进制 | `9d20e51787fd98c1af561805a3a3eefe799d47b1c3ec928d2f5ef0d98af94cf9` |
| XNull 版 xnfmt 二进制 | `03e408feb02b1432487bbe862ac3c47801d9576cb5ba4e714109c1d6c458de19` |
| Go 输出清单（155 行） | `1d2f10166ca2d06f11136128072efa3cfd30c4b691dceec870b9da89331dc03c` |
| XNull 输出清单（155 行） | `651bb5837a879869d2730cee8b6bf70c5382648830d09488788fad3714e22dc7` |
