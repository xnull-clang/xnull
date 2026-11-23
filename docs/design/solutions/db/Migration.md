# `Migration`

| 项 | 值 |
| --- | --- |
| 类型 | `class Migration` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `SqlStatement`、`Checksum`、`ChecksumAlgorithm`、`Bytes` |
| 被依赖 | [`MigrationRunner`](MigrationRunner.md) |

> 实现状态：implemented (M6.6，内存驱动验证)；校验和由本地 FNV-1a 64 位实现，不依赖 crypto 包。

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

不可变迁移定义：点分十进制版本、可读名称、按序执行的 up 语句、可选按逆序执行的 down 语句、稳定校验和。

用于 [`MigrationRunner`](MigrationRunner.md) 排序、应用、回滚、审计与漂移检测。

不做：读写数据库、执行语句、生成 SQL、schema diff、占位符替换、回调、分支/合并图、自动回滚生成、加密签名。

---

## 2. 设计逻辑

- 迁移是**值**：版本、名称、语句列表、校验和构造后不可变；列表构造时复制，读取返回副本。
- 版本采用点分十进制段（如 `1`、`1.2`、`2026.11.22`）：
  - 每段只含 ASCII 数字；无前导零（`0` 本身除外）；每段 1..18 位；最多 16 段；总长 1..64。
  - 排序逐段进行：先比段数，再逐段按数值比较；不做 SemVer 预发布/构建元数据语义。
  - 不提供任意字符串版本；避免 `"10" < "2"` 的字典序错误和不可判定顺序。
- 名称是给人看的短标签：非空、单行、≤200；进入历史表与诊断，不得放秘密。
- `up` 至少一条语句；空迁移没有意义，且会掩盖“漏写脚本”。`down` 可为空，表示不可回滚；`MigrationRunner.rollback*` 在预检阶段对缺失 down 返回 `Unsupported`，不会执行一半再失败。
- 语句顺序即执行顺序；`down` 由调用方按“逆操作”顺序写好，runner 只按列表顺序执行，不再反转单个迁移内的语句。多个迁移的回滚顺序由 runner 反转。
- 校验和覆盖：
  - 版本字符串、名称；
  - 每条 up 语句的 SQL 文本，按顺序；
  - 每条 down 语句的 SQL 文本，按顺序；
  - 使用 `ChecksumAlgorithm.Fnv1a64` 对 UTF-8 规范化文本计算。
  - **不覆盖**参数值、参数名、`SqlOptions`、驱动名、数据库名、目标 schema。迁移脚本应使用固定 SQL；参数化迁移的校验和只保证文本稳定。
  - 校验和用于发现“已应用迁移被改写”，不是加密完整性/防篡改机制；FNV 可碰撞。
- `checksum` 是 64 位 bit pattern，按 `Long` 保存；可能为负，历史表用有符号 `BIGINT` 保存并按位相等比较；不要格式化为无符号十进制再解析。
- 不持有连接/事务/驱动；无 close；可跨任务只读共享。
- `describe` 只输出版本、名称、语句数、校验和；不输出 SQL 正文/参数值。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_version` | `String` | final | 点分十进制；1..64；合法段 |
| `_versionSegments` | `List<String>` | final | 构造时复制；每段无前导零 |
| `_name` | `String` | final | 非空、单行、≤200 |
| `_upStatements` | `List<SqlStatement>` | final | 构造时复制；非空；元素非 null |
| `_downStatements` | `List<SqlStatement>` | final | 构造时复制；可为空；元素非 null |
| `_checksum` | `Long` | final | FNV-1a 64 位；可为负 |

不变量：

- `_version` 非 null；`_versionSegments` 非空；每段为 1..18 位 ASCII 数字，无前导零；段数 ≤16。
- `_name` 非 null；trim 后非空；长度 ≤200；不含换行/回车/制表。
- `_upStatements` 非 null、非空；元素非 null。
- `_downStatements` 非 null；元素非 null；可为空。
- `_checksum` 由构造时的版本/名称/语句文本决定；同一输入得到同一值；构造后不变。
- 对象不可变；`upStatements()`/`downStatements()` 返回副本。
- 不持有连接/事务/驱动/结果。

---

## 4. 生命周期

由公开构造器创建；构造后不可变；无 close；GC 管理内存；可跨任务只读共享。

- 一个 `Migration` 可被多个 `MigrationRunner` 调用复用；runner 不修改它。
- 修改迁移定义必须创建新对象；已应用迁移的校验和变化应由 `MigrationRunner.validate` 报错，而不是静默覆盖。
- 语句对象不可变，迁移只持有引用；调用方不能通过迁移修改语句。
- 长生命周期迁移列表由应用持有；建议在启动时构建一次。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Migration(String version, String name, List<SqlStatement> upStatements)` | version/name/upStatements | 见 §3；up 非空 | 非法 → panic |
| `Migration(String version, String name, List<SqlStatement> upStatements, List<SqlStatement> downStatements)` | 四个字段 | 见 §3；down 可空 | 非法 → panic |

构造复制 `upStatements`/`downStatements`；调用方之后修改原列表不影响迁移。构造时计算校验和，不执行 I/O。

非法版本/空名称/空 up/null 元素/超长名称/多行名称均 panic；这些是构建期配置错误，不返回 `Result`。

---

## 6. 字段表

见 §3；字段私有。

`_versionSegments` 是排序缓存，不对外暴露；调用方通过 `version()`/`compareTo` 使用。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `version` | 版本字符串 | 无 | `String` | 无 | 规范化输入 |
| `name` | 名称 | 无 | `String` | 无 | 单行 |
| `upStatements` | up 快照 | 无 | `List<SqlStatement>` | 无 | 列表副本 |
| `downStatements` | down 快照 | 无 | `List<SqlStatement>` | 无 | 列表副本 |
| `upStatementCount` | up 数 | 无 | `Int` | 无 | ≥1 |
| `downStatementCount` | down 数 | 无 | `Int` | 无 | ≥0 |
| `hasRollback` | 是否可回滚 | 无 | `Bool` | 无 | down 非空 |
| `checksum` | 校验和 | 无 | `Long` | 无 | FNV-1a 64 位；可为负 |
| `compareTo` | 版本比较 | `Migration other` | `Int` | null → panic | -1/0/1 |
| `compareVersion` | 独立版本比较 | `String leftVersion, String rightVersion` | `Int` | 非法/null → panic | 静态；-1/0/1 |
| `equals` | 值相等 | `Migration other` | `Bool` | null → false | 版本/名称/语句/校验和 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 SQL/参数值 |

详细契约：

- `version()` 返回构造时的版本字符串；因为前导零被拒绝，它与规范化形式一致。
- `upStatements()`/`downStatements()` 返回独立列表；元素 `SqlStatement` 不可变，无需深拷贝。修改副本不影响迁移。
- `hasRollback()` 等价于 `downStatementCount() > 0`；空 down 表示 runner 拒绝回滚该迁移。
- `checksum()` 返回构造时计算的值；不重新计算，不随外部修改变化（列表已复制，语句不可变）。
- `compareTo(other)`：`other == null` panic；等价于 `compareVersion(_version, other.version())`；`-1` 表示当前更早，`1` 表示更晚，`0` 表示同版本。
- `compareVersion(left, right)`：两参数非 null、版本合法；逐段比较，段数多者更大；同段按数值（先长度后逐位）比较；返回 -1/0/1。非法版本 panic。
- `equals(other)`：null 返回 false；比较版本、名称、up/down 列表顺序与元素 `SqlStatement.equals`，以及校验和。校验和是派生值，理论上可省略，但保留以发现实现不一致。
- `describe()` 形如 `"Migration(version=2026.11.22 name=add_users up=3 down=1 checksum=123456789)"`；名称进入输出，调用方不得把秘密放进名称；不输出 SQL 正文/参数值。
- 不提供 `with*`：迁移定义应整体替换，避免“只改 down 不改 checksum”的不一致。
- 不提供 `parse`/`fromText`：版本/名称由调用方显式构造；不从文件名猜测。
- 不提供 `apply`/`rollback`：执行归 `MigrationRunner`。

---

## 8. 使用的技术

- 不可变值对象；
- 防御性复制列表；
- 点分十进制版本解析与比较；
- FNV-1a 64 位校验和；
- 单行诊断；
- 无 I/O、无反射、无 SQL 生成。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Long、Bool、List；
- 运行时：`split(String,String)`、`substring(Int,Int)`、`trim(String)`、`String.indexOf`、`str(Int)`、`str(Long)`；
- 接口：`SqlStatement`、`Checksum`、`ChecksumAlgorithm`、`Bytes`、`Error`。

---

## 10. 依赖的特性/接口/类

[`SqlStatement`](../../network/sql/SqlStatement.md)、[`Checksum`](../../utils/crypto/Checksum.md)、[`ChecksumAlgorithm`](../../utils/crypto/ChecksumAlgorithm.md)、[`Bytes`](../../core/bytes/Bytes.md)。被 [`MigrationRunner`](MigrationRunner.md) 消费。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- 构造复制两个语句列表；`upStatements()`/`downStatements()` 再复制。
- `SqlStatement` 不可变，迁移只持有引用；无需深拷贝。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希；不推荐作 `Map` 键（列表比较成本高）。
- 排序：`compareTo` 按版本；同版本不同名称不比较名称，视为相等排序位置；runner 要求版本唯一。
- 校验和不是安全边界；不要用它做签名/授权判断。

---

## 12. 示例与反例

正确：

```text
Migration migration = new Migration(
    "2026.11.22",
    "add_user_email",
    [
        new SqlStatement("alter table users add column email varchar(320)"),
        new SqlStatement("create index users_email_idx on users(email)")
    ],
    [
        new SqlStatement("drop index users_email_idx"),
        new SqlStatement("alter table users drop column email")
    ]
)

Int order = migration.compareTo(previous)
Long checksum = migration.checksum()
```

反例：

- 版本 `"1.02"` 或 `"v1"`；无前导零、仅数字段。
- `up` 为空；迁移没有效果，应删除或合并。
- `down` 只写一半，或顺序写反；runner 按列表顺序执行 down。
- 修改已应用迁移的 SQL 后期望自动更新校验和；应报错并要求显式修复。
- 把口令/令牌放进迁移名称；名称进入历史表/诊断。
- 用 `checksum()` 做安全签名；FNV 不是加密哈希。
- 用 `"10"` 与 `"2"` 字符串比较排序；使用 `compareTo`/`compareVersion`。
- 把 `downStatements()` 返回列表修改后期望改变迁移；返回副本。
- 在一个 `Migration` 中放非事务性 DDL 并期望原子回滚；runner 只能尽力。

---

## 13. 测试/场景义务

- 版本合法：单段/多段/最大 16 段/每段 18 位/`0`；非法：空、前导零、非数字、空段、17 段、19 位、超长、null；
- 版本比较：`1 < 1.1 < 1.2 < 2 < 10`；同段长度/逐位；段数；相等；非法 panic；
- 名称合法/空/空白/超长/多行/tab；
- up null/空/含 null panic；down null/含 null panic；down 空允许；
- 构造复制列表独立；`upStatements()`/`downStatements()` 副本独立；
- 校验和稳定性：同一内容两次构造相等；版本/名称/up/down 任一变化改变；参数值变化不改变（文档义务）；
- `hasRollback`；`upStatementCount`/`downStatementCount`；
- `compareTo` null panic；`equals` 顺序/字段；`describe` 不含 SQL/参数值；
- checksum 为负时历史表读写往返一致；
- Unicode 名称/SQL；长 SQL；
- 迁移跨任务只读共享；`MigrationRunner` 不修改迁移。

---

## 14. XNull 伪代码

```xnull
class Migration {
    final String _version
    final List<String> _versionSegments
    final String _name
    final List<SqlStatement> _upStatements
    final List<SqlStatement> _downStatements
    final Long _checksum

    Migration(String version, String name, List<SqlStatement> upStatements) {
        List<String> segments = parseVersionSegments(version)
        validateName(name)
        List<SqlStatement> upCopy = copyStatements(upStatements, true)
        List<SqlStatement> downCopy = []
        Long computed = computeChecksum(version, name, upCopy, downCopy)
        _version = version
        _versionSegments = segments
        _name = name
        _upStatements = upCopy
        _downStatements = downCopy
        _checksum = computed
    }

    Migration(String version, String name, List<SqlStatement> upStatements,
              List<SqlStatement> downStatements) {
        List<String> segments = parseVersionSegments(version)
        validateName(name)
        List<SqlStatement> upCopy = copyStatements(upStatements, true)
        List<SqlStatement> downCopy = copyStatements(downStatements, false)
        Long computed = computeChecksum(version, name, upCopy, downCopy)
        _version = version
        _versionSegments = segments
        _name = name
        _upStatements = upCopy
        _downStatements = downCopy
        _checksum = computed
    }

    String version() { return _version }
    String name() { return _name }
    List<SqlStatement> upStatements() { return _upStatements.copy() }
    List<SqlStatement> downStatements() { return _downStatements.copy() }
    Int upStatementCount() { return _upStatements.length() }
    Int downStatementCount() { return _downStatements.length() }
    Bool hasRollback() { return _downStatements.length() > 0 }
    Long checksum() { return _checksum }

    Int compareTo(Migration other) {
        if other == null {
            throw "Migration.compareTo: null other"
        }
        return Migration.compareVersion(_version, other.version())
    }

    static Int compareVersion(String leftVersion, String rightVersion) {
        List<String> left = parseVersionSegments(leftVersion)
        List<String> right = parseVersionSegments(rightVersion)
        Int index = 0
        while index < left.length() && index < right.length() {
            String leftSegment = left.get(index)
            String rightSegment = right.get(index)
            if leftSegment.length() != rightSegment.length() {
                if leftSegment.length() < rightSegment.length() {
                    return -1
                }
                return 1
            }
            Int digitIndex = 0
            while digitIndex < leftSegment.length() {
                String leftDigit = leftSegment.substring(digitIndex, 1)
                String rightDigit = rightSegment.substring(digitIndex, 1)
                if leftDigit != rightDigit {
                    if "0123456789".indexOf(leftDigit)
                            < "0123456789".indexOf(rightDigit) {
                        return -1
                    }
                    return 1
                }
                digitIndex = digitIndex + 1
            }
            index = index + 1
        }
        if left.length() < right.length() { return -1 }
        if left.length() > right.length() { return 1 }
        return 0
    }

    Bool equals(Migration other) {
        if other == null { return false }
        if _version != other.version() { return false }
        if _name != other.name() { return false }
        if _checksum != other.checksum() { return false }
        List<SqlStatement> otherUp = other.upStatements()
        if _upStatements.length() != otherUp.length() { return false }
        Int index = 0
        while index < _upStatements.length() {
            if !_upStatements.get(index).equals(otherUp.get(index)) {
                return false
            }
            index = index + 1
        }
        List<SqlStatement> otherDown = other.downStatements()
        if _downStatements.length() != otherDown.length() { return false }
        index = 0
        while index < _downStatements.length() {
            if !_downStatements.get(index).equals(otherDown.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "Migration(version=" + _version
            + " name=" + _name
            + " up=" + str(_upStatements.length())
            + " down=" + str(_downStatements.length())
            + " checksum=" + str(_checksum) + ")"
    }

    private static List<String> parseVersionSegments(String versionText) {
        if versionText == null || versionText.length() == 0 {
            throw "Migration: empty version"
        }
        if versionText.length() > 64 {
            throw "Migration: version too long"
        }
        List<String> segments = versionText.split(".")
        if segments.length() == 0 || segments.length() > 16 {
            throw "Migration: invalid segment count"
        }
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if segment.length() == 0 || segment.length() > 18 {
                throw "Migration: invalid segment length"
            }
            if segment.length() > 1 && segment.substring(0, 1) == "0" {
                throw "Migration: leading zero"
            }
            Int digitIndex = 0
            while digitIndex < segment.length() {
                String character = segment.substring(digitIndex, 1)
                if "0123456789".indexOf(character) < 0 {
                    throw "Migration: non-digit version segment"
                }
                digitIndex = digitIndex + 1
            }
            index = index + 1
        }
        return segments.copy()
    }

    private static void validateName(String nameText) {
        if nameText == null || trim(nameText) == "" {
            throw "Migration: empty name"
        }
        if nameText.length() > 200 {
            throw "Migration: name too long"
        }
        Int index = 0
        while index < nameText.length() {
            String character = nameText.substring(index, 1)
            if character == "\n" || character == "\r" || character == "\t" {
                throw "Migration: multiline name"
            }
            index = index + 1
        }
    }

    private static List<SqlStatement> copyStatements(
            List<SqlStatement> statements, Bool requireNonEmpty) {
        if statements == null {
            throw "Migration: null statements"
        }
        List<SqlStatement> copied = statements.copy()
        if requireNonEmpty && copied.length() == 0 {
            throw "Migration: empty up statements"
        }
        Int index = 0
        while index < copied.length() {
            if copied.get(index) == null {
                throw "Migration: null statement at " + str(index)
            }
            index = index + 1
        }
        return copied
    }

    private static Long computeChecksum(String versionText, String nameText,
            List<SqlStatement> upList, List<SqlStatement> downList) {
        String canonical = "version=" + versionText + "\n"
            + "name=" + nameText + "\n"
        Int index = 0
        while index < upList.length() {
            canonical = canonical + "up:" + upList.get(index).sql() + "\n"
            index = index + 1
        }
        index = 0
        while index < downList.length() {
            canonical = canonical + "down:" + downList.get(index).sql() + "\n"
            index = index + 1
        }
        return Checksum.compute(ChecksumAlgorithm.Fnv1a64,
            Bytes.fromUtf8(canonical))
    }
}
```

> 伪代码非可执行。`parseVersionSegments` 是文件内私有辅助；`Checksum.compute` 返回 64 位 bit pattern，允许负值。校验和只覆盖 SQL 文本，不覆盖参数值。
