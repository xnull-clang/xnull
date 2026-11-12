# bootstrap/ —— 无 Go 引导（B4c-02a）

本目录保存**已冻结的 C 源**，只依赖 `cc` + `impl/runtime` 的 14 个 C 源即可构建出两个原生工具，
不调用 `go`、不依赖 /tmp 里的历史二进制。

| 文件 | 来源 | sha256（前 12 位） |
|---|---|---|
| `xn-s4.c` | B4c-03 编译器工件：当前 `xnullc.x` + 2 处 C 级修复，115,751 行 | `27ae5245452a` |
| `xparser.c` | B4c-03 原生自举：`tests/b4/rebuild-xparser.sh`（xn-s4 + 原生 bundle + proj B） | `391ec8465bb9` |

产物（`bootstrap/bin/`，**不入库**，由 `.gitignore` 忽略）：

- `xn-s4`：原生 XNull 编译器（AST → C）；
- `xparser`：原生解析器，支持 `--file <path>` / `--diags --file` 与源码字符串模式。

## 构建

```bash
bootstrap/build.sh                 # 只需 cc；可用 CC / XNULL_RUNTIME 覆盖
ls bootstrap/bin                    # xn-s4  xparser  res.c
```

构建脚本完全不调用 `go`，可在 `PATH` 不含 Go 的机器上执行：

```bash
env PATH=/usr/bin:/bin:/usr/sbin:/sbin bootstrap/build.sh
```

## 用法

```bash
# 1) AST
bootstrap/bin/xparser --file tests/b2/corpus/examples/hello.x > /tmp/hello.ast

# 2) C
bootstrap/bin/xn-s4 tests/b2/corpus/examples/hello.x \
  --ast-file /tmp/hello.ast --project "" > /tmp/hello.c

# 3) cc（与 tests/b4/xnull-build.sh 相同的链接口径）
cc -std=c11 -O2 -pthread -I impl/runtime -o /tmp/hello /tmp/hello.c \
   impl/runtime/{rt.c,rt_gc.c,rt_policy.c,rt_weak.c,xrt_abi.c,rt_std_runtime.c,rt_std_text.c,rt_std_sys.c,rt_std_bytes.c,rt_std_net.c,rt_task.c,rt_sync.c,rt_std_res.c,rt_std_res_empty.c} \
   bootstrap/bin/res.c
/tmp/hello
```

或直接走统一 CLI：

```bash
bin/xnull --bootstrap build tests/b2/corpus/examples/hello.x -o /tmp/hello
bin/xnull --bootstrap examples        # 9/9
```

## 边界

- `xparser.c` 由 B4c-03 原生工具链生成；`tests/b4/rebuild-xparser.sh` 可复现（需已有
  `bootstrap/bin/{xparser,xn-s4}`），不调用 Go。
- `xn-s4.c` 是 B4c-03 编译器工件，**不是** B3-10 固定点：当前 `xnullc.x` 自编译仍会挂起
  （E4 债务）；B3-10 历史固定点 sha256 为 `347908a93865…`、116,085 行，保存在 git 历史。
- 工件相对 Go 解释器有两处 C 级修复：proto 返回的 `b + ")"` 拼接、NUL 字符串
  `rt_string_from_c("\000")` → `rt_string_new("\000", 1)`；源级修复留给 E4。
- 资源表固定为空表；资源/FFI 投影、`.xlib` 打包等仍由 `tests/b4/` 的原型 CLI 处理。
- `bootstrap/bin/` 不入库；更新 C 源后必须重跑 `tests/b4/verify-golden.sh` 并单独评审。
