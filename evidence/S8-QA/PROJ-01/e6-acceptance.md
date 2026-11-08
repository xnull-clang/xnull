# S8-01 自检结论（link.unsafe 解析与构建门禁）

## 结论

**main 已具备全部判据，无代码缺口**。实现由 E4 的 S7-04 提交 `3a6d4e1`（`feat(codegen): S7-04 @unsafe 构建门禁（link.unsafe）`）一次性完成；E6 本轮做独立核验，未重复落码（本地重复实现已丢弃）。

| 判据 | 实现位置 | 核验 |
|---|---|---|
| 解析工程清单 `link.unsafe` | `impl/internal/codegen/unsafe_gate.go: readLinkUnsafe`（缺省 false；重复声明/非法值报错） | `TestS704UnsafeGate*` 覆盖 |
| 未开启时构建失败 | `checkUnsafeGate`（找不到清单/未开启 → 构建错误） | `TestS704UnsafeGateRejectsDefault` PASS |
| 仅 `bindings/` 可用 | `ffi/check.go` FFI-110（路径前缀校验） | `TestS704UnsafeOnlyInBindings` PASS |
| 应用代码不可创建 `@unsafe` | 同上：注解只存在于 `.xfb` 绑定声明，语言无 `unsafe` 语法 | 同上 |
| 合同文本必填 | `ffi/check.go` FFI-110（`contract=` 为空即报错） | `TestS704UnsafeContractRequired` PASS |
| 与 S7-04 对接 | 同一门禁函数，S7 §8 / S8 §7 共用 | `TestS704UnsafeGateEnabled` PASS（构建日志输出一条记录） |

## 验证

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS704Unsafe'` | 4/4 PASS |
| `go test ./internal/codegen`（临时移出 s6_03_test.go，见下） | exit 0 |
| `go test ./internal/cli` | exit 0 |

## 缺口（他卡）

`impl/internal/codegen/s6_03_test.go`（E4/S6-03 `ef48796`）引用未定义 `InjectSys603`，codegen 测试包编译失败；核验时临时移出、未修改该文件。
