# 验收：M1-GEN-01（泛型，独立 26 项）

> **验收人**：QA1（独立复验）
> **被测**：`pod/e2-sema` @ `c969a83`（merge `131c244`）
> **判据来源**：台账 GEN-01 + `XNull解决方案-第1部分-基础语法-v3.3.0.md` §8.1–§8.4
> **独立性**：26 项用例与期望由 QA1 按条款自写（`difftest/gen01/cases.json`），未引用/未运行 E2 的 `gen01_acceptance_test.go` 作为判据；accept 项跑解释 + 编译双路径
> **复现**：`cd wt/qa-1 && bash difftest/gen01/run.sh --bin <xnull-c969a83> --root <同提交导出树>`

---

## 0. 当前判定（2026-11-07 复验，`pod/e2-sema` @ `b17e5cc`，含 `33d11ee`）：**PASS 26/26**

- 独立 26 项 harness 复跑：`GEN-QA 26/26`（exit 0）。
- G9：`static T g(T x)` → `error[RES-101]: 未定义的类型 T（§3.3/§8.1）`（sema 阶段，已修）。
- G11：`List<T> box = [local]; box.get(0)` → interp `4`、compiled `4`，均 exit 0（已修）。
- 非泛型最小例 `List<Int> box = [v]; return box.get(0)` → compiled `4`，exit 0。
- **范围**：本次基于 `pod/e2-sema@b17e5cc`（含 E2 单态化与 `b23fa42`/`c55dd81`）；main 尚未并入 E2 codegen 单态化，main 上泛型用例仍会停在「类型 T 未支持」，不能据此在 main 上签 GEN。
- 证据：`wt/qa-1/evidence/GEN-G11-reverify/`。

---

## 1. 历史判定（`c969a83`）：FAIL 24/26


E2 自测 `go test ./internal/codegen -run TestGEN01` 在本提交上 **PASS**（26/26，QA1 已复跑确认）；但 QA1 独立口径有 2 项不成立。

| # | 项 | 条款 | 实际 |
|---|---|---|---|
| 1 | **G9** 签名位置泄漏类型参数 | §8.1（L1189）`T` 只在声明它的函数签名/体内可见 | `static T g(T x)` 未被 sema 拒绝，落到 codegen：`xnull: 代码生成失败：codegen：类型 T 未支持（M4.1 范围）`；期望 sema `RES-101`。E2 的 G9 用例只在函数体位置引用 `T`，已由 sema 报 `RES-101`，未覆盖签名位置 |
| 2 | **G11** `List<T>` 构造后取元素 | §8.1（L1191）`T` 可用于局部变量与嵌套类型 | 解释路径输出 `4`；编译路径 `fatal: 容器下标越界`（exit 134） |

### G9 最小复现

```x
static T g(T x) { return x }
static Int main() { return 0 }
```

```
$ xnull build g9.x -o g9
xnull: 代码生成失败：codegen：类型 T 未支持（M4.1 范围）
```

期望：`error[RES-101]`（sema 阶段，未定义类型参数）。

### G11 最小复现

```x
static T boxFirst<T>(T v) {
    T local = v
    List<T> box = [local]
    return box.get(0)
}
static Int main() { print(boxFirst<Int>(4)); return 0 }
```

```
--interp: 4 (exit 0)
compiled: fatal: 容器下标越界 (exit 134)
```

**根因不属泛型**：同一构造在非泛型代码复现，且 main `4d1495c` 同样失败：

```x
static Int f(Int v) { List<Int> box = [v]; return box.get(0) }
static Int main() { print(f(4)); return 0 }
```

- `List<Int> box = [v]`（形参做元素）后 `box[0]` / `box.get(0)` → 越界；`[4]` 字面量正常；局部变量 `Int v = 4` 做元素正常。
- 推论：列表字面量以函数形参为元素时，生成代码的长度/索引错误。属 codegen 既有缺陷，本卡构造将其暴露。

## 通过面

其余 24 项双路径/拒绝行为均成立：显式实参、推断（直接/嵌套/字面量/冲突/未绑定）、重载、实例化、递归与 `new T()` 拒绝、跨包泛型、`is T`、`Result` 实参、`void` 拒绝、重名拒绝、约束拒绝等。

## 判定建议

- GEN-01 按 E2 的 26 项口径可判 26/26；按 QA1 独立口径 **24/26**。
- 建议董事会：①G9 开缺陷卡给前端线 E2（sema 签名位置解析）；②G11 开缺陷卡给前端线 E2 / 自举线 E4（列表字面量形参元素 codegen），**不阻塞** GEN-01 主体合入判定；③若坚持“26/26 才过门”，则本轮判 FAIL。

## 下一棒

- E2：G9 sema 修补；列表字面量形参元素（非泛型最小复现）。
- QA1：修复后复跑 `bash difftest/gen01/run.sh`。
