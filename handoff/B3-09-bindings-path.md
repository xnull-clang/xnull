# B3-09 绑定查找修复：impl/lib 入口向上加载仓库 bindings

- 卡片：B3-09 门禁回归（B4b 后 xparser 大文件）
- 日期：2026-11-11
- 分支：`pod/e4-codegen`（已 `git merge main`，含 `d8c2019`）
- 改动：`impl/internal/codegen/build.go`、`impl/internal/codegen/ffi_gen.go`、
  `impl/lib/b2/xparser.x`、`tests/b3/xnullc_all.py`、本文件、`evidence/B3-09-bindings/`
- 结论：**PASS**。`xnull build --emit-c impl/lib/b2/xparser.x` 成功；
  B3-09 全量门禁 **PASS0=142 / DIFF=0 / NEG-PASS=97 / EXCLUDED=2**；
  native xparser `ast-check` 12/12、`examples` 9/9 不变。

## 1. 失败复现

```bash
cd wt/e4-codegen/impl
go run ./cmd/xnull build --emit-c lib/b2/xparser.x
# xnull: 代码生成失败：codegen：String 表达式调用未支持（10:18，*xfront.IdentExpr）
```

`impl/lib/b2` 无 `bindings/`，`LoadFFI(filepath.Dir(srcPath))` 得到空注册表；
`impl/lib/xdk/sys.x` 的 `readFileText` 包装调用 `readFileTextRaw/readFileTextError`
没有 `xn_ffi_*` 绑定，codegen 在 sys.x:10 失败。

## 2. 修复

### 2.1 `build.go`：入口目录优先，向上找仓库 bindings

- `resolveFFIRoot(start)`：
  1. 入口目录（递归）有 `.xfb` → 原行为，加载入口目录；
  2. 否则自入口目录向上，遇到 `bindings/` 即停：有 `.xfb` 返回 `bindings/`，
     无 `.xfb` 返回入口目录（保持无绑定路径）；
  3. 到仓库根（存在 `.git`）或文件系统根仍未找到 → 返回入口目录。
- 向上找到的绑定只保留编译单元实际引用的入口（`FilterFFIRegistryByUse`），
  避免把全量 XDK 绑定注入无关入口。入口目录自带 `.xfb` 时不过滤（行为不变）。
- `usesBuiltinXDK` 守卫：编译单元若同时引用 codegen 内建降级的 xdk 入口
  （`env/nowMono/diagnose`、S6-03/04/09），则回退入口目录空绑定。原因是
  canonical `.xfb` 与语言面内建签名可能冲突（`nowMono` 的 `.xfb` 返回
  `Int64`，语言面是 `Int`）。这保持了内建路径与既有输出不变。
- 向上找到绑定时**不调用 `InjectFFI`**：语言面签名继续由 sema 的 xdk 内建表
  提供，codegen 只用注册表发射 `xn_ffi_*`。否则 canonical `.xfb` 签名
  （如 `fileClose/fileOpenRead` 的 Int32 形态）会覆盖语言面签名，改变既有
  sema 判定并意外放行 B3-09 负例。

### 2.2 `ffi_gen.go`：按使用过滤注册表

`FilterFFIRegistryByUse` 用 `xfront.PrintUnit(u)` 中的 `(ident <name>)` 匹配
注册表入口（覆盖 `--file` 入口与 import 闭包），并只保留这些入口引用的
handle/layout/callback；无错误码通道的入口清空 `ErrorMap`，避免生成与
native 投影不一致的错误码助手。

### 2.3 `tests/b3/xnullc_all.py`：门禁投影镜像同一规则

Go 侧现在会加载仓库 bindings，native xnullc 侧的 `--project` 必须同步：
入口目录投影为空时向上找 `bindings/`，按 bundle AST 的 `(Name "...")` 过滤
到实际引用入口（排除内建降级名），无错误码通道时不下发 `M|` 行。
仅测试侧改动，production xnullc/xparser 语义未变。

### 2.4 `xparser.x`：三处 C 逐字节对齐（无语义变化）

为让 Go `--emit-c` 与 native xnullc 在 xparser.x 上 raw diff=0：

| 位置 | 改动 | 原因 |
|---|---|---|
| `main` `--file` 分支 | 先 `String path = args[ai + 1]` 再 `readFileText(path)` | Go 会对 Index 实参生成临时变量，native 内联 |
| `parseBin` / `parsePostfix` | `List<E> lh/eh = []` + `push(...)` | 避免数组字面量元素临时变量差异 |
| `scanString` / `q` | `str('\0')` → `$"{'\0'}"` | Go 的 `str(Char)` 走 `xn_str_int`，native 走 `xn_str_char`；插值两面一致 |

AST 语义不变：B4b 的 `\u0000` → `\x00` 输出仍逐字节一致。

## 3. 验证

### 3.1 `--emit-c`（`evidence/B3-09-bindings/emit-c.txt`）

```text
xnull build --emit-c impl/lib/b2/xparser.x
default_frontend_rc=0  go_frontend_rc=0  frontend_independent=yes
lines=27185 sha256=ff721a9c7daca34f0043954760f8073d9078a3f7ea9e190b2112b6359f6b9d6d
```

无 native xparser 二进制参与：默认前端与 `XNULL_FRONTEND=go` 输出逐字节相同。

### 3.2 B3-09 全量门禁（`evidence/B3-09-bindings/`）

```text
python3 tests/b3/xnullc_all.py --root . --shard 1/1 --parallel 8
汇总：文件 241；excluded=2；entries=239；raw 0 diff 142；
      status {'NEG-PASS': 97, 'PASS0': 142, 'EXCLUDED': 2}
首因：scope-excluded=2
```

- `impl/lib/b2/xparser.x` → `PASS0`（raw=0）
- `impl/lib/b3/xnullc.x` → `NEG-PASS`（仍按冻结负例失败；受 `usesBuiltinXDK` 守卫）

### 3.3 B4b 回归

```text
XPARSER_BIN=/tmp/xparser-b4b-final tests/b4/xnull-build.sh ast-check
AST 一致性：PASS=12 DIFF=0
XPARSER_BIN=/tmp/xparser-b4b-final tests/b4/xnull-build.sh examples
B4b-01 examples：PASS=9 FAIL=0
```

`go test -p 8 ./internal/codegen/...`：`ok codegen`、`ok codegen/ffi`。

## 4. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/e4-codegen
cd impl && go build -o /tmp/xnull-bind ./cmd/xnull && cd ..
/tmp/xnull-bind build --emit-c impl/lib/b2/xparser.x | wc -l

python3 tests/b3/xnullc_all.py --root . --shard 1/1 --parallel 8 \
  --go-bin /tmp/xnull-bind --out /tmp/b3-out
```

## 5. 遗留

1. **canonical `.xfb` 与语言面内建签名冲突**：`nowMono` 在 `bindings/xdk/runtime.xfb`
   返回 `Int64`，语言面为 `Int`；混用会触发 TY-101。当前用 `usesBuiltinXDK`
   守卫回退，E2/E4 需统一签名后移除守卫。
2. **xnullc.x**：绑定修复后 Go 已可生成 C（原生 C 仍有 K-06 temp 差异），
   但 B3-09 v1.0.3 将 xnullc.x 冻结为负例；本卡不改范围/基线，保持 NEG-PASS。
3. **canonical `Invalid` 错误码**：xnullc 的 errorKind 映射不识别 `Invalid`
   （落到 Internal），带 `@errorCode` 的 sys 入口若经向上绑定会引入差异；
   当前 sys 所需两个入口无错误码通道，未触发。
4. 门禁投影过滤与 Go `FilterFFIRegistryByUse`/`BUILTIN_FFI` 是两份镜像逻辑，
   修改时需同步（已在两处注释标注）。
