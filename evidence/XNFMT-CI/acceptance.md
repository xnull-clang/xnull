# XNFMT-CI 自检结论

## 判据

| 项 | 判据 | 实测 |
|---|---|---|
| CI 第 11 项 | `--list` 11 项；`--only 11` 通过 | 11 项；PASS，exit 0 |
| 全仓幂等 | 每个 `.x` 格式化两次逐字节相同 | 通过（全仓 `git ls-files '*.x'`） |
| 存量冻结 | 未格式化文件必须在 `ci/xnfmt-baseline.txt`；新增即 FAIL | 负向探针 `ci/probe-unformatted.x` → FAIL 1 并点名；移除后 PASS 0 |
| baseline 只减不增 | 已规范文件仍列在 baseline → 仅提示移除 | 实现：`baseline 已过期（现已规范，可移除）` |
| 全量 CI | 11 项：01–03 真实现、04–09 SKIP、10/11 真实现 | PASS=5 FAIL=0 SKIP=6，exit 0 |
| 发布产物 | `xnull` + `xnfmt` + `SHA256SUMS` | `sh scripts/build_release.sh /tmp/release` exit 0；两个二进制 + 校验清单 |
| 回归 | `go test ./...`（CI 02） | 绿 |

## 存量 baseline

`ci/xnfmt-baseline.txt` 冻结 19 个既有未规范化文件（examples 5、evidence 5、tests/b0-07c-numeric 7、impl/lib 1、其余）。**只允许删除行，新增行视为回退**；未改写的理由见 B1-01（§1 只做差分，不改写历史证据）。

## 缺口

1. 04–09 仍是 SKIP 桩，第 11 项不代表 CI 全量完整。
2. baseline 中的 19 个文件尚未格式化；需董事会/CEO 决定何时一次性格式化（会改动 examples 与证据）。
3. 发布脚本只产出本机平台二进制，无交叉编译/签名；发布口径归 COO。
