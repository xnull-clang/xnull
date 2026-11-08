# 回执：XDK-06 sema 回归

- **状态**：`DONE`（sema；运行时未改）
- **dumpTasks**：补 `dumpTasks() -> void` 内建签名，`import xdk.runtime` 后可正常调用；多参仍报 `TY-101`。
- **collections 方法**：`methodRet` 增加类方法查找（含继承链、泛型实参替换），`RingBuffer.isFull/isEmpty/length/push/pop/clear` 等按源码声明解析；实参个数/类型按声明检查，未登记成员仍 `TY-229`。
- **测试**：`s6_xdk06_test.go`（dumpTasks + 等价泛型 RingBuffer 夹具）、`diagpos_test.go` TY-229 触发改用 collections、`s6_01_test.go` 移除已支持的 dumpTasks 负例；红→绿 `evidence/S6-XDK06/`；sema/xfront/interp/codegen/cli 全绿。
- **边界**：工作树无 `impl/lib/xdk/collections.x`，用等价泛型类夹具复现；main 合入后走同一类方法查找路径。未改 E4/E5。
