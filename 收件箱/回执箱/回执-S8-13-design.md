# 回执：S8-13 `.xlib` 格式设计（只读）

- 执行位：运行时线 E5
- 性质：**只设计，不实现**
- 产出：`handoff/S8-13-xlib-format.md`
- 结论：`.xlib` 采用确定性 ZIP（Store）源码包：
  - 内容：`xnull.project`、`META-INF/xmeta.xpd`、`META-INF/hashes.xpd`、
    `src/main/x/**`、`src/main/resources/**`、`bindings/**`、可选 `native/<platform>/**`；
  - 哈希：归档全文 SHA-256 供锁引用；逐文件哈希在 `hashes.xpd` 自校验；
  - 关系：仅 `library` 产 `.xlib`；app 产可执行体、starter/pom 只产清单/元数据；
  - 本地仓库：`~/.xnull/repository` 或 `XNULL_REPO`，按 `groupId/artifactId/version/`
    安装 `.xlib`/`.xmeta`/`xnull.project`/`.sha256`，原子替换、同版本不可变；
  - 锁：`entry.sha256` = `.xlib` 全文哈希；`repository` 为逻辑仓库 id；
    本地优先且必须与锁哈希一致，`XNULL_REPO` 为离线唯一来源。
- 未实现：本卡不写代码，不改变 `xmeta`/锁/资源现有实现。
- 待确认：本地仓库默认根、`native/` 是否入 1.x、`local` 仓库 id、starter/pom
  文件集（详见设计 §11）。
