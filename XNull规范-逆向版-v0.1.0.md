# XNull 规范（逆向版）

| 项 | 值 |
| --- | --- |
| 文档版本 | 0.1.0 |
| 状态 | 现行施工依据 |
| 日期 | 2026-11-15 |
| 替代关系 | 与《XNull解决方案》第 1—10 部分冲突时以本文件为准；旧文档降为参考（语义矿场） |

## 0. 方法

本规范按「用法 → 规范 → 实现」生长，不按「体系 → 条款 → 用途」铺开：

1. 先写开发者会写的程序（`dx/LN-*.x`）和精确输出；
2. 只写让这个程序成立所需的条款；
3. 每条条款必须能指向一个场景；没有场景的条款不写；
4. 场景暴露缺陷，就地改条款，记一行变更。

禁止先写完整体系再找用途。

## 1. 程序模型

- 程序 = 一个入口文件 + 它的 `import` 闭包。
- 一个包 = **一个源文件**（v0.1 限制）。包名 = 文件名去掉 `.x`，全小写。
- 每个源文件首行是 `package <包名>`；一个文件只属于一个包。
- 入口是顶层 `static Int main()`。

## 2. 布局与装载

| 规则 | 行为 |
| --- | --- |
| 用户包 | `import p1.p2` → 入口文件所在目录的 `p1/p2.x` |
| XDK 包 | `import xdk.<pkg>` → 标准库根下的 `xdk/<pkg>.x` |
| 标准库根 | 默认 `impl/lib`，由工具链参数可覆盖；不由入口目录决定 |
| 文件名 | 全小写，与包名一致；扩展名 `.x` |
| 多文件包 | v0.1 不支持；需要时先修订本节，写清目录聚合与装载顺序 |

禁止：分层/分域目录、`base`/`full` 双面、`*_full.x`、PascalCase 文件名。

## 3. XDK 模型

- XDK 是 XNull 源码，**8 个平铺包，一包一文件**：

  ```text
  impl/lib/xdk/errors.x
  impl/lib/xdk/tasks.x
  impl/lib/xdk/sync.x
  impl/lib/xdk/runtime.x
  impl/lib/xdk/collections.x
  impl/lib/xdk/text.x
  impl/lib/xdk/sys.x
  impl/lib/xdk/net.x
  ```

- 包名固定：`xdk.errors` / `xdk.tasks` / `xdk.sync` / `xdk.runtime` / `xdk.collections` / `xdk.text` / `xdk.sys` / `xdk.net`。
- 公开 API 只来自这 8 个文件；C 原语经 `.xfb` 绑定，不以 `xdk.*` 名义暴露。
- 禁止 `xdk-raw`、`xdkc_*` 出现在公共面；禁止 `xdk.compiler`、`xdk.build` 等工具链包。
- 新增包 = 修订本节 + 登记依赖矩阵，缺一不可。

## 4. 最小子集（L0—L2）

v0.1 只覆盖已跑通的级别；L3 起逐级追加。

- 源文件：UTF-8；LF/CRLF；开头 BOM 忽略；行列从 1 开始。
- 顶层：`package`、`import`、`static Int main()`。
- 语句：表达式语句、`return`。
- 表达式：字符串/整数字面量、函数调用、`+` 拼接；`print` 为内建。
- 类型：`Int`、`String`、`Bool`。
- 类（L1 已验证）：`class` + `final` 字段 + 构造器 + 方法 + `self`。
- 其余文法暂引用第 1、2 部分，直到对应级别重写。

## 5. 诊断

- 编译失败的输出格式：`<file>:<line>:<col>: <message>`。
- 必须带源位置；禁止 `fatal:`、`panic` 或内部错误直接泄露给开发者。
- 退出码：成功 `0`；有诊断 `1`；用法错误 `2`。

## 6. 验收

- 每级一个场景：`dx/LN-*.x` + `dx/LN-*.out`，输出逐字节一致，exit 0。
- 冷跑 ≤3 秒；负例 ≤2 秒且带位置。
- 全量场景必须全绿；红必须能定位到条款。

## 7. 变更

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| 0.1.0 | 2026-11-15 | 重建。确定 XDK 源码模型（8 平铺包、一包一文件、全小写）；废止 layer/domain、base/full、`*_full`、`xdk-raw`；废止 S9-01 §2.1/§2.3「`xdk.*` 不落文件系统」的模型；确立“无场景不写条款”。 |
