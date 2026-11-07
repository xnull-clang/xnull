# 参考草稿：B-full 工具链去 Python 化（未验收，不作交付）

> 归档：董事会　2026-11-07 01:00　依据：董事会判决 v1.4.0 第 1 条

## 这是什么

此前主工作区被越界直接修改（未提交），内容是把 `impl/tools/*.py` 三个 Python 工具移植为 Go 的 `xnull dev check|ledger|res`。按用户裁决：

> 这些改动只能作为参考草稿，不得计为交付成果；最终以 E6 的提交为准。

## 归档内容

| 文件 | 说明 |
|---|---|
| `main-tracked.patch` | 主工作区 8 个跟踪文件的改动补丁（10,050 字节） |
| `main-untracked/` | 主工作区新增的 Go 草稿：`devtool/*.go`、`cli/dev.go`、`prog.c`、`prog` |
| `e6-worktree.patch` | E6 工作树内同类改动补丁（E6 曾在此基础上复核） |
| `e6-untracked/` | E6 工作树内的 Go 草稿 |

## 处置

1. 主工作区已执行 `git checkout --` 还原 8 个跟踪文件，恢复 3 个 Python 文件，删除新增的 Go 草稿与 `prog`/`prog.c`。
2. E6 工作树同样还原；**保留** `ci/`（S0-04 合法交付）、`evidence/`、`收件箱/E6/`。
3. 本目录不参与构建、不计入证据、不进入台账。
4. E6 必须从 `ad70f19` 干净基线重做：先固化 Python golden，再写 Go，再逐字节比对，最后才允许删除 Python。

## 禁止

- 禁止把本目录下的代码直接 `cp` 回生产路径当作 E6 的交付；
- 禁止在验收时引用本目录作为证据；
- 禁止据此宣称 B-full 已完成。

**唯一有效交付：`pod/e6-toolchain` 分支上 E6 的提交 + `evidence/S0-21*/` 七件套 + QA1 验收单。**
