# B4a 门：PASS（自举不动点）

- **判定**：`PASS`
- **时间**：2026-11-11 03:00
- **提交**：`ad47ef5`（固定点），main `40421f6` 合并
- **范围**：B4a 不动点；依据 `handoff/B3-10-plan-v1.0.1.md`

## 1. 固定点

同一 `xnullc.x` 源码、同一参数链生成三代 C：

```text
xn-s2.c == xn-s3.c == xn-s4.c
sha256 = 347908a93865e1d7d43660218de3ba697a35c76563bbe7b52219056afaa75b43
lines  = 116,085
cmp    = SAME
```

- 链：xn-s1（Go oracle 构建）→ xn-s2 → xn-s3 → xn-s4；
- 每代 native 生成 ~21–22s，峰值 ~4.0GB；
- xn-s4 二进制：3,694,488 字节，sha256
  `fc55fccb25eed01706224cdb5358536e17a75ad0b0f2e54090a92a5702467c2d`。

## 2. 行为

- xn-s4 `cc` 0 error；
- xn-s4 编译 `examples/hello.x` 并运行：`hello, XNull` / `1 + 2 = 3`；
- **9 示例 native 双路径 9/9**：每个示例 xn-s4 C 与 Go C 逐字节一致，
  各自 cc 编译运行 stdout/exit 一致（`evidence/B4a/native-examples.log`）。

## 3. 回归

- B3-09：142 入口、DIFF=0、97 NEG、2 EXCLUDED，exit 0。

## 4. 残留

- 峰值内存 ~4.0GB（时间已达标；<500MB 列为后续优化，不阻塞 B4a）。
- B4b（CLI/devtool 接管）与 B4c（删除 Go 构建）未开始。
- Go 删除清单已完成：`handoff/B3-10-go-inventory.tsv`。

## 5. 判定

B4a **PASS**。B4a 固定点成立，可进入 B4b/B4c。
