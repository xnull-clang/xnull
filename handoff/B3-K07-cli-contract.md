# B3-09 K-07 xnullc 文件输入 CLI 合同（v1.0.0）

> 接口冻结：E2（xnullc 实现）与 E4（全量门禁脚本）按本文件对接，不再各自猜参数。
> 背景：`impl/lib/b2/xparser.x` 的 AST/bundle 走 argv 触发 `ARG_MAX`；
> E5 已提供 `xdk.sys.readFileText(String) -> String`（`92211c0`）。

## 1. 调用形态

### 1.1 兼容形态（小样例，保持现状）

```bash
xnullc <entry.x> '<xnast json/text>' '<projection>' ['<bundle json>']
```

- 第 2 参：AST（xnast v1 文本/JSON）；
- 第 3 参：FFI 投影（`xfb-projection.py` 输出）；
- 第 4 参（可选）：AST bundle JSON（多文件）。

### 1.2 文件形态（大入口 / 全量门禁）

```bash
xnullc <entry.x> --ast-file <ast.path> --project '<projection>' \
  [--bundle-file <bundle.path>]
```

- `--ast-file <path>`：从文件读取 AST；存在时忽略位置参数第 2 参。
- `--bundle-file <path>`：从文件读取 bundle JSON；存在时忽略位置参数第 4 参。
- `--project <text>`：FFI 投影仍走内联（体积小，保持现状）。
- 文件内容按 UTF-8 原样读取；读取失败必须报 `readFileText` 级错误并以非 0 退出，
  不得静默当作空 AST/空 bundle。
- 文件路径可以是相对路径，按 xnullc 进程 cwd 解析。

## 2. xnullc 实现要求

1. 参数解析先扫描 `--ast-file/--bundle-file/--project`，再回退位置参数；
   两种形态可混用，但同一输入以 flag 优先。
2. 读文件用 `xdk.sys.readFileText`（E5 已实现 C/interp 双路径）。
3. 解析入口不变：AST 文本 → 现有 parser；bundle JSON → 现有 bundle 解析。
4. 错误信息至少包含：`--ast-file`/`--bundle-file` 路径与失败原因。
5. 不在 xnullc 内做 argv 切片/分片拼接（方案 C 不采用）。

## 3. 门禁脚本要求（E4）

1. 默认对**所有** Go 入口写 AST/bundle 到临时文件，走 1.2 文件形态；
   小样例也走文件形态，保证同一路径被验证。
2. 保留 `--inline-args` 开关，供兼容性回归（1.1 形态）使用。
3. 临时文件在用例结束后清理；失败时保留路径写入 results.tsv 的 note。
4. 超过 16 MiB 的 AST/bundle 必须失败并标 `K-07-LIMIT`，不得标 ARGMAX。
5. `xparser.x` 必须在全量门禁中从 `ARGMAX` 变为实际 diff/0。

## 4. 验收

- `impl/lib/b2/xparser.x` 经文件通道可生成 C，且与 Go `--emit-c` 逐字节比较
  （允许仍有语义 diff，但不再是输入通道失败）。
- 1.1/1.2 两种形态对同一小样例输出字节一致。
- 缺失文件、超限文件、非 UTF-8 文件三类错误路径有测试。
