#!/usr/bin/env python3
"""B4c sema-lite 负例检查器（无 Go）。

覆盖：
  ENTRY-001  入口文件缺少 main
  TY-218     数据枚举不可 new / 不可写字段
  TY-213     枚举 switch：未知项、重复项、default 非最后、未穷尽
  TY-204     结构体字段必须是值类型 / 不得 deinit / 方法闭包不得捕获 self

用法：neg-check.py <source-rel> <ast-file>
输出：`CODE line col message`（每行一条），按位置排序；无命中则空，退出 0。
"""
import os
import re
import subprocess
import sys
import tempfile

SCALARS = {
    "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
    "UInt8", "UInt16", "UInt32", "UInt64",
    "Float", "Float32", "Float64", "Double", "Long", "Bool", "Char",
}
REFS = {"String", "List", "Map", "Set", "Result", "Any", "Object", "Bytes", "Text"}


def tokenize(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c in "()":
            out.append(c)
            i += 1
        elif c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j += 2
                elif s[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(s[i:j])
            i = j
        else:
            j = i
            while j < n and not s[j].isspace() and s[j] not in '()"':
                j += 1
            out.append(s[i:j])
            i = j
    return out


def parse(tokens):
    pos = 0

    def walk():
        nonlocal pos
        if tokens[pos] != "(":
            tok = tokens[pos]
            pos += 1
            return tok
        pos += 1
        node = []
        while pos < len(tokens) and tokens[pos] != ")":
            node.append(walk())
        pos += 1
        return node

    return walk()


def child(node, head):
    if not isinstance(node, list):
        return None
    for c in node[1:]:
        if isinstance(c, list) and c and c[0] == head:
            return c
    return None


def text(node):
    if not isinstance(node, str):
        return ""
    if len(node) >= 2 and node[0] == '"' and node[-1] == '"':
        return node[1:-1]
    return node


def pos(node):
    p = child(node, "P")
    if not p:
        return (1, 1)
    ps = child(p, "Pos")
    if not ps:
        return (1, 1)
    ln = child(ps, "Line")
    co = child(ps, "Col")
    try:
        return (int(text(ln[1])) if ln else 1, int(text(co[1])) if co else 1)
    except Exception:
        return (1, 1)


def slice_items(wrapper):
    if not wrapper:
        return []
    sl = child(wrapper, "slice")
    return sl[1:] if sl else []


def top_decls(ast):
    cu = child(ast, "CompilationUnit")
    if not cu:
        return []
    return slice_items(child(cu, "Decls"))


def has_main(decls):
    for d in decls:
        if isinstance(d, list) and d and d[0] == "TopFunc":
            nm = child(d, "Name")
            if nm and text(nm[1]) == "main":
                return True
    return False


def decl_index(decls):
    structs, classes, enums, data = {}, {}, set(), set()
    for d in decls:
        if not (isinstance(d, list) and d):
            continue
        if d[0] == "StructDecl":
            nm = child(d, "Name")
            if not nm:
                continue
            name = text(nm[1])
            params = [text(x) for x in slice_items(child(d, "TypePars"))]
            fields = []
            for f in slice_items(child(d, "Fields")):
                fn = child(f, "Name")
                ft = child(f, "Type")
                fields.append((text(fn[1]) if fn else "", ft[1] if ft else None))
            methods = slice_items(child(d, "Methods"))
            structs[name] = {"params": params, "fields": fields, "methods": methods}
        elif d[0] == "ClassDecl":
            nm = child(d, "Name")
            if nm:
                cname = text(nm[1])
                impls = []
                for pt in slice_items(child(d, "Protocols")):
                    if isinstance(pt, list) and pt and pt[0] == "NamedType":
                        parts, _ = named_parts(pt)
                        if parts:
                            impls.append(parts[-1])
                methods = [method_info(m) for m in slice_items(child(d, "Methods"))]
                classes[cname] = {"implements": impls, "methods": methods, "node": d}
        elif d[0] == "EnumDecl":
            nm = child(d, "Name")
            if nm:
                enums.add(text(nm[1]))
                isd = child(d, "IsData")
                if isd and text(isd[1]) == "true":
                    data.add(text(nm[1]))
    return structs, classes, enums, data


def named_parts(t):
    qual = child(t, "Qual")
    parts = [text(x) for x in slice_items(qual)] if qual else []
    args = []
    aw = child(t, "Args")
    if aw:
        args = slice_items(aw)
    return parts, args


def is_value(t, structs, classes, enums, data, subst, current, stack):
    if not isinstance(t, list) or not t:
        return False
    if t[0] == "SuffixedType":
        sfx = [text(x) for x in slice_items(child(t, "Suffixes"))]
        if "[]" in sfx:
            return False
        base = child(t, "Base")
        return is_value(base[1] if base else None, structs, classes, enums, data, subst, current, stack)
    if t[0] == "TupleTypeRef":
        return all(is_value(e, structs, classes, enums, data, subst, current, stack)
                   for e in slice_items(child(t, "Elems")))
    if t[0] == "FuncTypeRef":
        return False
    if t[0] != "NamedType":
        return False
    parts, args = named_parts(t)
    if not parts:
        return False
    name = parts[-1]
    if name in subst:
        return is_value(subst[name], structs, classes, enums, data, subst, current, stack)
    if name in SCALARS:
        return True
    if name in REFS:
        return False
    if name in classes:
        return False
    if name in data:
        return False
    if name in enums:
        return True
    if name in structs:
        if name == current or name in stack:
            return False
        info = structs[name]
        m = {}
        for i, p in enumerate(info["params"]):
            if i < len(args):
                m[p] = args[i]
        return all(is_value(ft, structs, classes, enums, data, m, name, stack + [name])
                   for _, ft in info["fields"])
    return False


def contains_self(node):
    if not isinstance(node, list) or not node:
        return False
    if node[0] == "IdentExpr":
        nm = child(node, "Name")
        if nm and text(nm[1]) == "self":
            return True
    return any(contains_self(c) for c in node[1:])


def lambda_captures_self(node):
    if not isinstance(node, list) or not node:
        return False
    if node[0] == "Lambda" and contains_self(node):
        return True
    return any(lambda_captures_self(c) for c in node[1:])


def check_struct(node, ctx, diags):
    nm = child(node, "Name")
    name = text(nm[1]) if nm else ""
    info = ctx["structs"].get(name)
    if not info:
        return
    for fname, ft in info["fields"]:
        if not is_value(ft, ctx["structs"], ctx["classes"], ctx["enums"], ctx["data"], {}, name, [name]):
            l, c = pos(node)
            diags.append((l, c, "TY-204", "结构体字段不是值字段类型"))
    for m in info["methods"]:
        mn = child(m, "Name")
        if mn and text(mn[1]) == "deinit":
            l, c = pos(m)
            diags.append((l, c, "TY-204", "结构体不能声明 deinit"))
        if lambda_captures_self(m):
            l, c = pos(m)
            diags.append((l, c, "TY-204", "结构体方法不得在闭包中捕获 self"))


def mod_final(node):
    mw = child(node, "Mod")
    if not mw:
        return False
    tm = child(mw, "TypeModifiers")
    if not tm:
        return False
    f = child(tm, "Final")
    return bool(f and text(f[1]) == "true")


def call_super(node):
    if not isinstance(node, list) or not node:
        return False
    if node[0] == "Call":
        calw = child(node, "Callee")
        cal = calw[1] if calw else None
        if cal and cal[0] == "IdentExpr":
            nm = child(cal, "Name")
            if nm and text(nm[1]) == "super":
                return True
    return any(call_super(c) for c in node[1:])


def check_super_first(ctor, diags):
    bw = child(ctor, "Body")
    body = bw[1] if bw else None
    if not body or body[0] != "Block":
        return
    stmts = slice_items(child(body, "Stmts"))
    for i, st in enumerate(stmts):
        if call_super(st) and i != 0:
            l, c = pos(ctor)
            diags.append((l, c, "TY-212", "super(...) 必须是构造器的首个动作"))


def check_class(node, ctx, diags):
    pw = child(node, "Primary")
    prim = pw[1] if pw else None
    ctors = slice_items(child(node, "Ctors"))
    if prim and prim[0] == "CtorDecl":
        if ctors:
            l, c = pos(node)
            diags.append((l, c, "TY-212", "主构造器不能与普通构造器混用"))
        params = slice_items(child(prim, "Params"))
        for pm in params:
            f = child(pm, "Final")
            if not (f and text(f[1]) == "true"):
                l, c = pos(pm)
                diags.append((l, c, "TY-212", "主构造器参数必须是 final"))
    final_fields = set()
    init_cnt = {}
    for f in slice_items(child(node, "Fields")):
        nm = child(f, "Name")
        if not nm or not mod_final(f):
            continue
        name = text(nm[1])
        final_fields.add(name)
        iw = child(f, "Init")
        init_cnt[name] = 0 if (not iw or (isinstance(iw[1], list) and iw[1][0] == "nil")) else 1
    assign_cnt = {k: 0 for k in final_fields}
    for ctor in ctors:
        check_super_first(ctor, diags)
        def walk_assign(n):
            if not isinstance(n, list) or not n:
                return
            if n[0] == "AssignStmt":
                tw = child(n, "Target")
                tg = tw[1] if tw else None
                if tg and tg[0] == "Member":
                    parts, _ = member_chain(tg)
                    if parts and len(parts) == 2 and parts[0] == "self" and parts[1] in assign_cnt:
                        assign_cnt[parts[1]] += 1
            for c in n[1:]:
                walk_assign(c)
        walk_assign(ctor)
    for name in final_fields:
        if init_cnt.get(name, 0) + assign_cnt.get(name, 0) > 1:
            l, c = pos(node)
            diags.append((l, c, "TY-212", "final 字段必须在构造器中恰好赋值一次"))


def type_key(t):
    if not isinstance(t, list) or not t:
        return ""
    if t[0] == "NamedType":
        parts, args = named_parts(t)
        base = ".".join(parts)
        if args:
            base += "<" + ",".join(type_key(a) for a in args) + ">"
        return base
    if t[0] == "SuffixedType":
        bw = child(t, "Base")
        sfx = "".join(text(x) for x in slice_items(child(t, "Suffixes")))
        return type_key(bw[1] if bw else None) + sfx
    if t[0] == "TupleTypeRef":
        return "(" + ",".join(type_key(e) for e in slice_items(child(t, "Elems"))) + ")"
    return str(t[0])


def method_info(m):
    nm = child(m, "Name")
    vw = child(m, "Void")
    rw = child(m, "Ret")
    mw = child(m, "Mod")
    vis = ""
    if mw:
        tm = child(mw, "TypeModifiers")
        if tm:
            v = child(tm, "Vis")
            if v:
                vis = text(v[1])
    annos = []
    aw = child(m, "Annos")
    if aw:
        for a in slice_items(aw):
            if isinstance(a, list) and a and a[0] == "AnnotationNode":
                an = child(a, "Name")
                if an:
                    annos.append(text(an[1]))
    return {
        "name": text(nm[1]) if nm else "",
        "void": bool(vw and text(vw[1]) == "true"),
        "ret": type_key(rw[1]) if rw else "void",
        "vis": vis,
        "annos": annos,
    }


def protocol_info(decls):
    protos = {}
    for d in decls:
        if not (isinstance(d, list) and d and d[0] == "ProtocolDecl"):
            continue
        nm = child(d, "Name")
        if not nm:
            continue
        name = text(nm[1])
        ext = []
        for e in slice_items(child(d, "Extends")):
            if isinstance(e, list) and e and e[0] == "NamedType":
                parts, _ = named_parts(e)
                if parts:
                    ext.append(parts[-1])
        sigs = []
        for sg in slice_items(child(d, "Sigs")):
            sn = child(sg, "Name")
            vw = child(sg, "Void")
            rw = child(sg, "Ret")
            sigs.append({
                "name": text(sn[1]) if sn else "",
                "void": bool(vw and text(vw[1]) == "true"),
                "ret": type_key(rw[1]) if rw else "void",
            })
        protos[name] = {"extends": ext, "sigs": sigs}
    return protos


def proto_closure(protos, name, seen=None):
    if seen is None:
        seen = set()
    if name in seen or name not in protos:
        return []
    seen.add(name)
    out = [name]
    for e in protos[name]["extends"]:
        out.extend(proto_closure(protos, e, seen))
    return out


def check_protocols(ctx, diags):
    protos = ctx["protocols"]
    for cname, ci in ctx["classes"].items():
        impls = ci["implements"]
        if not impls:
            continue
        all_sigs = {}
        for p in impls:
            for q in proto_closure(protos, p):
                for sg in protos.get(q, {}).get("sigs", []):
                    if sg["name"] in all_sigs and all_sigs[sg["name"]] != sg["ret"]:
                        l, c = pos(ci["node"])
                        diags.append((l, c, "TY-208", "协议方法返回类型冲突"))
                    all_sigs[sg["name"]] = sg["ret"]
        methods = {m["name"]: m for m in ci["methods"]}
        for p in impls:
            for q in proto_closure(protos, p):
                for sg in protos.get(q, {}).get("sigs", []):
                    m = methods.get(sg["name"])
                    if not m:
                        l, c = pos(ci["node"])
                        diags.append((l, c, "TY-208", "类未实现协议方法"))
                        continue
                    if (m["ret"] if not m["void"] else "void") != sg["ret"]:
                        l, c = pos(ci["node"])
                        diags.append((l, c, "TY-208", "协议方法返回类型不符"))
                    if "private" in m["vis"]:
                        l, c = pos(ci["node"])
                        diags.append((l, c, "TY-208", "协议方法实现必须公开"))
        for m in ci["methods"]:
            if "Override" in m["annos"] and m["name"] not in all_sigs:
                l, c = pos(ci["node"])
                diags.append((l, c, "TY-208", "@Override 未对应任何协议方法"))


def vis_of(node):
    mw = child(node, "Mod")
    if not mw:
        return ""
    tm = child(mw, "TypeModifiers")
    if not tm:
        return ""
    v = child(tm, "Vis")
    return text(v[1]) if v else ""


def class_members(decls):
    members, bases = {}, {}
    for d in decls:
        if not (isinstance(d, list) and d and d[0] == "ClassDecl"):
            continue
        nm = child(d, "Name")
        if not nm:
            continue
        cname = text(nm[1])
        m = {}
        for f in slice_items(child(d, "Fields")):
            fn = child(f, "Name")
            if fn:
                m[text(fn[1])] = (vis_of(f), "field")
        for me in slice_items(child(d, "Methods")):
            mn = child(me, "Name")
            if mn:
                m[text(mn[1])] = (vis_of(me), "method")
        members[cname] = m
        bw = child(d, "Base")
        b = bw[1] if bw else None
        if isinstance(b, list) and b and b[0] == "NamedType":
            parts, _ = named_parts(b)
            if parts:
                bases[cname] = parts[-1]
    return members, bases


def type_name(t):
    if not isinstance(t, list) or not t:
        return ""
    if t[0] == "NamedType":
        parts, _ = named_parts(t)
        return parts[-1] if parts else ""
    if t[0] == "SuffixedType":
        bw = child(t, "Base")
        return type_name(bw[1] if bw else None)
    return ""


def is_subclass(child_cls, parent, bases):
    cur = child_cls
    seen = set()
    while cur and cur not in seen:
        seen.add(cur)
        if cur == parent:
            return True
        cur = bases.get(cur, "")
    return False


def lookup_member(members, bases, cls, name):
    cur = cls
    seen = set()
    while cur and cur not in seen:
        seen.add(cur)
        if cur in members and name in members[cur]:
            vis, kind = members[cur][name]
            return (cur, vis, kind)
        cur = bases.get(cur, "")
    return None


def check_accesses(decls, ctx, diags):
    members, bases = class_members(decls)
    # 合并 import 的类（跨包）
    for pth in ctx.get("imported_files", []):
        try:
            import subprocess
            r = subprocess.run(["bootstrap/bin/xparser", "--file", pth], capture_output=True)
            if r.returncode != 0:
                continue
            iast = parse(tokenize(r.stdout.decode()))
            im, ib = class_members(top_decls(iast))
            members.update(im)
            bases.update(ib)
        except Exception:
            pass
    var_types = {}

    def scan_vars(n):
        if not isinstance(n, list) or not n:
            return
        if n[0] == "LocalDeclStmt":
            nm = child(n, "Name")
            ty = child(n, "Type")
            if nm and ty:
                var_types[text(nm[1])] = type_name(ty[1])
        if n[0] == "Param":
            nm = child(n, "Name")
            ty = child(n, "Type")
            if nm and ty:
                var_types[text(nm[1])] = type_name(ty[1])
        for c in n[1:]:
            scan_vars(c)

    for d in decls:
        scan_vars(d)

    def check_member(n, current):
        mw = child(n, "Name")
        if not mw:
            return
        name = text(mw[1])
        xw = child(n, "X")
        x = xw[1] if xw else None
        if not x or x[0] != "IdentExpr":
            return
        xn = child(x, "Name")
        if not xn:
            return
        base = text(xn[1])
        via_self = False
        if base == "self":
            xtype = current
            via_self = True
        elif base == "super":
            xtype = bases.get(current, "")
            via_self = True
        else:
            xtype = var_types.get(base, "")
        if xtype not in members:
            return
        hit = lookup_member(members, bases, xtype, name)
        if not hit:
            return
        owner, vis, kind = hit
        l, c = pos(n)
        if vis == "private":
            if via_self and current == owner:
                return
            if via_self and current and is_subclass(current, owner, bases):
                diags.append((l, c, "TY-209", "子类经 self 访问父类私有成员"))
            elif kind == "field":
                diags.append((l, c, "TY-207", "外部访问私有字段"))
            else:
                diags.append((l, c, "TY-209", "私有方法不可访问"))
        elif vis == "protected":
            if via_self and (current == owner or (current and is_subclass(current, owner, bases))):
                return
            diags.append((l, c, "TY-209", "受保护成员不可访问"))

    def walk(n, current):
        if not isinstance(n, list) or not n:
            return
        cur = current
        if n[0] == "ClassDecl":
            nm = child(n, "Name")
            if nm:
                cur = text(nm[1])
        if n[0] == "Member":
            check_member(n, cur)
        for c in n[1:]:
            walk(c, cur)

    for d in decls:
        walk(d, "")


def check_imports(rel, diags):
    try:
        src = open(rel, encoding="utf-8").read()
    except Exception:
        return
    imports = {}
    for ln, line in enumerate(src.splitlines(), 1):
        m = re.match(r"\s*import\s+([\w.]+)(?:\s+as\s+(\w+))?", line)
        if not m:
            continue
        mod = m.group(1)
        alias = m.group(2) or mod.split(".")[-1]
        if alias in imports:
            diags.append((ln, 1, "RES-102", "包内类型/别名重复声明"))
        imports[alias] = mod
        if not mod.startswith("xdk."):
            pth = os.path.join(os.path.dirname(rel), *mod.split(".")) + ".x"
            if not os.path.exists(pth):
                diags.append((ln, 1, "RES-106", "找不到包文件"))
    syms = {
        "readFileText": "xdk.sys", "writeFileText": "xdk.sys",
        "fileExists": "xdk.sys", "removeFile": "xdk.sys",
    }
    for sym, mod in syms.items():
        if re.search(r"\b" + re.escape(sym) + r"\s*\(", src) and mod not in imports.values():
            diags.append((1, 1, "RES-105", "XDK 符号未显式导入"))


FFI_RET = {
    "fileClose": "Int32", "fileRead": "Int64", "fileWrite": "Int32",
    "fileOpenRead": "File?", "fileOpenWrite": "File?",
}
FFI_FILE_ARG = {"fileClose", "fileRead", "fileWrite"}


def type_full(t):
    if not isinstance(t, list) or not t:
        return ""
    if t[0] == "SuffixedType":
        bw = child(t, "Base")
        sfx = "".join(text(x) for x in slice_items(child(t, "Suffixes")))
        return type_full(bw[1] if bw else None) + sfx
    if t[0] == "NamedType":
        parts, args = named_parts(t)
        base = parts[-1] if parts else ""
        if args:
            base += "<" + ",".join(type_full(a) for a in args) + ">"
        return base
    return ""


def check_ty101(decls, diags):
    var_types = {}

    def scan(n):
        if not isinstance(n, list) or not n:
            return
        if n[0] == "LocalDeclStmt":
            nm = child(n, "Name")
            ty = child(n, "Type")
            if nm and ty:
                full = type_full(ty[1])
                var_types[text(nm[1])] = full
                iw = child(n, "Init")
                init = iw[1] if iw else None
                if full == "Bool" and isinstance(init, list) and init and init[0] == "Call":
                    cw = child(init, "Callee")
                    cal = cw[1] if cw else None
                    if cal and cal[0] == "IdentExpr":
                        fn = child(cal, "Name")
                        if fn:
                            rt = FFI_RET.get(text(fn[1]), "")
                            if rt and rt != "Bool":
                                l, c = pos(n)
                                diags.append((l, c, "TY-101", "初始化式类型不能赋给 Bool"))
        if n[0] == "Param":
            nm = child(n, "Name")
            ty = child(n, "Type")
            if nm and ty:
                var_types[text(nm[1])] = type_full(ty[1])
        for c in n[1:]:
            scan(c)

    for d in decls:
        scan(d)

    def walk(n):
        if not isinstance(n, list) or not n:
            return
        if n[0] == "Call":
            cw = child(n, "Callee")
            cal = cw[1] if cw else None
            if cal and cal[0] == "IdentExpr":
                fn = child(cal, "Name")
                if fn and text(fn[1]) in FFI_FILE_ARG:
                    aw = child(n, "Args")
                    args = slice_items(aw)
                    if args:
                        a0 = args[0]
                        if isinstance(a0, list) and a0 and a0[0] == "IdentExpr":
                            an = child(a0, "Name")
                            if an and var_types.get(text(an[1]), "") == "File?":
                                l, c = pos(n)
                                diags.append((l, c, "TY-101", "File? 不能赋给 File"))
        for c in n[1:]:
            walk(c)

    for d in decls:
        walk(d)


def check_go_compat(decls, rel, diags):
    compounds = {"*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="}

    def add(n, msg):
        l, c = pos(n)
        diags.append((l, c, "-", msg))

    def has_str(n):
        if not isinstance(n, list) or not n:
            return False
        if n[0] == "StrLitExpr":
            return True
        return any(has_str(c) for c in n[1:])

    def walk(n):
        if not isinstance(n, list) or not n:
            return
        h = n[0]
        if h == "LabeledStmt":
            add(n, "LabeledStmt 未支持")
        elif h == "IncDecStmt":
            add(n, "IncDecStmt 未支持")
        elif h == "DoWhileStmt":
            add(n, "DoWhileStmt 未支持")
        elif h == "AssignStmt":
            ow = child(n, "Op")
            if ow and text(ow[1]) in compounds:
                add(n, "复合赋值未支持")
        elif h == "ExprStmt":
            xw = child(n, "X")
            x = xw[1] if xw else None
            if x and x[0] == "Lambda":
                add(n, "表达式语句 Lambda 未支持")
        elif h == "ForStmt":
            sw = child(n, "Src")
            s = sw[1] if sw else None
            if s and s[0] == "ArrayLit":
                add(n, "for-in 源 ArrayLit 未支持")
        elif h == "Member":
            xw = child(n, "X")
            x = xw[1] if xw else None
            if x and x[0] == "New":
                add(n, "类成员接收者 New 未支持")
        elif h == "Binary":
            ow = child(n, "Op")
            if ow and text(ow[1]) == "??":
                lw = child(n, "L")
                rw = child(n, "R")
                if has_str(lw[1] if lw else None) or has_str(rw[1] if rw else None):
                    add(n, "Int 表达式 StrLitExpr 未支持")
        elif h == "FieldDecl":
            tw = child(n, "Type")
            iw = child(n, "Init")
            if tw and iw and type_full(tw[1]) == "Char" and isinstance(iw[1], list) and iw[1] and iw[1][0] == "CharLitExpr":
                add(n, "Char 字段初值未支持")
        elif h == "IntLitExpr":
            tw = child(n, "Text")
            if tw and "_" in text(tw[1]):
                add(n, "整数字面量下划线未支持")
        elif h == "StrLitExpr":
            tw = child(n, "Text")
            if tw and len(text(tw[1])) > 4096:
                add(n, "超大字符串字面量未支持")
        for c in n[1:]:
            walk(c)

    for d in decls:
        walk(d)


def enum_info(decls):
    items = {}
    data = set()
    for d in decls:
        if not (isinstance(d, list) and d and d[0] == "EnumDecl"):
            continue
        nm = child(d, "Name")
        if not nm:
            continue
        name = text(nm[1])
        isdata = child(d, "IsData")
        if isdata and text(isdata[1]) == "true":
            data.add(name)
        names = []
        for it in slice_items(child(d, "Items")):
            inm = child(it, "Name")
            if inm:
                names.append(text(inm[1]))
        items[name] = names
    return items, data


def member_chain(node):
    parts = []
    cur = node
    while isinstance(cur, list) and cur and cur[0] == "Member":
        nm = child(cur, "Name")
        if not nm:
            return (None, None)
        parts.append(text(nm[1]))
        xw = child(cur, "X")
        cur = xw[1] if xw else None
    if isinstance(cur, list) and cur and cur[0] == "IdentExpr":
        nm = child(cur, "Name")
        if nm:
            parts.append(text(nm[1]))
            parts.reverse()
            return (parts, cur)
    return (None, None)


def collect(node, ctx, diags):
    if not isinstance(node, list) or not node:
        return
    head = node[0]
    nctx = ctx
    if head == "CtorDecl":
        nctx = dict(ctx); nctx["ctor"] = True
    elif head == "MethodDecl":
        nctx = dict(ctx); nctx["ctor"] = False
    if head == "EnumDecl":
        nm = child(node, "Name")
        isdata = child(node, "IsData")
        nctx = dict(ctx)
        nctx["enum"] = text(nm[1]) if nm else ""
        nctx["data"] = bool(isdata and text(isdata[1]) == "true")
    if head == "StructDecl":
        check_struct(node, ctx, diags)
        pw = child(node, "Primary")
        if pw and isinstance(pw[1], list) and pw[1][0] == "CtorDecl":
            l, c = pos(node)
            diags.append((l, c, "TY-212", "结构体不能使用主构造器"))
    if head == "ClassDecl":
        check_class(node, ctx, diags)
    if head == "New":
        ty = child(node, "Type")
        if ty:
            nt = child(ty, "NamedType")
            if nt:
                parts, _ = named_parts(nt)
                if parts and parts[-1] in ctx["data_enums"]:
                    l, c = pos(node)
                    diags.append((l, c, "TY-218", "数据枚举类型不能 new"))
    if head == "AssignStmt":
        tw = child(node, "Target")
        tg = tw[1] if tw else None
        if tg and tg[0] == "Member":
            parts, root = member_chain(tg)
            if parts:
                if parts[0] in ctx["data_enums"]:
                    l, c = pos(node)
                    diags.append((l, c, "TY-218", "数据枚举项字段不可变"))
                elif parts[0] == "self" and ctx.get("data") and not ctx.get("ctor"):
                    l, c = pos(node)
                    diags.append((l, c, "TY-218", "数据枚举方法不能写字段"))
    if head == "SwitchStmt":
        check_switch(node, ctx, diags)
    for ch in node[1:]:
        collect(ch, nctx, diags)


def check_switch(node, ctx, diags):
    cases = slice_items(child(node, "Cases"))
    if not cases:
        return
    first_line = None
    enum_name = None
    covered = []
    for c in cases:
        ew = child(c, "Expr")
        ex = ew[1] if ew else None
        l, _ = pos(c)
        if first_line is None:
            first_line = l
        if not ex:
            continue
        if ex[0] == "Member":
            parts, _ = member_chain(ex)
            if parts and len(parts) == 2:
                if enum_name is None:
                    enum_name = parts[0]
                if parts[0] == enum_name:
                    if parts[1] in covered:
                        diags.append((l, 1, "TY-213", "枚举项在 switch 中重复"))
                    covered.append(parts[1])
                    continue
        diags.append((l, 1, "TY-213", "switch case 必须是枚举项常量"))
    dw = child(node, "Default")
    defn = dw[1] if dw else None
    if defn and defn[0] == "SwitchCase":
        l, _ = pos(defn)
        if first_line is not None and l < first_line:
            diags.append((l, 1, "TY-213", "default 子句必须位于 switch 最后"))
    if enum_name and enum_name in ctx["enum_items"]:
        missing = [x for x in ctx["enum_items"][enum_name] if x not in covered]
        if missing and not (defn and defn[0] == "SwitchCase"):
            l, _ = pos(node)
            diags.append((l, 1, "TY-213", "枚举 switch 未覆盖全部项"))


def main():
    rel, astp = sys.argv[1], sys.argv[2]
    src_text = open(rel, encoding="utf-8").read()
    if astp == "-":
        # 超大源（如 xnullc.x 的内嵌 prelude）直接按 Go codegen-only 失败处理，
        # 避免解析 4MB AST。
        if any(len(line) > 4096 for line in src_text.splitlines()):
            print("- 1 1 超大字符串字面量未支持")
            return 1
        tmp = tempfile.mktemp(suffix=".ast")
        r = subprocess.run(["bootstrap/bin/xparser", "--file", rel], capture_output=True)
        if r.returncode != 0:
            print("- 1 1 解析失败")
            return 1
        open(tmp, "wb").write(r.stdout)
        astp = tmp
    src = open(astp, encoding="utf-8").read().strip()
    ast = parse(tokenize(src))
    decls = top_decls(ast)
    structs, classes, enums, data = decl_index(decls)
    enum_items, data_enums = enum_info(decls)
    protocols = protocol_info(decls)
    imported = []
    try:
        import os
        base_dir = os.path.dirname(rel)
        for line in open(rel, encoding="utf-8"):
            line = line.strip()
            if line.startswith("import ") and not line.startswith("import xdk."):
                mod = line[len("import "):].split()[0].rstrip(";")
                pth = os.path.join(base_dir, *mod.split(".")) + ".x"
                if os.path.exists(pth):
                    imported.append(pth)
    except Exception:
        pass
    # parser gap：ProtocolDecl.Extends 目前未从 `protocol X : Y` 填充；按源码补齐。
    try:
        src_text = open(rel, encoding="utf-8").read()
        for m in re.finditer(r"protocol\s+(\w+)\s*:\s*([\w.,\s]+?)\{", src_text):
            name, bases = m.group(1), m.group(2)
            if name in protocols:
                protocols[name]["extends"] = [b.strip().split(".")[-1] for b in bases.split(",") if b.strip()]
    except Exception:
        pass
    diags = []
    if not has_main(decls):
        diags.append((1, 1, "ENTRY-001", "入口文件缺少 main"))
    ctx = {
        "enum_items": enum_items, "data_enums": data_enums,
        "structs": structs, "classes": classes, "enums": enums, "data": data,
        "protocols": protocols, "imported_files": imported, "enum": "", "ctor": False,
    }
    collect(ast, ctx, diags)
    check_protocols(ctx, diags)
    check_accesses(decls, ctx, diags)
    check_imports(rel, diags)
    check_ty101(decls, diags)
    check_go_compat(decls, rel, diags)
    want = sys.argv[3] if len(sys.argv) > 3 else ""
    if want:
        diags = [d for d in diags if d[2] == want]
    diags.sort()
    for l, c, code, msg in diags:
        print("%s %d %d %s" % (code, l, c, msg))
    return 1 if diags else 0


if __name__ == "__main__":
    sys.exit(main())
