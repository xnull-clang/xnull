# `EntryKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum EntryKind` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

文件系统条目类型：缺失、文件、目录、符号链接、其他。

不做：权限、ACL、inode、设备号。

---

## 2. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Missing` | 路径不存在 |
| `File` | 普通文件 |
| `Directory` | 目录 |
| `Symlink` | 符号链接 |
| `Other` | 其他类型（设备/FIFO/socket 等） |

不变量：成员固定；只允许追加；`Missing` 不是失败错误，是元数据结果。

---

## 3. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `entryKindName` | 稳定小写名 | `EntryKind kind` | `String` | null → `"unknown"` |
| `entryKindFromName` | 名称解析 | `String name` | `EntryKind?` | null/未知 → null |

名称：`missing`、`file`、`directory`、`symlink`、`other`。

---

## 4. 示例与反例

正确：`metadata.kind() == EntryKind.File`。

反例：把 `Missing` 当 `Io`；把 `Symlink` 当目标类型；新增第六个成员。

---

## 5. 测试/场景义务

五个成员名称/解析；metadata 文件/目录/链接/缺失；`isFile`/`isDirectory`/`isSymlink`/`isOther` 与 kind 一致；未知名称 null。

---

## 6. XNull 伪代码

```xnull
enum EntryKind {
    Missing,
    File,
    Directory,
    Symlink,
    Other,
}

String entryKindName(EntryKind kind) {
    if kind == null { return "unknown" }
    if kind == EntryKind.Missing { return "missing" }
    if kind == EntryKind.File { return "file" }
    if kind == EntryKind.Directory { return "directory" }
    if kind == EntryKind.Symlink { return "symlink" }
    return "other"
}
```
