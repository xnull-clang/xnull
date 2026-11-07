# QA1 B1-03 独立复验

被测：`pod/e4-codegen` @ `cac6686`（`9832bfb`/`6dc2bfa` 的 `impl/`、`bindings/` 与之一致）。
不引用 E4 的 evidence/结论；从 git 提交导出源码，QA1 自行构建两侧二进制。

## 一键复验

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
E4_SHA=cac6686 bash difftest/b1-03/verify-b1-03.sh
E4_SHA=cac6686 bash difftest/b1-03/verify-diagnostics.sh
bash difftest/b1-03/verify-utf8-runtime.sh      # E5_SHA 默认 c9e8a5d
```

## 结果

```
corpus=7df123d files=122 diffs=0 errors=0 idem_go=0 idem_xn=0
corpus=f63fcba files=155 diffs=0 errors=0 idem_go=0 idem_xn=0

noargs       rc=2  期望=2/FMT-104  PASS
missing      rc=2  期望=2/FMT-104  PASS
directory    rc=2  期望=2/FMT-104  PASS
badutf8      rc=2  期望=2/FMT-102  PASS
unterm       rc=2  期望=2/FMT-101  PASS
badcomment   rc=2  期望=2/FMT-101  PASS
诊断项：6/6

utf8_valid QA probe: 32/32 PASS
```

判定 **PASS**。完整回执：`收件箱/回执箱/CEO3/验收-M6-B1-03.md`。

## 脚本

| 文件 | 作用 |
|---|---|
| `verify-b1-03.sh` | 多语料逐字节差分 + 双方二次格式化幂等；`CORPUS_SHAS` 可覆盖，默认 `7df123d f63fcba` |
| `verify-diagnostics.sh` | 6 项诊断：FMT-104（缺文件/目录/无参数）、FMT-102（非法 UTF-8）、FMT-101（未闭合字符串/块注释），均断言 rc=2 |
| `verify-utf8-runtime.sh` + `utf8_valid_probe.c` | 独立 C 探针验证 `xdkc_utf8_valid`，32 条语义/边界断言 |

## 限制

- 差分只证明 Go oracle 与 XNull 版一致，不证明符合规范；规范级共享向量仍缺。
- union 语料（E4 自报 156/157）未由 QA1 复跑。
- XNull 诊断位置统一 `0:0`，Go 为精确 `line:col`；码型与退出码一致。
