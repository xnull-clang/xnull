# 回执：S2-E4 BND-02 / BND-03 / DISP-01（P0 三项）

- 卡片：QA FAIL 三项（`验收-S2-BND-02/03`、`验收-S2-DISP-01`）
- 提交：`44d7ef1`（pod/e4-codegen → main 合并）
- 顺序：BND-02 → BND-03/DISP-01；均先红后绿。

## 一、红 → 绿

| 项 | 红（d99c682 / 修前） | 绿（本提交） |
|---|---|---|
| BND-02 A02 多级继承 + 协议 | compiled `3 / 2 / 0 / 4 / 5 / true`（字段偏移错） | `1 / 2 / 3 / 4 / 5 / true` |
| BND-03 A03 策略结构（`P? peer = null`） | `codegen：可空类型 xn_proto_P 未支持` | compiled `7 / 7` |
| BND-03 M01-chain 子类 deinit | sema `TY-203 方法 deinit 与祖先同签名` | `dD / dB`（显式 super.deinit 只执行一次） |
| BND-03 M01-single compiled | `dD / after` | `dD / after`（保持） |
| DISP-01 A05a `c is P` | `0` | `true` |
| DISP-01 A05b `p is C` | `0` | `true` |
| DISP-01 A05c `p as? C` | `可空类型 xn_Cls_C * 未支持` | `true` |
| DISP-01 A05d `P p = c` | `TY-101 C 不能赋给 P` | `1` |

## 二、实现要点

- **BND-02 布局**：协议 vtable 指针槽向祖先传播（子类 implements 时父类同名槽），
  保证父类字段偏移在整条继承链一致；A02 恢复。
- **BND-03**：`T?`（类/协议/句柄/Bytes）用 NULL 哨兵，不再走 opt wrapper；
  可空协议字段可初始化/读取。`deinit` 显式 `super.deinit()` 时跳过自动父链，
  避免双调用；无显式调用仍自动沿父链。
- **DISP-01**：
  - `is`：类→父类/协议静态判定；协议接收者按对象 vtable 身份运行时判定。
  - `as?`：协议→类按 vtable 身份转换，失败为 NULL；可空类/协议用 NULL 哨兵。
  - sema `canAssign`：子类→祖先类、类→其实现协议（含祖先）、协议→父协议。
  - `methodOf` 纳入 `deinit`，`super.deinit()` 可解析。
- 子类 `deinit` 不再被 TY-203 覆写检查误拒（§6.4 例外）。
- 类赋值生成按目标类型转型（消除 `Base b = new Derived()` 的 C 指针告警）。

## 三、残余（非 E4）

- **解释器 deinit 作用域结束不执行**（M01-single interp）：`收件箱/回执箱/验收-S2-BND-03.md` 第 2 条，归 E3。
- 规则穷尽性/负例矩阵仍属 E2/QA1；工程模式 `xnull build` 夹具缺口未动。

## 四、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestS2BND02|TestS2BND03|TestS2DISP01' -count=1 -v
go test ./internal/codegen/... ./internal/sema/ ./internal/cli/ ./internal/interp/ -count=1
```
