# 中文发布物料 —— V2EX / 知乎（二合一）

> 发布时机：与 HN 同窗口（周二至周四）。V2EX 发「分享创造」节点；知乎可发想法或回答「设计一门编程语言是什么体验」类问题。两处均可在 HN 讨论起来后附英文讨论链接引流。

---

## V2EX · 分享创造

**标题**：

```
XNull：一门「显式、可预测、拒绝隐式」的编程语言，8 份正式规范（中英双语）+ 可运行解释器已开源
```

**正文**：

---

做了几个月的语言设计，开源了完整规范：https://github.com/xnull-clang/xnull

XNull 的设计公理只有一条：**程序的行为必须由源码文本加规范唯一确定，不存在第三种来源。** 所有主流语言为了好写引入的「隐式」，我们全部反着做，并且每一条拒绝都写明了理由。

三个核心决策：

**1. 内存管理由编译器判定，源码零注解。**
没有所有权标注、没有 Rc/Arc、没有 weak 字段、没有 @gc。编译器按判定表（S2 §15.1）给每个对象定策略：单例→GC 全局根；数据枚举→GC；类方法捕获 self 或存在 deinit→ARC；类只有值字段且不逃逸→栈候选（逃逸后按 §14.2 提升）。混合引用图靠不变量保证：每个强引用要么增加 ARC 计数要么被 GC 追踪（S3 §78 引 S2 §15.6 不变量 1），绝不两者皆无；环在静态分析阶段检测并归入 GC（§15.1.1）。同源码 + 同版本编译器 + 同编译选项 = 同判定，确定性写进验收项（DET-01）。

**2. 语法层面不存在访问器模式。**
没有 getter/setter，没有自定义属性。公开字段就是属性访问；要算的、要校验的、要打日志的，用动词命名的方法。属性和行为的边界是语法边界，不是约定。

**3. 类继承只有静态复用，多态只走协议。**
子类不能覆写父类方法——同签名直接编译错误。动态分派只存在一种：协议类型的接收者走 vtable。「这个方法调用到底执行的是谁」这个问题，在 XNull 里看静态类型就能回答。

错误处理：Result<T,E> 是值，try 逐层传播，defer/errdefer 做清理；throw 只用于致命 panic，不展开栈，不存在异常控制流。

**现在就能跑**（tree-walking 解释器已随仓库上线）：

```
$ go run ./cmd/xnull run examples/hello.x
hello, XNull
1 + 2 = 3
```

defer/errdefer 的真实输出（`cleanup 2` 先于 `cleanup 1`——LIFO；正常路径不执行 errdefer；错误路径先 errdefer 后 defer，try 传播后错误可读）：

```
$ go run ./cmd/xnull run examples/defer-cleanup.x
A
B
C
inner cleanup
D
cleanup 2
cleanup 1
---
ok path: 5
defer: run exits
---
errdefer: error path
defer: run exits
recovered: neg
```

**诚实状态**：解释器刻意限定范围——已覆盖控制流、字符串插值、Result/try 传播、defer/errdefer LIFO（正是本次争论所系的语义）；尚未做静态类型检查、不支持对象/类（S2），用到即报「解释器不支持」诊断，绝不静默（支持范围见 impl/README.md）。一致性用例台账 101 条逐项如实标注（PASS 2），下一站是 C 运行时（执行 ARC/GC 判定、deinit 时序）。欢迎拍砖——尤其欢迎对「为什么拒绝覆写」「为什么不要访问器」的正面攻击，规范里每条拒绝决策我们都准备了辩护词。

---

## 知乎 · 想法/回答模板

**开头钩子**：

> 为什么大多数编程语言的 bug 修复，要先回答「这段代码实际执行的是谁」？我把答案写成了 8 份规范。

**正文**：可直接复用 V2EX 正文（知乎排版可加小标题），结尾改为：

> 仓库地址：https://github.com/xnull-clang/xnull （规范中英双语，中文母本 + 英译；英译为非规范文本，以中文版为准——这也是「可预测」原则的一部分：一份规范两个版本，歧义时谁是权威必须事先写死。）
>
> 最想听反驳的三个点：① 内存策略让编译器判定而非程序员表达；② 语法层面禁止访问器模式；③ 类不支持覆写、多态只走协议。规范 S1 §0.6 有一张「明确不支持」全表，每条附理由——欢迎逐条攻击。

---

## 发布检查清单（发布前逐项勾）

- [x] GitHub Topics 已生效（8 个，2026-11-06 用户确认：compiler / error-handling / language-design / memory-management / programming-language / protocols / specification / type-system）
- [ ] 社交预览图已上传（Settings → Social preview，建议 1280×640，深底白字：「XNull — Explicit. Predictable. No implicit behavior.」）
- [x] README 的「代码示例」区块已合入（2026-11-06 推送，`a5d2eae` Run It Today）
- [x] HN 帖 + 首评准备就绪（含真实运行输出与对抗性回复预案）
- [ ] 发布日全天可回复评论
