# bootstrap/ —— 无 Go 引导（B4c-02a）

本目录保存**已冻结的 C 源**，只依赖 `cc` + `impl/runtime` 的 14 个 C 源即可构建出两个原生工具，
不调用 `go`、不依赖 /tmp 里的历史二进制。

| 文件 | 来源 | sha256（前 12 位） |
|---|---|---|
| `xn-s4.c` | B3-10 固定点（xnullc 自举第四代），116,085 行 | `347908a93865` |
| `xparser.c` | Go oracle：`XNULL_FRONTEND=go xnull build --emit-c impl/lib/b2/xparser.x` | `ff721a9c7dac` |

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

- `xparser.c` 由 Go oracle 生成一次后冻结；本目录不再需要 Go。
- `xn-s4.c` 是固定点产物（`xn-s2.c == xn-s3.c == xn-s4.c`），sha256 见上表。
- 资源表固定为空表；资源/FFI 投影、`.xlib` 打包等仍由 `tests/b4/` 的原型 CLI 处理。
- `bootstrap/bin/` 不入库；如需更新 C 源，必须在有 Go 的环境重新生成并单独评审。
