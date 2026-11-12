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
import sys

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
    structs, classes, enums, data = {}, set(), set(), set()
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
                classes.add(text(nm[1]))
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
    src = open(astp, encoding="utf-8").read().strip()
    ast = parse(tokenize(src))
    decls = top_decls(ast)
    structs, classes, enums, data = decl_index(decls)
    enum_items, data_enums = enum_info(decls)
    diags = []
    if not has_main(decls):
        diags.append((1, 1, "ENTRY-001", "入口文件缺少 main"))
    ctx = {
        "enum_items": enum_items, "data_enums": data_enums,
        "structs": structs, "classes": classes, "enums": enums, "data": data,
        "enum": "", "ctor": False,
    }
    collect(ast, ctx, diags)
    diags.sort()
    for l, c, code, msg in diags:
        print("%s %d %d %s" % (code, l, c, msg))
    return 1 if diags else 0


if __name__ == "__main__":
    sys.exit(main())
