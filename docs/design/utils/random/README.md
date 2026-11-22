# `xdk.random` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.random` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.collections` |
| 被依赖 | `xdk.uuid`、`xdk.crypto`、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

可种子 PRNG、安全随机、采样/洗牌/加权选择。

不做：加密算法（crypto）、UUID 格式（uuid）、全局随机单例。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式随机源 | Random/SecureRandom 为对象；无全局 |
| 可复现 | `Random(seed)` 明确可复现 |
| 安全分离 | SecureRandom 不复用 PRNG 状态 |
| 边界明确 | nextInt/Long/Double/bytes；越界合同错误 |
| 无 close | 无资源 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `RandomSource` | protocol | 随机源最小面 | [`RandomSource.md`](RandomSource.md) |
| `Random` | class | 可种子 PRNG/采样 | [`Random.md`](Random.md) |
| `SecureRandom` | class | 安全随机 | [`SecureRandom.md`](SecureRandom.md) |
| `WeightedChoice` | class | 加权选择 | [`WeightedChoice.md`](WeightedChoice.md) |

X：可插拔算法、并行 PRNG、硬件随机源。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：PRNG、加密随机、均匀采样、洗牌、加权选择。
- 支撑：`random*Raw`、`secureRandomBytes`。
- 依赖：`errors`、`bytes`、`collections`。

---

## 6. 场景

### R1：可复现测试

`Random(seed)`；同 seed 同序列。

### R2：安全令牌

`SecureRandom.bytes(32)`。

### R3：采样/洗牌

`sample(list, n)`、`shuffle(list)`、`WeightedChoice.pick`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局 RNG | 禁止 |
| 加密安全 | 只用 SecureRandom |
| 算法可插拔 | X |
| 并行 PRNG | X |
| 高斯分布 | 支持 `nextGaussian` |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 权重选择值语义、RandomSource 签名 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `WeightedChoice` | `@Value` | 值语义成员 |
| `RandomSource` 实现 | `@Override` | 签名校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
