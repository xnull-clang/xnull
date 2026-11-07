# 回执-S6-XDK08-E3

1. 改了什么：解释器新增 `vBytes` 与 `impl/internal/interp/bytes.go`——`Bytes.fromString`、`length/get/set/push/append/slice`（可变字节缓冲、引用语义）；`values.go`/`interp.go` 接入类型匹配、成员分派与静态构造。顺带修两处 text.x/解释器缺陷：十六进制字面量 `0xNN` 在解释器按 base16 解析时未剥离前缀；UTF 续字节判断 `c & 0xC0 != 0x80` 在 XNull 优先级下需显式括号（改为 `(c & 0xC0) != 0x80`）。
2. 先红后绿：红 `evidence/S6-XDK08/red.log`——`未定义的名称：Bytes`（UTF 用例与 Bytes 方法用例均失败）；绿 `green.log` 2/2 PASS：BMP+4 字节代理对解码（`5/65/233/20013/55357/56832`）、回编码 `10/65/195/128`、非法字节 `Err`、Bytes 方法矩阵。
3. 端到端：CLI `run --interp` 执行 `evidence/S6-XDK08/utf.x` 输出 `5/20013/55357/10/128`（`cli.out`），`import xdk.text` 装载源码单元后 UTF-8↔UTF-16 路径可用。
4. 回归：`go test ./internal/interp/...` ok；`go test ./... -count=1 -timeout 900s` **全绿**；`go vet ./...` 0。
5. 边界：本卡只补 `Bytes`，`Text`/`StringBuilder` 仍按既有能力；Bytes 为引用语义（赋值共享缓冲），slice 复制；编码覆盖 1–4 字节 UTF-8 与 UTF-16 代理对，孤立代理/非法序列返回 Err；编译路径的 text.x 若受 E4 codegen（Result<_,Error>/Char）限制不受本卡影响。
6. 是否越界：否（改 `impl/internal/interp/**`、`impl/lib/xdk/text.x` 的括号修正、`evidence/S6-XDK08/**`；未 push）。
