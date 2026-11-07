# BND-07 复验摘要（main e2f943c）

- main ref：`e2f943cf01319544c655469f9f9a81df690964d9`
- binary：`/tmp/xnull-s2-e2f943c`
- 结果：**FAIL**

## 通过

- 名称空间 `check` rc=0；编译路径 A01 `XNull\n3`、A02 `localhost\n8080`
- `new` TY-216、继承 TY-202、implements SYN-101、`instance` 只读 TY-215

## 失败

- 解释路径 A01/A02 `未定义的名称 AppInfo/Config`
- `r02_fwd`：check/interp rc=0；compiled 被“字段初始化式访问成员”间接拒绝
- 补充：`abstract singleton` rc=0；单例静态字段/方法 codegen 未支持；引用前面单例字段编译失败；`instance` 用 `rt_arc_new` 发射，未见 GC 全局根
