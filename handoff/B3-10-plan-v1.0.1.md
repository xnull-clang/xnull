# B3-10 B4 前置计划（v1.0.1）

> 替代 v1.0.0。变更：xn-s1 由 **解释执行的 xnullc 自编译**生成，不依赖 Go codegen
> （Go oracle 对 xnullc.x 的容器 Member 表达式仍不支持）。
> 依据：`handoff/B3-10-plan.md` v1.0.0、ADR-001/009。

## 1. 固定点链

```text
xnullc.x --(interp)--> xnullc.self.c --cc--> xn-s1
xnullc.x --(xn-s1)----> xn-s2.c ------cc--> xn-s2
xnullc.x --(xn-s2)----> xn-s3.c ------cc--> xn-s3
xnullc.x --(xn-s3)----> xn-s4.c ------cc--> xn-s4
```

- xn-s1 是解释器生成的 C 编译产物；允许比 xn-s2 慢。
- xn-s2 起为原生自举编译器。

## 2. 输入与命令

### 2.1 自编译输入

```bash
# AST / bundle / FFI 投影（bundle 含 xdk.sys 闭包）
xnull --emit-ast-bundle impl/lib/b3/xnullc.x > /tmp/xnullc.bundle.json
xnast --ast impl/lib/b3/xnullc.x > /tmp/xnullc.ast
python3 tests/b3/xfb-projection.py . > /tmp/xnullc.proj
```

### 2.2 xn-s1（解释执行）

```bash
xnull run --interp impl/lib/b3/xnullc.x -- impl/lib/b3/xnullc.x \
  --ast-file /tmp/xnullc.ast --project "$(cat /tmp/xnullc.proj)" \
  --bundle-file /tmp/xnullc.bundle.json > /tmp/xnullc.self.c
cc -std=c11 -O2 -pthread -I impl/runtime -o /tmp/xn-s1 /tmp/xnullc.self.c \
  <runtime sources>
```

### 2.3 xn-s2/xn-s3

```bash
/tmp/xn-s1 impl/lib/b3/xnullc.x --ast-file /tmp/xnullc.ast \
  --project "$(cat /tmp/xnullc.proj)" --bundle-file /tmp/xnullc.bundle.json > /tmp/xn-s2.c
cc ... -o /tmp/xn-s2 /tmp/xn-s2.c
# 同理 xn-s2 -> xn-s3 -> xn-s4
```

## 3. 判定

1. **C 产物**：`/tmp/xn-s2.c` 与 `/tmp/xn-s3.c` 逐字节一致；xn-s3→xn-s4 亦一致。
2. **二进制**：若构建可复现，`sha256(xn-s2)==sha256(xn-s3)`；否则记录差异原因，
   以 C 产物 + 行为一致为准，二进制一致降为 B4a 改进项。
3. **行为**：xn-s1/s2/s3 对 9 示例、B3-09 全量入口、98 负例（前端拒绝）行为一致；
   xn-s2 编译自身得到 xn-s3 可运行。
4. **Go 删除清单**：`handoff/B3-10-go-inventory.tsv` 完成，B4a 可开工。

## 4. 卡

| 卡 | 内容 |
|---|---|
| B3-10-01 | 生成 xnullc AST/bundle/proj；interp 自编译 → xn-s1；验证 xn-s1 可编译 hello |
| B3-10-02 | xn-s1 编译 xnullc → xn-s2；验证 xn-s2 可编译 hello/text |
| B3-10-03 | xn-s2 编译 xnullc → xn-s3；C 产物对比 |
| B3-10-04 | xn-s3 编译 xnullc → xn-s4；多一代对比 |
| B3-10-05 | Go 删除清单（keep/replace/delete） |

## 5. 风险

- xnullc 自编译输入 3.9MB bundle/3.8MB AST，文件通道可承载；解释器耗时高。
- xnullc 的 FFI 依赖 `xdk.sys`，投影须包含根 `bindings/xdk/sys.xfb`（用 repo root 投影）。
- 自编译 C 需要完整 runtime 源（含 `rt_std_sys.c` 等）。
- Go codegen 不能作为 xn-s1 生成器；B4c 删除 Go 构建前，B3-10 只依赖解释器 + cc。
