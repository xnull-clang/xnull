// Tier: T0（内嵌资源读取子集）；依赖：xdk.errors；稳定性：preview。
// xdk.sys —— 内嵌资源（默认精简单元，与 io/resource 完整单元同语义）。
package xdk.sys
import xdk.errors

static Bool resourceCancelled(Context context) {
    return contextCancelledRaw(context) != 0
}

static Error resourceCancelError(String api) {
    return sysError(ErrorKind.Cancelled, api + ": 操作已取消")
}

// 路径规则：相对 `resources/` 根、`/` 分隔；绝对/`..`/空段/反斜杠非法。
static Bool resourcePathOk(String path, Bool allowEmpty) {
    Int n = path.length()
    if n == 0 {
        return allowEmpty
    }
    if path.substring(0, 1) == "/" {
        return false
    }
    if path.substring(n - 1, 1) == "/" {
        return false
    }
    if n >= 2 {
        if path.substring(0, 2) == ".." {
            return false
        }
    }
    Int i = 0
    while i < n {
        String ch = path.substring(i, 1)
        if ch == "\\" {
            return false
        }
        if ch == "/" {
            if i == 0 {
                return false
            }
            if path.substring(i - 1, 1) == "/" {
                return false
            }
            if i + 2 < n {
                if path.substring(i + 1, 2) == ".." {
                    return false
                }
            }
            if i + 2 == n {
                if path.substring(i + 1, 2) == ".." {
                    return false
                }
            }
        }
        i = i + 1
    }
    return true
}

// resourceExists：路径合法且资源存在；不存在/非法 → false（不报错）。
Bool resourceExists(String path) {
    if !resourcePathOk(path, false) {
        return false
    }
    return resourceExistsRaw(path) != 0
}

// resourceSize：字节数；缺失/非法返回 null。
Int? resourceSize(String path) {
    if !resourcePathOk(path, false) {
        return null
    }
    Long n = resourceSizeRaw(path)
    if n < 0 {
        return null
    }
    return n as Int
}

// resourceCount：产物内嵌资源总数（含所有目录层级）。
Int resourceCount() {
    return resourceCountRaw() as Int
}

// readResource：取全部字节。缺失 → NotFound；路径非法 → InvalidArgument。
Result<Bytes, Error> readResource(Context context, String path) {
    if resourceCancelled(context) {
        return Err(resourceCancelError("readResource"))
    }
    if !resourcePathOk(path, false) {
        return Err(sysError(ErrorKind.InvalidArgument, "readResource: 非法资源路径"))
    }
    String hex = readResourceHexRaw(path)
    Int code = resourceErrorRaw()
    if code != 0 {
        return Err(sysError(resourceKind(code), $"readResource: 无法读取 {path}"))
    }
    if resourceCancelled(context) {
        return Err(resourceCancelError("readResource"))
    }
    return Ok(hexDecode(hex))
}

// readResourceText：UTF-8 解码后返回文本。非法字节 → DataCorrupted。
Result<String, Error> readResourceText(Context context, String path) {
    if resourceCancelled(context) {
        return Err(resourceCancelError("readResourceText"))
    }
    if !resourcePathOk(path, false) {
        return Err(sysError(ErrorKind.InvalidArgument, "readResourceText: 非法资源路径"))
    }
    String text = readResourceTextRaw(path)
    Int code = resourceErrorRaw()
    if code != 0 {
        return Err(sysError(resourceKind(code), $"readResourceText: 无法读取 {path}"))
    }
    if resourceCancelled(context) {
        return Err(resourceCancelError("readResourceText"))
    }
    return Ok(text)
}

static Bool resourceUnder(String name, String prefix) {
    if prefix.length() == 0 {
        return name.length() > 0
    }
    if name.length() <= (prefix.length() + 1) {
        return false
    }
    if name.substring(0, prefix.length()) != prefix {
        return false
    }
    if name.substring(prefix.length(), 1) != "/" {
        return false
    }
    return true
}

// listResources：列出前缀下的全部资源路径（`/` 分隔、字典序升序）。
Result<List<String>, Error> listResources(Context context, String prefix) {
    if resourceCancelled(context) {
        return Err(resourceCancelError("listResources"))
    }
    if !resourcePathOk(prefix, true) {
        return Err(sysError(ErrorKind.InvalidArgument, "listResources: 非法资源前缀"))
    }
    Int total = resourceCountRaw() as Int
    List<String> result = []
    Int i = 0
    while i < total {
        if resourceCancelled(context) {
            return Err(resourceCancelError("listResources"))
        }
        String name = resourceAtRaw(i)
        if resourceUnder(name, prefix) {
            result.push(name)
        }
        i = i + 1
    }
    return Ok(result)
}
