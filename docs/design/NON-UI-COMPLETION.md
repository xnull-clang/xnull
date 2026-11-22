# 非 UI 能力补齐计划

> **历史记录**：本文件记录 2026-11-21 的非 UI 补齐批次，已由 [`ARCHITECTURE.md`](ARCHITECTURE.md) 与 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) 取代。UI/desktop 在 2.x 中已移除，不是“暂缓”。

| 项 | 值 |
| --- | --- |
| 目的 | 历史批次：补齐非 UI 缺口包（已完成）；UI/desktop 已在 2.x 移除 |
| 范围 | `xdk.sql`；`xdk.gpu`/`xdk.tensor`/`xdk.linalg`/`xdk.geo`/`xdk.serial`/`xdk.device` |
| 不做 | UI/桌面相关包（不在 XDK 范围） |
| 暂缓 | X：event/reflect/graph、YAML/TOML/XML、zstd/lz4/brotli、exporter |
| 约束 | 只写设计文档；不改代码/测试/脚本；共享 README 由集成者最后修改 |

---

## 1. 为什么暂缓 UI

桌面 UI 需要大量抽象：窗口/合成器/控件树/布局/渲染/输入/无障碍/主题/DPI/生命周期。
当前 XNull 的抽象与运行时还不足以把这些设计冻结；先做不依赖 UI 抽象的包，避免把错误抽象写进规范。

2.x 已移除 UI/桌面相关包；这些不在 2.x 计划，不排期、不设计、不立 3.x 议题。

---

## 2. 本轮包

| 包 | 层 | 职责 | 依赖 |
| --- | --- | --- | --- |
| `xdk.sql` |  | 通用 SQL 连接/语句/参数/结果/事务接口 | core |
| `xdk.gpu` |  | 高层 GPU 计算：buffer/program/pipeline/command/fence | `xdk.os.gpu`、core |
| `xdk.tensor` |  | CPU 张量：shape/dtype/数据/逐元素/矩阵乘 | core |
| `xdk.linalg` |  | 向量/矩阵/分解/求解 | core、tensor |
| `xdk.geo` |  | 坐标/边界/路径/多边形/距离/投影 | core |
| `xdk.serial` |  | 串口打开/读写/刷新/枚举 | core、`xdk.os.hardware` |
| `xdk.device` |  | GPIO/I2C/SPI/相机控制面 | core、`xdk.os.hardware` |

---

## 3. 工作流

| 流 | 包 | 产物 | 状态 |
| --- | --- | --- | --- |
| N1 | SQL | `sql` 包 README + 类型文件 | 已完成 |
| N2 | GPU | `gpu` 包 README + 类型文件 | 已完成 |
| N3 | Tensor + Linalg | `tensor`、`linalg` 包 README + 类型文件 | 已完成 |
| N4 | Geo + Serial | `geo`、`serial` 包 README + 类型文件 | 已完成 |
| N5 | Device | `device` 包 README + 类型文件 | 已完成 |

并行规则：

- 每个流只写自己的目录；
- 不修改 `network/README.md`、`platform/README.md`、`COVERAGE.md`、`PLAN.md`；
- 类型名/字段/方法与本文件一致；
- 每类型 14 段；包 README 只做索引/规则/场景/缺口；
- 伪代码只用 XNull。

---

## 4. 统一约束

- 非泛型协议；泛型只用于 class/函数。
- 可阻塞方法首参 `Context`；失败 `Result<T, Error>`；无权限 `PermissionDenied`。
- 资源句柄 `close()` 幂等；`isOpen()`；不暴露裸 fd/指针。
- 字节/大小/句柄 `Long`；计数 `Int`。
- 不重复 core/net/os 已有类型。
- 不把驱动/厂商 SDK/裸设备 ioctl 放进公共 API。
- 公开参数全名；禁止 `id`/`unit`/`pad`/`to`/`q` 等缩写。

---

## 5. 集成校验

1. 包 README 与类型文件齐全；
2. 每类型 14 段；
3. `check_doc_naming.py` PASS；
4. 相对链接 0 broken；
5. 扫描非 XNull 写法；
6. 更新 `network/README.md`、`platform/README.md`、`COVERAGE.md`；
7. 无代码/脚本改动。

---

## 6. 执行结果

```text
SQL        12 类型
GPU         8 类型
Tensor      5 类型
Linalg      7 类型
Geo         6 类型
Serial      6 类型
Device      9 类型
合计       53 类型文件
14 段检查：全部通过
命名检查：PASS
相对链接：0 broken
代码/脚本改动：无
```

“已完成”指设计文档完成；`src/xdk` 尚未实现这些包。

## 7. 验收谓词

- 7 个包全部有 README 与完整类型文件；
- 类型索引 = 文件数；
- 不出现 UI/桌面类型；
- 不出现驱动/裸设备 ioctl 公共 API；
- `COVERAGE.md` 的 §4.1 明确缺包只保留 UI 相关项与 X。
