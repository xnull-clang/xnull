# S3-01：容器 GC 化（T[] / List / Map / Set）

- 卡片：S3-01（ADR-007；S3 §10）
- 基线：`main=427ce94`
- 结论：四类容器均为 GC 对象（分配头 + 长度 + 元素区），元素扫描/释放按元素种类分流；
  容器字段可持有并进入类扫描

## 先红

新增 4 例（分配种类、GC 元素、容器字段、clear 释放）在旧实现上全红：

```
FAIL TestS3_01ContainerGCAllocation   数组字面量目标类型 xn_map_s_i 不支持
FAIL TestS3_01GCContainerElements     List 元素为 GC 类型 xn_Cls_Node * 暂未支持
FAIL TestS3_01ContainerField          类 scan 未访问容器字段
FAIL TestS3_01ClearReleasesARCElements clear 未立即释放 ARC 元素
```

原始输出：`red.log`。

## 实现

**容器表示（`containers.go`）**

```c
xn_arr_<e>     { rt_header hdr; size_t len, cap; <e> *data; }
xn_set_<e>     { rt_header hdr; xn_arr_<e> *a; }
xn_map_<k>_<v> { rt_header hdr; size_t len, cap; <k> *keys; <v> *vals; }
```

- 分配：`rt_gc_new(&RT_TYPE_...)`；描述符带 `deinit`/`scan`：
  - `deinit`：释放 ARC 元素（GC 元素不动）+ `free(元素区)` + 置空；
  - `scan`：遍历引用元素（元素区或 keys/vals）；纯值元素 `scan=NULL`。
- Set 持有数组对象（scan 访问 `s->a`）；Map 直接持有 keys/vals 元素区。
- 局部容器不再 `_free`/release（GC 管理）；函数参数/返回值按指针传递。
- 字面量：`[1,2]`/`[]`/Map 空字面量分配 GC 对象；引用元素入容器后释放 +1 临时
  （Ident/Member 为借用，不释放）。

**类型与调用点**

- `cType`：`List/Set/Map` 返回 `xn_* *`；`containerElem`/`mapTypes` 去掉 `*` 解析。
- 成员调用/下标读写/for-in/`String.split` 全部改指针访问（`a->len/data`）。
- 容器字段：`isArr` 字段按 GC 引用处理——类 `scan` 访问、deinit 不 release、
  `b.xs = other` 直接赋值（不再报「需要引用语义容器」）。
- 入口 `String[] args` 包装改为指针。

**元素种类**

| 元素 | 入容器 | 移除/clear | 扫描 |
|---|---|---|---|
| 标量 | 复制 | 无动作 | 无 |
| String/ARC 类 | `rt_retain` | `rt_release` | visit（无害，保持根） |
| GC 类 | 不计数 | 不释放（GC 管理） | visit（标记） |

## 后绿

- `green-tests.log`：4 例 PASS。
- `green-all.log`：`go test ./...` 全绿（codegen/interp/sema/xnfmt/cli/ffi 等）。
- `green-build_rt.log`：运行时六套件 exit 0。
- `smoke.log`：List<Int> 求和/长度、Set 去重、Map 字面量/getOr、List<String>、
  容器字段 push/get、List<GC Node> 退出回收（node-deinit ×2）。

## 边界

| 项 | 状态 |
|---|---|
| 中途收集 / 局部容器根 | **未做**（S3-02）：生成程序仍只在退出收集；局部容器未登记根 |
| 嵌套容器（`List<List<Int>>`） | 未支持（`mangle` 拒绝指针元素） |
| struct 元素容器 | 未支持（mangle 仅 Int/Bool/String/类引用） |
| 容器值语义 | 按 S3 §10 改为引用语义（GC 对象）；旧值拷贝语义不再成立 |
| FFI 数组形参 | 既有 wrapper 支持 `T* + count`；codegen 调用路径未接（不变） |

## 复现

```bash
cd impl && go test ./internal/codegen/ -run TestS3_01 -count=1 -v
cd impl && go test ./... -count=1
cd impl/runtime && sh build_rt.sh
xnull build <容器用例>.x -o prog && ./prog
```
