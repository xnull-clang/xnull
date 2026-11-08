# 回执：S8-14 reactor 聚合构建设计（只读）

- 执行位：运行时线 E5
- 性质：**只设计，不实现**
- 产出：`handoff/S8-14-reactor-plan.md`
- 结论：reactor 以聚合根 `pom` 的 `modules` 声明顺序为构建顺序；
  依赖图只做拓扑校验，不静默重排（S8 附录 A.3）

## 设计要点

1. **输入/模型**：根 `packaging=pom` + `modules`；模块显式 GAV/packaging；
   递归扁平化 `modules`（先模块自身，再其子模块）；禁止路径逃逸/重复坐标。
2. **模块图**：包含/parent/依赖/starter 传递边；reactor 内依赖按
   `groupId:artifactId` 解析，版本必须与 reactor 模块一致；外部依赖走锁/仓库。
3. **顺序**：`flatten` 声明顺序即构建顺序；对每条依赖/parent 边做拓扑校验，
   `pos[from] >= pos[to]` 即失败（XPD-222 建议），不自动重排；环/深度/重复失败。
4. **构建阶段**：validate 全局先行；compile/test/package 按顺序；
   pom/starter 跳过编译，library 产 `.xlib`，app 产可执行体；install 最后统一。
5. **starter**：无源码、只产清单/元数据；其依赖传递为边，构建顺序
   lib→starter→app；资源不合并给消费者。
6. **聚合产物**：各模块 `target/<artifact>-<version>.<ext>` + `.xmeta`；
   根 `target/reactor.xpd` 为聚合报告（实现定义，不安装）。
7. **失败回滚**：validate 失败不写盘；compile/test/package 失败停止后续、
   清理当前临时产物、保留已完成模块 target、不 install；install 先预检全部
   产物（同版本不可变），再原子安装，异常删除本次新建；锁仅成功后原子更新。
8. **锁/仓库**：全 reactor 一份 `xnull.lock` 在根；模块目录禁止锁；
   `--update-lock` 仅根；reactor 内模块走 workspace，外部依赖走本地/远程，
   `XNULL_REPO` 为离线唯一来源且哈希必须匹配。

## 待确认

1. 声明顺序违反拓扑时：本设计选择失败、不重排（符合 S8 A.3）；若需自动重排
   需改规范并同步插件跨模块顺序。
2. 嵌套聚合器扁平化顺序（先 pom 自身，再子模块）。
3. 一个 reactor 是否允许出现多个 app。
4. app 是否允许 `install` `.xmeta` 作审计。
5. `target/reactor.xpd` 是否纳入 S8-04 的元数据规范或保持实现定义。

本卡不写代码，不改变现有清单/锁/构建实现。
