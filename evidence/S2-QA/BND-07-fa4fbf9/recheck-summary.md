# BND-07 复验摘要（main fa4fbf9）

- main：`fa4fbf9d756882afe7e1aae52b7d9c72e90ec743`
- 包含：`1b1d12e` BND-07/08 sema
- binary：`/tmp/xnull-s2-fa4fbf9`
- 结果：**FAIL**

## 通过

- 编译路径 A01 `XNull\n3`、A02 `localhost\n8080`
- `new` TY-216、继承 TY-202、implements SYN-101
- `instance` 只读 TY-215、手动 instance TY-215、构造器 TY-201、泛型 SYN-101

## 失败

- 解释路径 A01/A02 `未定义的名称 AppInfo/Config`
- `abstract singleton` rc=0
- 单例静态字段/方法 codegen 未支持
- 引用前面单例字段编译失败；前向引用 `check` rc=0
- `instance` 用 `rt_arc_new` 发射，未见 GC 全局根
