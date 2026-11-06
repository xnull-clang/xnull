# B0-02（P-10）摘要

## 一句话

`xnull build` 的 C 清单从 4 源扩到 8 源（新增 `xrt_abi.c` + 3 个 `rt_std_*.c`），`LinkArgs`（`-l/-L`，去重 + 升序）注入在全部目标文件之后；含 ABI/STD 的样例在旧清单下链接失败、新清单下链接并运行通过，`xnull build` 产物内实测 48 个 `xrt_`/`xdkc_` 符号。

## 数据

| 项 | 值 |
| --- | --- |
| 基线 | `81ec33d` |
| 单元级红→绿 | `red.txt`（缺 4 源）→ `green.txt`（PASS） |
| 链接级红→绿 | `red-link.txt`（undefined `_xrt_runtime_init`/`_xrt_safepoint`/`_xdkc_now_mono_ms`）→ `run.out` §2 通过 |
| 样例 | `hello.x` + `-lm -L/usr/lib`，exit 0，输出与解释一致 |
| 产物 ABI/STD 符号 | 48 |
| 回归 | vet 0 / codegen+cli 0 / 全量 0 / build_rt 0 |
| 干净 clone | `clone.txt` |

## 自动驱动

`evidence/B0-02/run.sh`：红→绿→样例→回归一条命令，exit 0。

## 本轮追加：B0-06 阻塞 #3（`fileOpenWrite`）

B0-06 验收指出「`fileOpenWrite` 在所有绑定/C 层零命中，无它则写文件不可完成」。已按 red-first 补齐：`sys.xfb` 入口（`xdkc_file_open_write`）+ `rt_std_sys.c` 实现（`fopen(path,"wb")`）+ 阻塞分类清单一行 + `ffi/xdk_write_test.go`（生成包装、写→关→读回逐字节比对）。红：`red-fileopenwrite.txt`；绿：`green-fileopenwrite.txt`。

## 未覆盖

1. `rt_std_*.c` 未按 import 闭包裁剪（条件 1；依赖 B0-03 的跨包 import）。
2. 生成代码仍走 `rt.h`/`rt_*`，`xrt_abi.c` 已链接未调用（条件 2；属 P-08/M4.4a）。
3. 无构建缓存（条件 4 不适用）。
