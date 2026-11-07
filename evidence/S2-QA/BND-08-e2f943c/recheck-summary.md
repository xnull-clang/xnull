# BND-08 复验摘要（main e2f943c）

- main ref：`e2f943cf01319544c655469f9f9a81df690964d9`
- binary：`/tmp/xnull-s2-e2f943c`
- 结果：**FAIL**

## 通过

- 同包工厂私有构造器：双路径 `cam`
- Target 不可见/泛型实参/非类型：`TY-217` + 位置
- factory 字段：`SYN-101` + 位置
- 补充：factory 非类型、`new` factory 拒绝

## 失败

- 跨包工厂调私有构造器：check/interp/compiled 均 rc=0，输出 `x`
- 跨包私有成员：check rc=0
- 跨包公开工厂：compiled rc=1 `未登记标识符 Device`
- 补充：工厂返回无关类型、使用 `self` 未被 sema 拒绝
- 三包工程 build 未实现
