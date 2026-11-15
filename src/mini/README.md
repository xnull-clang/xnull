# XNull Mini Compiler

新的最小 XNull 编译器。完整里程碑与能力覆盖表见 `PLAN.md`。

```sh
./build.sh
./mini --version
```

当前为 M9 自举固定点阶段：

- 自身源码已能被 mini 编译，`mini1` 与 `mini2` 生成的 C 完全一致。
- 泛型函数/泛型类、插值字符串、nullable、throw、Double、位运算和静态类方法已进入最小面。
- `build.sh` 优先用已有 `bin/mini` 自编译；没有种子二进制时回退 legacy bootstrap。
- 资源表、项目 `.xfb` 无参标量、`check --json`、简单工程模式已接通。
- M9-PAR 全场景差分、默认切换、完整语言面仍未完成；M7 全量 XDK 仍需 package/FFI/Bytes/Result 面。

## 回归

```sh
for t in src/mini/tests/*.sh; do "$t"; done
```

当前 21 个回归覆盖 lex、parser、sema、codegen、class、flow、array、containers、
result、defer、m6_4、xdk、check、project、ffi、resources、object_list、selfhost、
generics、c4、m8。

## 构建

`build.sh` 的 bootstrap 路径仍保留 legacy 回退；自举路径使用 `.cache/xnull/` 的运行时库缓存，
但编译器 C 由当前 mini 直接生成。源码不变时自举构建约数秒。
