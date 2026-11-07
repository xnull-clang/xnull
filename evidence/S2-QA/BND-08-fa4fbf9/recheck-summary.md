# BND-08 复验摘要（main fa4fbf9）

- main：`fa4fbf9d756882afe7e1aae52b7d9c72e90ec743`
- 包含：`1b1d12e` BND-07/08 sema
- binary：`/tmp/xnull-s2-fa4fbf9`
- 结果：**FAIL**

## 通过

- 同包 factory 私有构造器：双路径 `cam`
- Target 不可见 TY-217、泛型实参 TY-217、非类型 TY-217、protocol TY-217、可空 TY-217
- factory 非类型 TY-217、`new` factory TY-217/TY-216、字段 SYN-101

## 失败

- 跨包 factory 调私有构造器：check rc=0，run 输出 `x`
- 跨包私有成员访问：check rc=0
- 跨包公开工厂 compiled rc=1 `未登记标识符 Device`
- 工厂返回无关类型 `static Int make()`：check/run rc=0
- 工厂方法用 `self`：check rc=0，C 编译失败
- 三包工程 build 未实现
