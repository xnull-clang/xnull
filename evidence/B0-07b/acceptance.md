# M6-B0-07b 自检结论：文本变体文件 API

> 依据：B0-06 文本变体验收（`验收-M6-B0-06.md` §二）与 M6-B0-07b 卡片。基线 `main` = `7d5651a`（本卡前推进为快进合并，`pod/e6-toolchain` 已与 main 同源）。先红后绿。

## 变更

| 文件 | 内容 |
| --- | --- |
| `bindings/xdk/sys.xfb` | 新增 `String readFileText(String path)`（`xdkc_read_file_text`）与 `Int writeFileText(String path, String text)`（`xdkc_write_file_text`），均 `@lease(.borrow)` + `@blocking(.unaware)` |
| `impl/runtime/rt_std_sys.c` | 新增 `xdkc_read_file_text`（整文件读，复用缓冲 + NUL 结尾；失败返回 NULL）与 `xdkc_write_file_text`（整文件写，成功 0 / 失败非 0）；均不 panic |
| `impl/docs/blocking-classification.md` | 补 `readFileText`/`writeFileText` 两行（文档同步测试自动校验） |
| `impl/internal/codegen/ffi/xdk_text_test.go` | 新增：入口/cName 断言 + 生成包装 + 写→读→缺失文件三态比对 |
| `impl/internal/codegen/ffi/xdk_test.go` | 注册表入口清单加两项（库存断言） |
| `impl/internal/codegen/ffi/emit.go` | **附带修复**：String 返回的原生变量类型改为 `const char *`（此前误声明为 `xrt_string *`，C 报 `incompatible pointer types`）；`xn_out` 仍为 `xrt_string **`。E4/P-09 域，因本卡首个大量使用 String 返回而暴露，已在回执声明 |

## 红 → 绿

| 阶段 | 证据 | 结果 |
|---|---|---|
| 红（绑定未加） | `red.txt` | `TestXDKTextFileAPI` FAIL：`绑定缺少 readFileText（B0-06 文本变体）` |
| 绿（绑定 + C 实现） | `green.txt` | PASS：`write wr=0 rc=0` / `read r=0 null=0` / `text len=11 body=hello` / `missing r=0 null=1` |

## 端到端（真实 B0-06 文本变体程序）

`evidence/B0-07b/run.sh` 用 QA1 的 `program/read_parse_write_text.x` + 两套 fixture 构建运行：

```
build exit=0
生成告警数：3
PASS  in1.x  exit=0  sha256=610855eb…1e18
PASS  in2.x  exit=0  sha256=9b10db97…2299
汇总：PASS=2 FAIL=0
```

`readFileText`/`writeFileText` 已被 P-09 注入识别（`xn_ffi_readFileText`/`xn_ffi_writeFileText` 出现在生成代码），程序无需任何测试脚手架 `textfile.xfb`。

## 余下告警（如实登记，非本卡引入）

`e2e-warnings.txt` 共 3 条：2 条 `-Wparentheses-equality`（既有 codegen 噪声）；1 条调用点 `rt_string **` → `xrt_string **` 类型不兼容（P-09 注入侧用 `rt_string*` 承接 String 返回值）。功能正确、2/2 通过，但属 E4/P-09 域待清理项，未在本卡擅自改动调用点。

## 验收

| 项 | 实测 |
|---|---|
| 绑定入口 | `readFileText`/`writeFileText` 存在，cName 正确，`.unaware` |
| C 实现 | 整文件读/写；失败 NULL/非 0；不 panic |
| P-09 注入识别 | 生成代码含两个包装；`xnull build` 真实程序 exit 0 |
| B0-06 文本变体 | **2/2**（in1/in2 输出与 expected 逐字节一致） |
| 回归 | `go vet`=0；`go test ./... -timeout 300s`=0（9 包）；`build_rt.sh`=0 |
| 干净 clone | `clone.txt` |

## 声明

执行侧自检，不构成验收签署；QA1 复跑为准。未 push、未合并（本分支已快进到 main）。
