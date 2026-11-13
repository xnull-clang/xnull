#!/usr/bin/env python3
"""修复冻结编译器在 XDK raw 绑定集上的 FFI 原型/包装器错位（B5 过渡）。

现象：xn-s4 在部分 bundle 组合下会把 `xn_ffi_<name>` 的参数列表或原生调用参数
清空（签名 `()` / 调用无参），但同一份投影里的原型信息是完整的。本脚本按
投影重建签名、原生原型和调用参数；只作用于已知的 xn_ffi_* 包装器。

用法：xdk-ffi-fix.py <project.txt> <file.c>
退出码：0 已处理（可能无改动）；1 用法/IO 错误。
"""
import re
import sys

SCALAR = {
    "Int": "int64_t", "Int64": "int64_t", "UInt": "uint64_t", "UInt64": "uint64_t",
    "Int8": "int8_t", "Int16": "int16_t", "Int32": "int32_t",
    "UInt8": "uint8_t", "UInt16": "uint16_t", "UInt32": "uint32_t",
    "Float": "double", "Float64": "double", "Float32": "float",
    "Bool": "uint8_t", "Char": "uint32_t",
}
OUT = {
    ("scalar", "Int"): "int64_t *", ("scalar", "Int64"): "int64_t *",
    ("scalar", "Int32"): "int32_t *", ("scalar", "Bool"): "uint8_t *",
    ("string", "String"): "xrt_string **", ("text", "Text"): "xrt_text **",
    ("bytes", "Bytes"): "xrt_bytes_obj **", ("handle", ""): "xrt_handle **",
}


def load_entries(path):
    entries = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            fld = line.rstrip("\n").split("|")
            if len(fld) < 10 or fld[0] != "E":
                continue
            name, cname, retk, retn, errp = fld[2], fld[3], fld[4], fld[5], fld[6]
            params = []
            for seg in fld[9].split(";"):
                if not seg:
                    continue
                parts = seg.split(":")
                if len(parts) >= 3:
                    params.append({"name": parts[0], "kind": parts[1], "type": parts[2],
                                   "lease": parts[3] if len(parts) > 3 else ""})
            entries[name] = {"cname": cname, "retk": retk, "retn": retn,
                             "errp": errp, "params": params}
    return entries


def native_params(e):
    out = []
    for p in e["params"]:
        if e["errp"] and p["name"] == e["errp"]:
            continue
        k, n = p["kind"], p["name"]
        if k in ("string", "text"):
            out += ["const char *%s_bytes" % n, "size_t %s_len" % n]
        elif k == "bytes":
            out += ["void *%s" % n, "size_t %s_len" % n]
        elif k == "handle":
            out.append("void *%s" % n)
        else:
            out.append("%s %s" % (SCALAR.get(p["type"], "int64_t"), n))
    return out


def wrapper_params(e):
    out = native_params(e)
    if not (e["retk"] == "void"):
        key = (e["retk"], e["retn"])
        out.append(OUT.get(key, "int64_t *") + "xn_out")
    return out


def call_args(e):
    out = []
    for p in e["params"]:
        if e["errp"] and p["name"] == e["errp"]:
            out.append("&xn_code")
            continue
        k, n = p["kind"], p["name"]
        if k in ("string", "text", "bytes"):
            out += ["%s_bytes" % n, "%s_len" % n]
        else:
            out.append(n)
    return out


def fix(text, entries):
    # 原生原型：RET CNAME(...);
    for e in entries.values():
        proto = "%s %s(%s);" % (
            {"scalar": SCALAR.get(e["retn"], "int64_t"), "string": "const char *",
             "text": "const char *", "bytes": "xrt_bytes_obj *", "handle": "void *",
             "void": "void"}.get(e["retk"], "int64_t"),
            e["cname"], ", ".join(native_params(e)))
        text = re.sub(r"^[A-Za-z_][\w ]*\*?\s*%s\s*\([^;]*\);" % re.escape(e["cname"]),
                      proto, text, count=1, flags=re.M)
    # 包装器签名 + 原生调用
    for name, e in entries.items():
        pat = re.compile(r"(static int32_t xn_ffi_%s\()([^)]*)(\)\s*\{)" % re.escape(name))
        m = pat.search(text)
        if not m:
            continue
        text = text[:m.start()] + m.group(1) + ", ".join(wrapper_params(e)) + m.group(3) + text[m.end():]
        # 重新定位包装器块
        start = text.index("static int32_t xn_ffi_%s(" % name)
        brace = text.index("{", start)
        end = text.index("\n}", brace)
        block = text[brace:end]
        callpat = re.compile(r"(%s)\([^;]*\)" % re.escape(e["cname"]))
        block = callpat.sub("%s(%s)" % (e["cname"], ", ".join(call_args(e))), block, count=1)
        text = text[:brace] + block + text[end:]
    return text


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("用法：xdk-ffi-fix.py <project.txt> <file.c>\n")
        return 2
    entries = load_entries(sys.argv[1])
    with open(sys.argv[2], encoding="utf-8") as f:
        text = f.read()
    fixed = fix(text, entries)
    if fixed != text:
        with open(sys.argv[2], "w", encoding="utf-8") as f:
            f.write(fixed)
        sys.stderr.write("xdk-ffi-fix: 已修复 FFI 包装器错位\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
