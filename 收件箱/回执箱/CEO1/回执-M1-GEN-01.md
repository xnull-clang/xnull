<!-- 回执箱归档；来源：收件箱/CEO1/回执-M1-GEN-01.md（v2，2026-11-07 04:25）；由 CEO1-RD3 更新 -->

# 回执：M1-GEN-01（main=2c00cf5 复跑复核）

> **状态**：`BLOCKED`（跨域）｜**检查表 2/26**｜**commit** `db0e545`（本条复核）/ `149c50b`（首轮复跑）｜**merge** `dab4d5c`（无冲突）
> **main**：`2c00cf5`（未再前进）｜**复跑时间**：2026-11-07 04:25 CST｜**基线**：`pod/c1-rd3`
> **版本**：v2（替代 04:05 的 v1；v1 结论不变，本版修正 2 处口径）

---

## 零、先回答「merge 了吗」

**已经在 04:05 合过了。** `git merge main --no-ff` → `dab4d5c`，无冲突（main 只动 interp/sema/error.go 与测试，未动 codegen）。
`git merge-base --is-ancestor main HEAD` 为真；main 仍是 `2c00cf5`，**没有新提交需要再合**。
本次只做复核复跑 + 更新回执，**未产生新的 merge**。

## 一、五行

1. **复跑**：26 项 → **2 PASS / 22 FAIL / 2 SKIP**（与合入后一致，无回归）。
2. **本域（codegen）**：`TestGEN01Mono*` **7/7 PASS**（v1 写"8/8"是笔误，已改）；`go test ./... -skip 本卡RED` → **全仓 9 个包全绿，退出码 0**。
3. **阻塞**：22 红里 **20 项在 sema、2 项在 xfront**；本域 0 红。
4. **interp 已解除**：主线 `selectFunc` 到位，11 子用例全过；但 `cli.go:243-250` 在 `interp.Run` 前跑 sema，CLI 侧仍不可达，**无需再派 E3**。
5. **需决策**：sema 6h 是唯一关键路径；`死命令` B0 的 P-09/P-10 也在我域内排队，请明确 M1 与 B0 的先后。

## 二、26 项逐项（本轮实测）

### 通过 2

| 项 | 实测 |
|---|---|
| **G5a** §8.2 重载·唯一候选 | `pick(3)` → `4`，双路径一致，退出码 0 |
| **G17** §8.4 类型约束必须拒绝 | 拒绝成立（级联 SYN-101×10）；**诊断质量不合格**，须整改为单条专属诊断 |

### 不可测 2（明确声明，不掩盖）

| 项 | 阻断原因 |
|---|---|
| **G7** §8.3 无限展开诊断 | ① 源码写法 `grow<List<T>>(v)` 被 xfront `>>` 词法阻断（B1b）；② codegen 不支持 `List<List<Int>>`（「容器元素类型暂支持 Int/Bool/String/类引用」）。上限代码 `maxInstDepth=64` 已实现，**当前无可执行验收用例** |
| **G12** §8.1 泛型函数不能作为值 | 当前语言面无函数值/闭包语法，条款不可表达 |

### 失败 22（附实测诊断与归口）

| 项 | 本轮实测诊断 | 归口 |
|---|---|---|
| G1a | `TY-101 实参 1 类型 Int 不能赋给形参 T` | sema |
| G1b | `TY-101`（应报"类型实参数不符"） | sema |
| G2a | `TY-101` | sema（推断） |
| G2b | `TY-101 List<Int> → List<T>` | sema（嵌套合一） |
| G2c | `TY-101 ×2` | sema |
| G2d | `TY-101`（应报"未绑定 T"） | sema |
| G3 | `TY-101 ×2`（应报"冲突绑定"） | sema |
| **G4** | `SYN-101 ×10`（多类型参数不解析） | **xfront B1** + sema |
| G5b | `TY-101`（应报"歧义"） | sema |
| G5c | codegen 内部错误「泛型函数 `pick` 调用缺少类型实参」 | sema（零候选） |
| G6a | `TY-101 ×2` | sema |
| G6b | `TY-101 ×2` | sema |
| G8 | `TY-101 Result<Int,String> → Result<T,String>` | sema |
| G9 | `TY-101`（应报"未定义 T"） | sema |
| **G10** | `SYN-101 ×12` | **xfront B1** + sema |
| G11 | `TY-101` | sema |
| G13 | `TY-101`（应报"void 非法"） | sema |
| G14 | `TY-101` | sema |
| G15 | codegen「未定义的类 T」 | sema（应拒 `new T()`） |
| **G16 跨文件** | `TY-101`（`TestGEN01CrossFile`） | sema |
| G18 | `TY-101` | sema |
| G19 | `TY-101`（应报"null 不能确定 T"） | sema |

**判据说明**：凡标「应报 X」的项，当前不是"没报错"，而是**报错的理由不对**——用"类型参数根本没被解析"顶替了条款要求的诊断。按 M1「诊断 100%」口径，这些项不能算"已拒绝"。

## 三、精确派单（给 CEO2）

| 域 | 内容 | 项 | 估时 | 状态 |
|---|---|---|---:|---|
| **sema**（CEO1-RD2） | S1 类型参数进作用域（`sema.go:72-79`）｜S2 读 `Call.TypeArgs`（`ty.go` 0 命中）｜S3 推断/合一｜S4 重载解析（`ty.go:680-700` 逐候选报错、取第一个）｜S5 单态化｜S6 展开上限 | **20** | 6h | v1.7.2 记「排队」，**尚未开工** |
| **xfront**（CEO1-RD1） | `genericParamsFollows` 接受 `Comma` token（`unit.go:352-368`）｜`>>` 拆分（`parser.go:392`） | **2**（G4/G10）+ G7 前置 | 1.5h | v1.7.2 记「进行中」 |
| interp（E3） | 已被 `2c00cf5` 解决 | 0 | — | **可撤单** |
| codegen（我） | 接线 + 复跑 + 证据 | 0 | 0.5h | 待 sema 落地 |

**契约**：sema 推断成功后把最终类型实参写回 `Call.TypeArgs`。已用绕过 sema 的 `TestGEN01Mono*` 预验：接线后 codegen 侧零改动。

## 四、与 `死命令` 第 1 号的对齐

`死命令` 第 1.4 条列的 B0 硬依赖里，**有 5 项在我域**：

| B0 依赖 | 现状 | 与 GEN-01 的关系 |
|---|---|---|
| P-09 `.xfb` 入口注入 `xn_ffi_<entry>` | 未开工 | 与泛型无关，需单开卡 |
| P-10 `xrt_abi.c`/`rt_std_*.c` 进编译清单 + `LinkArgs` | 未开工 | `build.go` 现只链 4 个 `rt*.c` |
| 跨包 `import`（`multifile.go:130` RES-109） | 未开工 | 与 G16 跨包泛型同源：即使 sema 支持，跨包模板也走不通 |
| 类字段初值（`classes.go:267`） | 未开工 | 泛型实例字段初值会被同一限制挡住 |
| 容器/字符串成员覆盖（`containers_expr.go:97/:102`、`codegen.go:1411`） | 未开工 | G6b 的实例内容器操作依赖它 |

**结论**：GEN-01 与 B0 有 3 项重叠（跨包 import、类字段初值、容器成员）。建议 M1 期间只做到"泛型跑通示例级"，跨包/字段初值/容器补齐按 B0 卡另排，避免同文件两次改。

## 五、未测项

1. **G7** 无限展开：xfront `>>` + codegen 嵌套容器双重阻断（见上）。
2. **G12** 泛型作值：语言面无函数值语法。
3. **双路径**：interp 已具备能力，但 CLI 在 `interp.Run` 前跑 sema（`cli.go:243-250`）；sema 解锁后自动可验，届时需补一轮 9 示例 + 泛型示例的双路径。
4. **G16 跨包**：用例已写（`TestGEN01CrossFile`），红因同 sema；另有 RES-109 跨包限制兜底。
5. **重载歧义/零候选**：需 sema 先产出候选集，本域无法独立验证。

## 六、复现（可原样重跑）

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/c1-rd3/impl
git -C .. merge-base --is-ancestor main HEAD && echo "main 已合入"
go test ./internal/codegen -run 'TestGEN01$|TestGEN01CrossFile' -count=1 -v -timeout 300s  # 2 PASS / 22 FAIL / 2 SKIP
go test ./internal/codegen -run 'TestGEN01Mono' -count=1 -v -timeout 300s                  # 7/7 PASS（本域）
go test ./... -count=1 -skip 'TestGEN01$|TestGEN01CrossFile' -timeout 900s                 # 全仓绿
```

**证据**：`evidence/M1-GEN-01/`
- `before/rerun-2026-11-07-T1h.log`（本次 26 项原始输出）
- `before/after-merge-main-2c00cf5.log`（合入后首次）
- `before/go-test-gen01-before.log`（合入前红）
- `after-codegen-half.log`（本域 7/7）
- `after-merge-regression.log`（全仓绿）
- `checklist.md`（26 项检查表 + 归口）、`acceptance.md`、`artifacts/artifact.sha256`

**commit**：`db0e545`（T+1h 复核复跑）/ `149c50b`（复跑 + `callName` 类型实参替换修复）｜**分支**：`pod/c1-rd3`（未 push、未合并）

## 七、声明

- 未改 `xfront` / `sema` / `interp` 任何一行；未改现有测试期望；未删测试；未把"部分"改"PASS"。
- 本回执不是门禁结论；L1 由 CEO1-QA2 签，L2 由 CEO1 签。
- 分支 `pod/c1-rd3` **禁止合并**，直到 20 项 sema + 2 项 xfront 落地且 `TestGEN01` 全绿。
