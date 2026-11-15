# XNull Mini Compiler

新的最小 XNull 编译器。完整里程碑与能力覆盖表见 `PLAN.md`。

```sh
./build.sh
./mini --version
```

当前为 M7.3/M8.2：errors/meta/runtime/text/sys 最小面、check、简单工程模式已接通；
资源表与项目 `.xfb` 无参标量已接通；`check --json` 已可用。

## 构建缓存

`build.sh` 使用 `.cache/xnull/` 缓存：

- `xparser` AST（未改源文件时跳过解析）
- mini 生成的 C（源文件、FFI、运行时、编译器未变时跳过旧代码生成）

源码不变时 warm build 可降到几秒；源码改动仍会全量重编。
