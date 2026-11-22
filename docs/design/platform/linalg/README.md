# `xdk.linalg` 稠密线性代数

| 项 | 值 |
| --- | --- |
| 包 | `xdk.linalg` |
| 层 |  |
| 依赖 | `xdk.core`、`xdk.tensor` |
| 被依赖 | 应用、数值/统计工具 |
| 稳定性 | `preview` |

> 本轮只冻结 CPU、实数、双精度、稠密矩阵；不绑定 BLAS/LAPACK，不提供复数。包级计划见 [`../../NON-UI-COMPLETION.md`](../../NON-UI-COMPLETION.md)。

---

## 1. 定位

小到中等规模稠密实数线性代数：向量、矩阵、LU/QR/SVD/对称特征分解，以及求解、求逆、行列式、迹、单位阵与张量桥接。

不做：复数、稀疏矩阵、GPU、分布式、批处理、任意精度、BLAS/LAPACK 公共绑定、自动微分。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 实数双精度 | 公共数值类型只用 `Double`；不引入 `Float` 包装 |
| 不可变值对象 | `Vector`/`Matrix` 构造时复制列表；更新返回新对象 |
| 行主序 | `Matrix` 的 `List<Double>` 按行优先存放 |
| 形状显式 | 维度用 `Int`；形状不匹配是合同错误（panic） |
| 数值失败可恢复 | 奇异、非有限输入、不收敛用 `Result<T, Error>` |
| 分解工厂 | 分解对象通过 `Result` 工厂创建；构造器私有 |
| 无隐藏后端 | 公共 API 不提 BLAS/LAPACK/FFI；实现可替换 |
| 可预测顺序 | 特征值/奇异值按降序；特征向量列与值一一对应 |
| 复数后置 | 一般非对称特征值/复数分解是 X |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `Vector` | class | [`Vector.md`](Vector.md) |
| `Matrix` | class | [`Matrix.md`](Matrix.md) |
| `LuDecomposition` | class | [`LuDecomposition.md`](LuDecomposition.md) |
| `QrDecomposition` | class | [`QrDecomposition.md`](QrDecomposition.md) |
| `Svd` | class | [`Svd.md`](Svd.md) |
| `EigenDecomposition` | class | [`EigenDecomposition.md`](EigenDecomposition.md) |
| `Linalg` | class（静态算子） | [`Linalg.md`](Linalg.md) |

---

## 4. 跨类型规则

- `Vector`/`Matrix` 接受 NaN/±Inf 作为值；分解工厂要求所有元素有限，否则 `InvalidArgument`。
- 形状/长度不匹配是调用方违约：`dot`、`add`、`multiply`、`solve` 的维度检查 panic；分解工厂对非方阵/非对称等结构性输入返回 `Result`，见各类型文档。
- 奇异系统：`solve`/`solveLeastSquares` 返回 `Result` 的 `InvalidArgument`；`determinant` 对奇异矩阵返回 `0.0`。
- 分解工厂只返回不可变结果；`q/r/u/vt/eigenvectors` 返回不可变 `Matrix`/`Vector`，可安全共享。
- 矩阵索引统一 `(rowIndex, columnIndex)`；向量索引统一 `index`；不使用 `i/j/m/n` 作为公开参数名。
- 不提供原地 `set`；`Matrix.withValue` 返回新矩阵。
- [`xdk.tensor`](../tensor/README.md) 是下层：`Linalg.matrixFromTensor`/`tensorFromMatrix` 做二维桥接，`Float64` 为默认转换 dtype。
- 实数对称特征分解只保证对称输入；一般实矩阵的复特征值是 X。

---

## 5. 场景

- 小型线性系统：`Linalg.solve(matrix, rightHandSide)`；奇异时显式处理 `Err`。
- 最小二乘：`QrDecomposition.factor(matrix)` 后 `solveLeastSquares`；要求满列秩。
- 降维/诊断：`Svd.decompose` 取奇异值、秩、条件数；只做 economy 分解。
- 对称谱分析：`EigenDecomposition.ofSymmetric` 取降序特征值与特征向量。
- 张量桥接：二维 `Tensor` → `Matrix` → 求解/分解 → `Tensor`。

---

## 6. 缺口

- 复数、一般非对称特征值、复数 SVD/QR：X。
- 稀疏矩阵、迭代求解器、预条件器：X。
- BLAS/LAPACK/GPU 后端：X，经 runtime/FFI 适配，不进入公共 API。
- 批处理、分块、并行 kernel、超大矩阵：X。
- 极端量级的缩放/溢出保护、迭代 refinement、条件数估计：X。
- 秩揭示 QR、全 SVD（完整 U/V）、广义特征值：X。
- 数值稳定的高端 SVD（单边 Jacobi/Golub-Kahan）：当前基线复用对称特征分解，见 [`Svd.md`](Svd.md)。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@LinalgOp` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | LinalgAnnotationProcessor（Validate/Generate） |
| 生成物 | 算子注册、矩阵约束校验 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 算子方法 | `@LinalgOp` | 算子注册 |
| `Vector`/`Matrix`/`LuDecomposition`/`QrDecomposition`/`Svd`/`EigenDecomposition` | `@Value`/`@Builder` | 值语义/构造 |

### 声明

```x
@Target(Method)
@Retention(Runtime)
@annotation LinalgOp {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class LinalgKernels {
    @LinalgOp("solve")
    Vector solve(Matrix matrix, Vector rhs) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
