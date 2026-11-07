# E5 交付：xdkc_utf8_valid（B1-02/B1-03 第 4 项诊断）

- 日期：2026-11-07
- 卡片：B1-02（第 4 项诊断的前置 API）→ 交回 E4 接 B1-03
- 结论：`xdkc_utf8_valid` C 实现 + `bindings/xdk/sys.xfb` 绑定已落地；C 测试与 XNull 端到端均通过。

## 接口

| 项 | 值 |
| --- | --- |
| C 符号 | `int32_t xdkc_utf8_valid(const char *bytes, size_t len)` |
| 语义 | **0 = 合法 / 非 0 = 非法**（与 XDK 错误码同向） |
| 绑定入口 | `Int utf8Valid(String text)`（`bindings/xdk/sys.xfb`，`@blocking(.aware)`，`@lease(text=.borrow)`） |
| 长度口径 | `len` 权威；允许内嵌 NUL；不要求 NUL 终止（S7 §3.4） |
| 校验规则 | 过短编码、代理区、> U+10FFFF、孤立续字节、截断、非法首字节均判非法（S1 §9.2） |

## 验证

```bash
# 1) C 层单测（六套件）
cd impl/runtime && sh build_rt.sh

# 2) 绑定/生成面
cd impl && go test ./internal/codegen/ffi/ -count=1

# 3) XNull 端到端（有效字符串 + 含 0xFF 的文件）
cd impl && go build -o /tmp/xnull-utf8 ./cmd/xnull
cp -a ../bindings /tmp/utf8probe/bindings   # 或从仓库根加载
printf '\xFF\xFE' > /tmp/utf8probe/bad.bin
printf 'ok-text' > /tmp/utf8probe/ok.txt
/tmp/xnull-utf8 build /tmp/utf8probe/prog.x -o /tmp/utf8probe/prog && /tmp/utf8probe/prog
```

实测：C 测试 `build_rt EXIT=0`；`go test ./internal/codegen/ffi/` ok；端到端 `RUN_EXIT=0`
（`utf8Valid("abc")==0`、`utf8Valid(readFileText(bad.bin))!=0`、`utf8Valid(readFileText(ok.txt))==0`）。

## 文件

| 文件 | 说明 |
| --- | --- |
| `impl/runtime/rt_std_text.c` | `xdkc_utf8_valid` 实现（复用 `utf8_decode`） |
| `impl/runtime/test_std.c` | `test_utf8_valid` 15 条断言（合法/非法/边界/NULL） |
| `bindings/xdk/sys.xfb` | `utf8Valid` 入口 |
| `impl/docs/blocking-classification.md` | 阻塞分类表增 `utf8Valid` 行 |
| `impl/internal/codegen/ffi/xdk_test.go` | 入口清单期望增 `utf8Valid` |

## 证据

`build.log`、`run.log`、`c-tests.log`、`probe.x`（sha256 `feca3a49…`）。

## 边界与提醒

- 本卡只新增只读校验入口，未改任何既有 ABI 符号、编译器语义或测试期望（`xdk_test.go` 的入口清单为新增项同步）。
- E4 侧 `impl/xnfmt/bindings/xdk/sys.xfb` 是独立副本，需同步加入 `utf8Valid` 入口（或改为加载仓库根 `bindings/`）。
- 绑定暴露为 `Int` 而非 `Bool`：当前主线 P-09 尚未接入 Bool 返回；`0/非 0` 语义与请求一致。
