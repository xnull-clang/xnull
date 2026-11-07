# BND-08 复验摘要（main 47fedb8）

- main：`47fedb8ad1659925af04a677a9e82b861c2dffcd`
- binary：`/tmp/xnull-s2-47fedb8`
- binary sha256：`46a22fee8a5523ef1a6061be2a4c73d3adb8c474762a930efa69850c56d14150`
- 结果：**FAIL**

## 关键失败

1. `factory` 名未登记：同包/跨包正例均为 `RES-101 未定义的名称 DeviceFactory`。
2. `factory F for Missing` rc=0（不可见 Target 未拒绝）。
3. `for Box<Int>` rc=0（泛型实例化 Target 未拒绝）。
4. `for Int` rc=0（非 class/struct Target 未拒绝）。
5. 跨包访问 Target 私有构造器被 `RES-101` 提前掩盖，未产生可见性诊断。
6. 三包工程 / 工厂当类型 / `new` factory / 返回约束未验（sema 未接入）。

## 通过面

- 工厂声明字段：`SYN-101` @3:5。
- codegen 发射面：`TestS2BND08Factory`、`TestS2BND08FactoryGeneric` PASS（`emitAndRunNoSema`，绕过 sema）。
