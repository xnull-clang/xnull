# S3-04（E5）：String / Text / Bytes / StringBuilder GC 化

- 卡片：S3-04 runtime（ADR-007；S3 §10）
- 基线：`cbf93bc`（E5 WIP）+ main `08553b1`（含 P0 两阶段清扫 `8e819fc`）
- 结论：四类文本/字节对象均为 GC 对象；codegen 对齐 E2 的 sema 签名（117ad9b）

## 运行时

| 类型 | 表示 | 分配 | 扫描 | 释放 |
|---|---|---|---|---|
| `String` | `rt_string`（头 + len + bytes[]） | `rt_gc_new_size` | 字节区免扫描（scan=NULL） | GC 清扫 |
| `Text` | `xrt_text`（头 + len + bytes[]） | `rt_gc_new_size` | 免扫描 | GC 清扫 |
| `Bytes` | `xrt_bytes_buf`（头 + data/len/cap） | `rt_gc_new` | 免扫描 | GC 清扫（deinit free data） |
| `StringBuilder` | `xrt_sb`（头 + len/cap/data） | `rt_gc_new` | 免扫描 | GC 清扫（deinit free data） |

- `rt_retain` / `rt_release` 对 `RT_KIND_GC` 为 no-op（过渡期 codegen 的 release 不改变生命周期）。
- `rt_gc_new_size`：变长 GC 载荷（String/Text 的字节区）。
- 弱引用：四类对象均可 `xrt_weak_bind/read`；目标死亡（清扫）前清除。
- 清扫沿用 main 的两阶段实现（P0-BND10）：deinit 阶段内存有效，随后统一释放。

新增 ABI：`xrt_text_from_string/length/code_point_count/to_string/compare_to`、
`xrt_sb_new/append_str/append_int/length/to_string`。

## codegen 对齐（E2 sema 签名 117ad9b）

- `Text` → `xrt_text *`，`StringBuilder` → `xrt_sb *`（cType/局部声明）。
- `Text.fromString/length/codePointCount/toString/compareTo`；
  `StringBuilder()/append(String|Int)/toString/length`。
- `Bytes` 补 `append(Bytes)`、`slice(start,end)`。
- 类 `scan` 现在访问 String/Text/Bytes/SB 字段（它们是 GC 引用）；句柄仍为 ARC，不扫描。
- `String` 字段的类按策略进入 GC（E2 策略更新），scan 保证字段存活。

## 先红

main（08553b1）上：
```
FAIL TestS3_04GCTextBytesSB    codegen：类型 StringBuilder 未支持
FAIL TestS3_04StringFieldScanned / TestS3_04TextSBTypes  codegen：类型 Text 未支持
```
原始输出：`evidence/S3-04-E5/red.log`。

## 后绿

- `green-tests.log`：`TestS3_04*` 3 例 PASS。
- `green-all.log`：`go test ./...` 全绿（含 S3-01 容器、S3-02 根/安全点、P0-BND10）。
- `green-build_rt.log`：运行时六套件 exit 0。
- `smoke.log`：Text/StringBuilder/Bytes 端到端输出 `x1` / `117`。

## 边界

| 项 | 状态 |
|---|---|
| Text/StringBuilder 完整方法面 | 按 E2 签名实现；未在 sema 之外的形态扩展 |
| `StringBuilder.append` 参数 | String / Int 两条路径；其他类型由 sema 约束 |
| 字符串所有权 | GC；过渡期 codegen release 为 no-op；正式 GC 生命周期随 S3-02 根/收集中途化 |
| 字节区扫描 | 全部免扫描（S3 §10） |
| 弱表原子性 | 单线程骨架（S3-06 随 B3） |

## 复现

```bash
cd impl && go test ./internal/codegen/ -run TestS3_04 -count=1 -v
cd impl && go test ./... -count=1
cd impl/runtime && sh build_rt.sh
```
