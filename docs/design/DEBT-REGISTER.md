# 2.x 债务登记表（B4 前置）

| 项 | 值 |
| --- | --- |
| 状态 | Draft for B4 owner acceptance；B4-01/B4-02 合同已冻结（待 owner 接受）；本表只分类已有债，不新增 API/包/批次 |
| 基线 | `xdk-2` @ `20a8edd6` |
| 范围 | 注解实现前已存在、至今未关闭的 1.x/2.x 旧账，以及 B4–B10 未实现批次 |
| 权威 | [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)、[`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)、[`PACKAGE-MAP.md`](PACKAGE-MAP.md) |
| 分类 | B4 阻塞 / 后续批次 / 1.x-only·post-1.0·owner accepted / BLOCKED |

本表不是完成声明。`owner accepted`、`ledger done`、`1.x out-of-scope` 都不等于 2.x 完成；`BLOCKED` 必须带依赖、证据与下一步。

## 1. 计数

| 类别 | 条数 | 说明 |
| --- | ---: | --- |
| B4 阻塞 | 2 | 合同已冻结，待 owner 接受；见 §4 |
| 后续批次 | 26 | 已明确归属 B4–B10 / P4–P8 |
| 1.x-only / post-1.0 / owner accepted | 13 | 不得冒充 2.x 完成 |
| BLOCKED | 4 | 有依赖或证据缺口，附下一步 |
| **合计** | **45** | |

## 2. B4 阻塞

> 只有直接影响 B4 纯包合同、且当前决策未冻结的条目才放这里。P4/P10 的决策已冻结，属于 B4.7/B4.8 合同回写，不冒充阻塞。

| ID | 债务描述 | 来源 / 证据 | 影响 | Owner | 目标批次 / 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| B4-01 | P11：`TensorView` 的 `offset + Σ((dim-1)*stride)` 未防 `Long` 溢出；stride 0 与 tensor README“不做广播”冲突。**冻结决定**：不做广播；非空视图中 `dim > 1` 的 stride 0 拒绝（构造 panic），`dim <= 1` 或空视图允许 stride 0；最大下标用带检查的 `Long` 乘加，任何溢出在构造时 panic，不回绕。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P11；[TensorView.md](platform/tensor/TensorView.md) §1/§3/§5/§7/§12–§14；[tensor/README.md](platform/tensor/README.md) §4/§7 | B4.6 `tensor` 与 B4.7 `linalg` 可按冻结合同签 `TensorView`；B4 仍待 owner 接受。 | XDK-PLATFORM / ARCH | B4 前：合同冻结 + 示例/反例/测试义务 + grep/门禁；owner 接受后 GO。 | 合同已冻结（待 owner 接受） |
| B4-02 | P8：`tensorDTypeByteWidth(null)` 返回 1、`geoProjectionName(null)` 返回 `"utm"`；null 与未知成员 fallback 未按函数冻结。**冻结决定**：`tensorDTypeName`/`geoProjectionName` 的 null → `"unknown"`、未知未来成员 → `"other"`；`tensorDTypeByteWidth` 的 null/未知成员 → 0（未知宽度，不是合法宽度）；`tensorDTypeFromName`/`geoProjectionFromName` 的 null/未知 → null（未找到），`"unknown"`/`"other"` 不解析成成员；不 panic，不映射到合法成员。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P8；[TensorDType.md](platform/tensor/TensorDType.md) §5/§7/§12–§14；[GeoProjection.md](platform/geo/GeoProjection.md) §5/§7/§12–§14 | B4.6 `tensor` 与 B4.8 `geo` 的 null/未知成员行为已可按冻结合同签；serial 同类项留 B8。 | XDK-PLATFORM | B4 前：合同冻结 + 示例/反例/测试义务 + grep/门禁；owner 接受后 GO。 | 合同已冻结（待 owner 接受） |

### 2.1 B4-01 / B4-02 合同冻结记录

> 状态是“合同已冻结（待 owner 接受）”，不是“债已关闭”。冻结不等于 B4 GO；关闭还需要 owner 接受与 B4.6/B4.7/B4.8 包验收证据。

**B4-01 / P11（TensorView）**

- 不做广播；`stride == 0` 不扩展数据。
- 非空视图（`elementCount > 0`）：`dim > 1` 的维度 `stride` 必须 `> 0`；`stride == 0` → `TensorView.of` panic（`TensorView.of: stride 0 on non-empty dimension`）。
- `dim == 0` 或 `dim == 1` 的维度允许 `stride == 0`；空视图（任一维为 0）接受全 0 步长，因为不存在可读取下标；与 `TensorShape.rowMajorStrides()` 对空形状返回全 0 对齐。该例外不是广播。
- `offset + Σ((dim−1)×stride)` 用带检查的 `Long` 乘加；任何中间溢出 → panic（`TensorView.of: maximum element index overflow`）；不回绕、不截断。
- 证据：[`TensorView.md`](platform/tensor/TensorView.md) §1/§3/§5/§7/§12–§14；[`tensor/README.md`](platform/tensor/README.md) §4/§7。

**B4-02 / P8（TensorDType / GeoProjection）**

- `tensorDTypeName` / `geoProjectionName`：`null` → `"unknown"`；未知未来成员 → `"other"`；不 panic，不返回合法成员名。
- `tensorDTypeByteWidth`：`null` / 未知成员 → `0`；`0` 不是合法元素宽度；不返回 1/4/8，不 panic。
- `tensorDTypeFromName` / `geoProjectionFromName`：`null` / 未知 / 空 → `null`（未找到）；`"unknown"` / `"other"` 不是成员，不得解析成合法成员。
- 谓词 `tensorDTypeIsFloatingPoint` / `tensorDTypeIsInteger` / `tensorDTypeIsBoolean`：`null` / 未知 → `false`。
- 证据：[`TensorDType.md`](platform/tensor/TensorDType.md) §5/§7/§12–§14；[`GeoProjection.md`](platform/geo/GeoProjection.md) §5/§7/§12–§14；[`platform/geo/README.md`](platform/geo/README.md) §4。
- 范围：serial 的同类 fallback 属 B8，不在本次冻结；P8 全量不在 B4-01/B4-02 关闭。

**冻结证据（本分支）**

- 分支 `debt-b4-contracts`，基线 `21c6444e`。
- `python3 src/toolchain/check_doc_naming.py docs/design` PASS；`python3 src/toolchain/check_links.py docs/design` PASS；`git diff --check` PASS。
- 合同内对 stride 0 的表述只有两类：`dim > 1` 拒绝；`dim <= 1` 或空视图允许且明确不是广播。
- 合同内 null fallback 只出现 `"unknown"`、`"other"`、0 或 null（未找到）。


## 3. 后续批次

> 这些不是 B4 阻塞。归属按 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) §4.3 与 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) 的 P 阶段。

| ID | 债务描述 | 来源 / 证据 | 影响 | Owner | 目标批次 / 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| NEXT-01 | C7：1.x 已实现 API 只完成 ledger 回写，尚未整合进 2.x core 完整合同。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) C7；[EXECUTION-PLAN.md](EXECUTION-PLAN.md) §11.1；[core/runtime/README.md](core/runtime/README.md) 等 10 个 core README | 2.x core 合同可能漏掉 1.x 已实现面；B5 前置。 | XDK-CORE / ARCH | B5 core 15 包：逐条把 ledger 并入类型合同；xdk2 + 1.x 回归绿。 | ledger done（B0）；integration OPEN |
| NEXT-02 | S7/U1：`API-SURFACE.md` 与 `utils/API-SURFACE.md` 仍是旧版广度稿，未按逐类型合同重生成。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) S7/U1；[API-SURFACE.md](API-SURFACE.md)；[utils/API-SURFACE.md](utils/API-SURFACE.md) | 旧名可能被误当实现依据；B5 合同冻结前必须只保留对照地位或重生成。 | ARCH | B5 前：从类型合同生成 API 面；旧名不进入实现；check_doc_naming + links 绿。 | OPEN（旧稿横幅已加，重生成未做） |
| NEXT-03 | N1：HTTP/2 头模型缺伪头与 `END_STREAM` 表示。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) N1；[network/net/http/README.md](network/net/http/README.md)；[Http2Session.md](network/net/http/Http2Session.md) | HTTP/2 合同不完整；HTTP/1.1 可先行，HTTP/2 不能实现。 | XDK-NET | B7/P5：补 `Http2Headers`/`endStream` 显式字段；HTTP/1.1 先验收，HTTP/2 最后验收。 | OPEN（延期 P5） |
| NEXT-04 | P6：平台适配器注入与包级 raw 自由函数两种模型未冻结。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P6；[platform/README.md](platform/README.md) | serial/device/gpu 的 raw 面可能引入全局可变驱动表；B8 前必须定一种注入模型。 | XDK-PLATFORM | B8/P6：冻结 `OsHost`/controller 参数或编译期后端选择；禁止全局可变驱动表；场景验证。 | OPEN（决策未冻结） |
| NEXT-05 | P7：平台错误分类不统一，`Unsupported` 同时表示无能力与输入不支持，超时/句柄错误有多套映射。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P7；[platform/README.md](platform/README.md) | 平台包失败通道不可预测；B8 前必须冻结统一错误映射。 | XDK-PLATFORM | B8/P6：冻结错误映射表（Unsupported/PermissionDenied/Timeout/Cancelled/DataCorrupted/InvalidArgument）；逐包场景。 | OPEN（决策未冻结） |
| NEXT-06 | P9：设备生命周期不对称：Camera 可重开，GPIO/I2C/SPI 关闭即终止；空路径判定不一致。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P9；[platform/device/README.md](platform/device/README.md)；[platform/serial/README.md](platform/serial/README.md) | 关闭/重开语义不能跨包复用；B8 前必须按包冻结。 | XDK-PLATFORM | B8/P6：一次性句柄关闭不可重开；可重开句柄显式 `reopen`；路径统一 `trim()==""`。 | OPEN（决策未冻结） |
| NEXT-07 | P10：平台文档 §10“依赖”表成环（Eigen↔Svd、Lu↔Qr、DeviceBus↔DeviceManager、GpuBuffer↔GpuFence）。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) P10；[platform/tensor/README.md](platform/tensor/README.md)；[platform/linalg/README.md](platform/linalg/README.md) | 把相关类型误读成 import DAG；B4.7 `linalg` 合同回写时必须同步，B8 清零。 | XDK-PLATFORM | B8/P6：§10 改名为“相关类型”；B4.7 落地时同步 Lu/Qr/Eigen/Svd；不新增包。 | OPEN（决定已冻结，回写未做） |
| NEXT-08 | U5：crypto 要求 `SecureRandom`，但 `Cipher/Kdf/Asymmetric` 不接收 `RandomSource`。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U5；[utils/crypto/README.md](utils/crypto/README.md)；[Cipher.md](utils/crypto/Cipher.md) | nonce/密钥来源不可注入，测试与合规边界不清；B6 前必须二选一。 | XDK-CORE | B6/P4：显式注入 `RandomSource` 或合同写明内部 `SecureRandom`；nonce 场景。 | OPEN（决策未冻结） |
| NEXT-09 | U6：`KdfAlgorithm` 是死枚举，`Kdf` 没有接收它的通用 `derive`。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U6；[Kdf.md](utils/crypto/Kdf.md)；[KdfAlgorithm.md](utils/crypto/KdfAlgorithm.md) | 枚举与 API 不一致；B6 前必须增加通用入口或删除枚举。 | XDK-CORE | B6/P4：`Kdf.derive(KdfAlgorithm,...)` 或删除 `KdfAlgorithm`；typed 方法场景。 | OPEN（决策未冻结） |
| NEXT-10 | U7：`AsymmetricAlgorithm.Sm9` 标 X，但枚举已暴露。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U7；[AsymmetricAlgorithm.md](utils/crypto/AsymmetricAlgorithm.md) | 未实现算法被枚举冒充支持；B6 前从枚举移除或实现。 | XDK-CORE | B6/P4：未实现前移除 `Sm9`；不得用 `Unsupported` 假装 K 面支持。 | OPEN（回写） |
| NEXT-11 | U8：`TarEntry` 说不做 PAX，`Tar` 说支持 PAX 长名称/长路径。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U8；[Tar.md](utils/compress/Tar.md)；[TarEntry.md](utils/compress/TarEntry.md) | 压缩包合同自相矛盾；B6 前二选一。 | XDK-CORE | B6/P4：支持 PAX 并更新 `TarEntry`，或删除 `Tar` 的 PAX 承诺；场景。 | OPEN（决策未冻结） |
| NEXT-12 | U9：`SecureRandom.nextInt(max)` 伪代码用有符号 `%`，有负值与模偏差风险。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U9；[SecureRandom.md](utils/random/SecureRandom.md)；[Random.md](utils/random/Random.md) | 有界随机分布不正确；B6/P4 必须用无符号/拒绝采样。 | XDK-CORE | B6/P4：`nextInt(max)` 非负且无模偏差；补边界/分布测试。 | OPEN（决定已冻结，实现未做） |
| NEXT-13 | U10：`MetricTimer.stop` 一处写负起点 panic，一处写时钟回退钳 0。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U10；[MetricTimer.md](utils/metrics/MetricTimer.md) | 失败语义不一致；B9/P7 metrics 不能签合同。 | XDK-SERVICES | B9/P7：仅 `startMono < 0` panic；`nowMono < startMono` 钳 0；场景。 | OPEN（决定已冻结，回写未做） |
| NEXT-14 | U11：`CompressionLevel` 对 deflate/zstd/lz4/brotli 映射不统一，`None` 语义不一。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) U11；[CompressionLevel.md](utils/compress/CompressionLevel.md)；[Zstd.md](utils/compress/Zstd.md)；[Lz4.md](utils/compress/Lz4.md)；[Brotli.md](utils/compress/Brotli.md) | 同一等级跨算法行为不可预测；B6/P4 前逐算法冻结。 | XDK-CORE | B6/P4：每个算法一张映射表；`None` 统一“不压缩/仅容器”或 Unsupported；场景。 | OPEN（决策未冻结） |
| NEXT-15 | X1：ML `BatchProcessor` 允许 pending 超上限，缺背压/拒绝策略。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) X1；[solutions/ml/README.md](solutions/ml/README.md) | 无界增长风险；B10/P8 前必须定硬上限。 | XDK-SOLUTIONS | B10/P8：硬上限 + 背压 + 拒绝策略；压力场景。 | OPEN（决策未冻结） |
| NEXT-16 | X2：`DatabasePool` 与连接可能重复 close 同一资源。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) X2；[DatabasePool.md](solutions/db/DatabasePool.md) | 关闭顺序/幂等未冻结；B10/P8 前必须定所有权。 | XDK-SOLUTIONS | B10/P8：池拥有连接；连接 close 幂等；池先停借出再排空；重复 close 无副作用。 | OPEN（决定已冻结，实现未做） |
| NEXT-17 | X3：`SseStream` 只覆盖部分写/关闭错误，缺 flush/取消/背压/编码失败面。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) X3；[SseStream.md](solutions/api/SseStream.md) | SSE 失败通道不完整；B10/P8 前补齐。 | XDK-SOLUTIONS | B10/P8：write/flush/close/取消/背压/编码失败显式返回；端到端场景。 | OPEN（决定已冻结，实现未做） |
| NEXT-18 | X4：`Agent` 启动失败可能留下半启动管线，回滚顺序未定义。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) X4；[solutions/agent/README.md](solutions/agent/README.md) | 失败不原子；B10/P8 前定启动顺序与逆序回滚。 | XDK-SOLUTIONS | B10/P8：启动顺序 + 逆序回滚；失败不返回半成品；关闭幂等。 | OPEN（决定已冻结，实现未做） |
| NEXT-19 | X5：API README 写“无注解扫描”，注解矩阵又写 `@HttpRoute` 生成路由；措辞与生成边界未统一。 | [DESIGN-CONSISTENCY.md](DESIGN-CONSISTENCY.md) X5；[solutions/api/README.md](solutions/api/README.md)；[ANNOTATION-SYSTEM.md](ANNOTATION-SYSTEM.md) | 易被误读为运行时反射/扫描；B10/P8 前统一为构建期生成显式 `ApiRoute`。 | XDK-SOLUTIONS | B10/P8：构建期生成 `ApiRoute` 注册；运行时无扫描/反射；文档统一；场景。 | OPEN（回写） |
| NEXT-20 | B4 首批纯包未实现：functional/graph/stats/net.uri/net.mime/tensor/linalg/geo，合计 8 包 / 34 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B4；[PACKAGE-MAP.md](PACKAGE-MAP.md) L4/L5/L6 | 2.x 尚无任何纯 XDK 包；B4 是 B5 的前置。 | XDK-CORE / XDK-NET / XDK-PLATFORM | B4：8 包逐包场景 + xdk2 + 1.x 回归；入口见本文件 §4。 | 未开工（受 B4-01/B4-02 约束） |
| NEXT-21 | B5 core 15 包 2.x 化未开工：foundation → io/fs/sys → log/config/cli → execution，合计 15 包 / 186 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B5；[PACKAGE-MAP.md](PACKAGE-MAP.md) L1–L3 | core 合同与 2.x 类型未落地；B5 是 B6 的前置。 | XDK-CORE / RUNTIME | B5：15 包 Verified；C7 完整整合；xdk2 + 1.x 回归绿。 | 未开工（等 B4） |
| NEXT-22 | B6 data/encoding 12 包未开工：codec/crypto/compress/random/uuid/stats/functional/graph/reflect/toml/yaml/xml，合计 12 包 / 76 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B6；[PACKAGE-MAP.md](PACKAGE-MAP.md) L4 | 数据/编码依赖闭包未落地；B6 是 B7 的前置。 | XDK-CORE | B6：12 包依赖闭包绿；Json/Base64/统计/图先验收。 | 未开工（等 B5） |
| NEXT-23 | B7 network 9 包未开工：net/uri/mime/tls/http/websocket/net.service/jwt/sql，合计 9 包 / 125 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B7；[PACKAGE-MAP.md](PACKAGE-MAP.md) L5 | 网络端到端能力未落地；B7 是 B8 的前置。 | XDK-NET | B7：9 包端到端网络场景绿；HTTP/1.1 先于 HTTP/2。 | 未开工（等 B6） |
| NEXT-24 | B8 platform 17 包未开工：os.*/gpu/tensor/linalg/geo/serial/device，合计 17 包 / 93 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B8；[PACKAGE-MAP.md](PACKAGE-MAP.md) L6 | 平台/计算能力未落地；B8 是 B9 的前置。 | XDK-PLATFORM | B8：17 包模型/只读/控制面分级绿；P6/P7/P9 决策先冻结。 | 未开工（等 B7） |
| NEXT-25 | B9 application services 12 包未开工：validate/cache/queue/schedule/event/resilience/metrics/trace/audit/terminal/i18n/test，合计 12 包 / 82 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B9；[PACKAGE-MAP.md](PACKAGE-MAP.md) L7 | 应用服务依赖闭包未落地；B9 是 B10 的前置。 | XDK-SERVICES | B9：12 包依赖闭包绿；U10 等 metrics 合同先冻结。 | 未开工（等 B8） |
| NEXT-26 | B10 solutions 9 包未开工：jsonrpc/mcp/ml/numerics/db/api/agent/accel/embedded，合计 9 包 / 122 类型。 | [EXECUTION-PLAN.md](EXECUTION-PLAN.md) §4.3/§5 B10；[PACKAGE-MAP.md](PACKAGE-MAP.md) L8 | 解决方案层未落地；B10 是 2.x 包面收口。 | XDK-SOLUTIONS | B10：9 包逐组端到端绿；X1–X5 先冻结。 | 未开工（等 B9） |


## 4. B4 入口判断

**结论：B4 仍未 GO；B4 未开工。** 入口条件已收敛为：**owner 接受本债表 + B4-01/B4-02 合同冻结后 GO**。两份合同现已冻结（见 §2.1），但仍需 owner 明确接受债表与冻结决定；本表不自行宣布 B4 GO。

B4 真正阻塞项只有两条，当前状态均为“合同已冻结（待 owner 接受）”：

1. **B4-01 / P11**：`TensorView` 的 stride 0 与 `Long` 溢出政策已冻结为“不做广播；非空视图 `dim > 1` 的 stride 0 拒绝；`dim <= 1`/空视图允许 0；最大下标 checked Long，溢出 panic”。B4.6 `tensor` 与 B4.7 `linalg` 按此合同。
2. **B4-02 / P8**：`tensorDTypeByteWidth(null)` 与 `geoProjectionName(null)` 的 null/未知成员语义已冻结为“null → `"unknown"`；未知未来成员 → `"other"`；byteWidth null/未知 → 0；FromName null/未知 → null；不 panic，不映射合法成员”。B4.6 `tensor` 与 B4.8 `geo` 按此合同。

来源表把 P11/P8 标在 P6 前后，但 B4.6/B4.8 已把 `tensor`/`geo` 提前到 B4；因此这两项必须在 B4 前冻结。这是“B4 提前实现所依赖的合同”，不是把后续批次升级成 B4 阻塞。

边界说明：

- C7 完整合同整合归 **B5**，不是 B4 阻塞；B4 只需使用 B3 已落地的 core 面。
- API-SURFACE 旧稿重生成归 **B5**，不是 B4 阻塞；B4 以逐类型合同为准。
- 注解 `Deinit`/`TypeUse` 受 S2 约束，跨包注解全限定名受编译器约束；B4 纯包不使用这些目标，故列为 BLOCKED 而非 B4 阻塞。
- N1、P6/P7/P9、U5–U11、X1–X5、B5–B10 都是后续批次或已接受债，不伪装成 B4 阻塞。
- P4（`PI()`）与 P10（“依赖”改“相关类型”）的决定已冻结，属于 B4.7/B4.8 合同回写，不阻塞 B4。
- P8 的 serial 同类 fallback 归 B8；本次只冻结 B4 需要的 `tensor`/`geo` 子集，不宣称 P8 全量关闭。

B4 入口公式：**owner 接受债表 + B4-01/B4-02 合同冻结 → GO**。当前合同冻结已完成，owner 接受未完成，所以 **B4 不 GO**。

需要 owner 决定：

- 接受本债表作为 B4 前置。
- 接受 B4-01 冻结决定：不做广播；非空视图 `dim > 1` 的 stride 0 拒绝；`dim <= 1`/空视图允许 0；checked Long 溢出 panic。
- 接受 B4-02 冻结决定：null → `"unknown"`；未知未来成员 → `"other"`；`tensorDTypeByteWidth` null/未知 → 0；FromName null/未知 → null；不 panic，不映射合法成员。
- 是否允许 B4.1–B4.5 先于 B4.6–B4.8 拆批；本表不自动拆批。

## 5. 1.x-only / post-1.0 / owner accepted

> 这些条目的共同点：1.x 已明确不含或已给 waiver。它们可以在 2.x 后续批次实现，但不能被写成 1.x 或 2.x 已完成。

| ID | 债务描述 | 来源 / 证据 | 影响 | Owner | 目标批次 / 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| X1-01 | 1.x 无 `xdk.random` 公开面；xorshift64* 桥未作为 XDK 证据。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §4；[RELEASE-NOTES-1.0.0.md](RELEASE-NOTES-1.0.0.md) §2.3 | 1.x 无随机数；不得宣称 2.x random 已完成。 | XDK-CORE | post-1.0 方向 A；2.x B6/P4：显式 seed、nextLong、nextInt、nextDouble、nextBool、shuffle。 | owner accepted（1.x 不含）；2.x pending |
| X1-02 | 1.x UTC-only，`toUTC`/`toLocal` 是恒等操作，无 `TimeZone` 源文件。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §4；[RELEASE-NOTES-1.0.0.md](RELEASE-NOTES-1.0.0.md) §2.3 | 1.x 无 DST/历史规则；不得宣称 2.x TimeZone 已完成。 | XDK-CORE | post-1.0 方向 A；2.x B5/P3：固定偏移 `FixedOffset` + `toZone` + `offsetSeconds`。 | owner accepted（1.x 不含）；2.x pending |
| X1-03 | 1.x 只有 `key=value` 的 `FileSource`，无 JSON/TOML/YAML codec。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §4；[RELEASE-NOTES-1.0.0.md](RELEASE-NOTES-1.0.0.md) §2.3 | 1.x 无标准结构化配置编解码；不得宣称 2.x codec 已完成。 | XDK-CORE | post-1.0 方向 A；2.x B6/P4：`Codec` + `JsonCodec`，对象标量映射，复杂形状按规则拒绝或展平。 | owner accepted（1.x 不含）；2.x pending |
| X1-04 | U5 真人 trial 未通过；只有 agent proxy。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §8 G2；[RELEASE-NOTES-1.0.0.md](RELEASE-NOTES-1.0.0.md) §2.1；[t0/C1-U0-U5-EVIDENCE.md](t0/C1-U0-U5-EVIDENCE.md) §U5 | 1.x 可用性未由真人确认；后续发布不得宣称 U5 PASS。 | QA / owner | post-1.0 真人 trial：干净机器 + 发布物，按 5 步模板记录，2 小时上限。 | owner waiver；human pending |
| X1-05 | 1.x tasks select/race 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/12-tasks.md](t0/12-tasks.md) 第 26/75 行 | 1.x 无 select/race；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：execution 的 Select/Future/Promise 场景。 | 1.x out-of-scope；2.x pending |
| X1-06 | 1.x `Context` 值语义是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/12-tasks.md](t0/12-tasks.md) 第 26/75 行 | 1.x 无完整 Context 值语义；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`Context` 值/传播/等待合同 + 场景。 | 1.x out-of-scope；2.x pending |
| X1-07 | 1.x 取消作用域是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/12-tasks.md](t0/12-tasks.md) 第 26/75 行 | 1.x 无结构化取消作用域；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：TaskGroup/Context 取消作用域 + 场景。 | 1.x out-of-scope；2.x pending |
| X1-08 | 1.x sync `RwLock` 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无读写锁；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`RwLock` 合同 + 并发场景。 | 1.x out-of-scope；2.x pending |
| X1-09 | 1.x sync `Semaphore` 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无信号量；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`Semaphore` 合同 + 并发场景。 | 1.x out-of-scope；2.x pending |
| X1-10 | 1.x sync `WaitGroup` 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无 WaitGroup；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`WaitGroup` 合同 + 并发场景。 | 1.x out-of-scope；2.x pending |
| X1-11 | 1.x sync `Once` 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无 Once；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`Once` 合同 + 并发场景。 | 1.x out-of-scope；2.x pending |
| X1-12 | 1.x sync `Barrier` 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无 Barrier；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：`Barrier` 合同 + 并发场景。 | 1.x out-of-scope；2.x pending |
| X1-13 | 1.x sync select 是规范非目标，未进 1.0。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §5；[t0/13-sync.md](t0/13-sync.md) 第 26/76-77 行 | 1.x 无 sync select；不得冒充 1.x 完成。 | RUNTIME | 2.x B5/P2–P3：select 语义 + 取消/超时场景。 | 1.x out-of-scope；2.x pending |


## 6. BLOCKED

> 依赖、证据、下一步必须同时存在；不得用“后续批次”代替 BLOCKED 的依赖说明。

| ID | 债务描述 | 来源 / 证据 | 影响 | Owner | 目标批次 / 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| BLK-01 | U3：官方 0.3.0 构建 blocked；tag `mini-v0.3.0`（`a36d123b`）缺 `src/bootstrap/bin/xn-s4`，官方 `./src/mini/build.sh` exit 2。替代 artifact 只证明 1.0 可升级，不是官方 0.3.0 通过。 | [MINI-1.0-SIGNOFF.md](MINI-1.0-SIGNOFF.md) §8 G1；[RELEASE-NOTES-1.0.0.md](RELEASE-NOTES-1.0.0.md) §2.2；[t0/C1-U0-U5-EVIDENCE.md](t0/C1-U0-U5-EVIDENCE.md) §U3 | 官方 0.3.0 升级路径未验证；不得宣称官方 0.3.0 已升级。 | QA / RELEASE | 修复或重建 tag 的 `xn-s4` bootstrap 后重跑官方 build；否则保持 substitute waiver 并继续标注 blocked。 | BLOCKED（缺官方 bootstrap artifact） |
| BLK-02 | 注解目标 `Deinit` 无合法挂载点：mini 不解析 `deinit` 声明语法；`@Target(Deinit)` 只作为目标名接受。 | [../../src/mini/tests/xdk2/annotations/BLOCKED.md](../../src/mini/tests/xdk2/annotations/BLOCKED.md)；[annotations/README.md](annotations/README.md) G2 | 11 个目标不能全部从源码生成；注册表 `deinit:` key 已有但无条目。 | COMPILER / S2 | S2 定义 `deinit` 声明语法；随后补 parser/AST/目标检查与正负例。 | BLOCKED（依赖 S2 语法） |
| BLK-03 | 注解目标 `TypeUse` 无显式类型使用位置语法；`@Target(TypeUse)` 只作为目标名接受。 | [../../src/mini/tests/xdk2/annotations/BLOCKED.md](../../src/mini/tests/xdk2/annotations/BLOCKED.md)；[annotations/README.md](annotations/README.md) G13 | 11 个目标不能全部从源码生成；类型使用注解无法挂载。 | COMPILER / S2 | S2 定义 type-use 位置语法；随后补 parser/AST/目标检查与正负例。 | BLOCKED（依赖 S2 语法） |
| BLK-04 | 跨包注解全限定名受限：mini 合并 AST 时丢弃被导入文件的 `Package` 节点；生成的 `typeName` 只对同包声明加当前包前缀，跨包注解按简单名解析。 | [../../src/mini/tests/xdk2/annotations_types/BLOCKED.md](../../src/mini/tests/xdk2/annotations_types/BLOCKED.md)；[annotations/README.md](annotations/README.md) §5.1 | 跨包领域注解可能同名冲突；运行时注册表 `typeName` 不能唯一标识来源。 | COMPILER | 在领域注解包（B5/B6+）前保留 `Package` 节点/全限定名；补两个包同名注解场景。 | BLOCKED（编译器合并 AST 限制） |


## 7. 非债务 / 范围外

> 本节不是债务，不计入 §1 的 45 条。UI/桌面能力是范围不变量：不实现、不排期、不立 3.x 议题。

| ID | 范围不变量 | 来源 / 证据 | 影响 | Owner | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| SCOPE-01 | UI/桌面/显示/音频/输入/电源/剪贴板/通知/托盘/文件对话框不是 XDK 能力；不得出现在包表、API 面或 `xdk2-packages.tsv`。 | [ARCHITECTURE.md](ARCHITECTURE.md) D7；[core/PLATFORM-BOUNDARY.md](core/PLATFORM-BOUNDARY.md) §1.3/§12；[COVERAGE.md](COVERAGE.md)；DESIGN-CONSISTENCY S4/P13 已清理（B4 UI scope） | 防止把已移除能力重新登记为“未来包”或债务。 | ARCH | grep 只出现“不在范围/已移除”；75 包/698 类型不变；PACKAGE-MAP/API-SURFACE 无 UI 包。 | active（范围不变量） |

## 8. 维护规则

- 新增债先登记本表，再改 `DESIGN-CONSISTENCY.md` 或对应合同；本表不复制第二份签名。
- 关闭一条债必须附：commit、命令/场景、退出码；只改状态不算关闭。
- “合同已冻结（待 owner 接受）”只表示合同文本与证据已就绪；关闭仍需 owner 接受 + 包验收 commit/场景/退出码。
- 分类只能四选一；跨类时按“是否阻塞 B4 → 是否有未解依赖 → 是否 1.x/post-1.0 已接受 → 其余后续批次”排序。
- B4 入口只在 §4 更新；B4 开工后本表仍保留，不因批次完成删除历史债。
