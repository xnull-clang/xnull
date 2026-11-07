# 验收：S6-XDK-08（text）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E3 interp Bytes/UTF-16 `b85715d` 与 E4 XDK-08 收口 `8800a1a`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Format.int/float/string/bool` + `Char` pad | **PASS**：双路径 `0007` |
| `parseInt` / `parseFloat`（`Double`） | **PASS**：`42` / `1.5` |
| `utf8ToUtf16` / `utf16ToUtf8` | **PASS**：双路径 `true/true` |
| `Regex.compile/isMatch` | **PASS**：双路径 `true/false/true` |
| `text.xfb` Regex 绑定端到端 | **PASS**：`0/1/2` |
| 双路径逐字节一致 | **PASS**：`42/1.5/true/true/0007` |

**判定：PASS。** E3 `b85715d` 补齐 interp `Bytes.fromString` 与 UTF-16 转换后，XDK-08 的 Format/parse/UTF/Regex/Char/Double 在解释与编译路径全部通过；上一轮 `未定义的名称：Bytes` 已消失。

---

## 二、双路径 E2E

夹具：`evidence/QA-XDK08/full.x`

```x
import xdk.text
static Int main() {
    Result<Int, Error> a = parseInt("42")
    if (a.isOk()) { print(a.value()) }
    Result<Double, Error> f = parseFloat("1.5")
    if (f.isOk()) { print(f.value()) }
    Bytes b = Bytes.fromString("A")
    Result<List<UInt16>, Error> u = utf8ToUtf16(b)
    print(u.isOk())
    if (u.isOk()) {
        Result<Bytes, Error> back = utf16ToUtf8(u.value())
        print(back.isOk())
    }
    print(Format.int(7).width(4).pad('0').build())
    return 0
}
```

| 路径 | 实测 | 判定 |
|---|---|---|
| `run --interp` | `42\n1.5\ntrue\ntrue\n0007\n`，rc=0 | **PASS** |
| `run`（编译） | 同左，rc=0 | **PASS** |

基础 API（parse/Format.int/Regex）另见 `basic.*`，双路径 `42/true/0007/true/false/true`。

---

## 三、官方用例

| 用例 | 结果 |
|---|---|
| `internal/codegen/s6_xdk08_test.go:TestS6XDK08TextXfbRegex` | **PASS** |
| `internal/interp/xdk_text_test.go:TestXdkTextRuntime` | **PASS** |
| `internal/cli/s6_xdk08_e2e_test.go:TestS6XDK08CompiledE2E` | **PASS** |
| `internal/sema/s6_05_test.go:TestS605*` | **PASS**（上一轮保留） |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/full.x`、`full.interp.out`、`full.compiled.out`、`*.exit`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/basic.x`、`basic.interp.out`、`basic.compiled.out`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/codegen-xdk08.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/interp-xdk08.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/cli-xdk08.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK08/vet.log`
- 断言依据：S6 §4.6/§10 XDK-08
