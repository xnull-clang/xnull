#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
XNull Web IDE —— 单页 Web IDE 后端（仅 Python 3 标准库，无第三方依赖）。

职责：
  1. 托管 ide/web/index.html 单页前端；
  2. 以 ide/web/workspace/ 为沙箱根，提供工程创建、文件读写 API；
  3. 封装仓库 CLI 的 mini 单文件 build/run。

工程模式尚未由 mini 提供：IDE 从 xnull.project 读取 entryFile，然后调用
mini 的单文件 build/run；不存在第二引擎或回退。

启动：python3 ide/web/server.py [端口]   （默认 8765，仅监听 127.0.0.1）
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEB_DIR = os.path.join(ROOT, "ide", "web")
WORKSPACE = os.path.join(WEB_DIR, "workspace")
CLI = os.path.join(ROOT, "src", "cli", "xnull")
TIMEOUT = 60  # 子进程超时（秒）

PROJECT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
# 可编辑的文本文件扩展名（.x 为法定源码，其余为工程配套文件）
TEXT_EXT = (".x", ".project", ".md", ".txt", ".gitignore", ".json", ".xml", ".ini", ".xn")
# 目录树/搜索跳过的目录与文件
SKIP_DIRS = {"target", ".git", "node_modules"}
SKIP_FILES = {".gitkeep", ".DS_Store"}


def safe_join(base, *parts):
    """把相对路径安全地拼到 base 下，拒绝越界。"""
    cur = os.path.abspath(base)
    for p in parts:
        cur = os.path.abspath(os.path.join(cur, p))
    if cur != os.path.abspath(base) and not cur.startswith(os.path.abspath(base) + os.sep):
        raise ValueError("路径越界")
    return cur


def parse_manifest(proj_dir):
    """从 xnull.project 提取 groupId/artifactId/version/entryFile。"""
    mf = os.path.join(proj_dir, "xnull.project")
    info = {"groupId": "", "artifactId": os.path.basename(proj_dir),
            "version": "", "entryFile": "", "packaging": "app"}
    if not os.path.isfile(mf):
        return None
    with open(mf, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    for key in ("groupId", "artifactId", "version", "packaging", "entryFile"):
        m = re.search(r"\b%s\s*=\s*([^\s;\n}]+)" % key, text)
        if m:
            info[key] = m.group(1).strip()
    return info


def list_tree(proj_dir):
    """递归列出工程全部目录与文件，返回嵌套结构。"""
    def walk(d):
        dirs, files = [], []
        try:
            names = sorted(os.listdir(d), key=str.lower)
        except OSError:
            return {"dirs": [], "files": []}
        for name in names:
            if name in SKIP_FILES or name.startswith("."):
                continue
            full = os.path.join(d, name)
            if os.path.isdir(full):
                if name in SKIP_DIRS:
                    continue
                dirs.append({"name": name, "children": walk(full)})
            else:
                files.append({"name": name, "size": os.path.getsize(full)})
        return {"dirs": dirs, "files": files}
    return walk(proj_dir)


def iter_source_files(proj_dir):
    """遍历工程内全部文本文件（含子目录），返回绝对路径。"""
    for cur, _dirs, files in os.walk(proj_dir):
        if set(cur.split(os.sep)) & SKIP_DIRS:
            continue
        for fn in files:
            if fn in SKIP_FILES or fn.startswith("."):
                continue
            if fn.endswith(TEXT_EXT):
                yield os.path.join(cur, fn)


def parse_problems(out, proj_dir):
    """从 CLI 输出解析 file:line:col: error 诊断，转为相对路径。"""
    problems = []
    for line in out.splitlines():
        m = re.match(r"^(.+?):(\d+):(\d+):\s*error:\s*(.+)$", line.strip())
        if not m:
            continue
        f, ln, col, msg = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        try:
            rel = os.path.relpath(f, proj_dir).replace(os.sep, "/")
            if rel.startswith(".."):
                rel = os.path.basename(f)
        except Exception:  # noqa: BLE001
            rel = os.path.basename(f)
        if rel.endswith((".x", ".project")):
            problems.append({"file": rel, "line": ln, "col": col, "msg": msg})
    return problems


def cli_run(args, cwd):
    """执行 CLI 子命令，返回 (stdout+stderr, 退出码)。"""
    cmd = [CLI, "--bootstrap"] + args
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT)
        out = (p.stdout or "") + (p.stderr or "")
        return out, p.returncode
    except subprocess.TimeoutExpired:
        return "执行超时（%d 秒上限）" % TIMEOUT, 124
    except Exception as e:  # noqa: BLE001
        return "执行失败：%s" % e, 1


def run_project(proj_dir, mode):
    """mode: 'run' | 'build'。工程清单只用于定位 entryFile，构建由 mini 完成。"""
    info = parse_manifest(proj_dir)
    if not info or not info.get("entryFile"):
        return "工程缺少 entryFile；mini 目前只支持单文件构建", 2, "entry"
    entry_path = safe_join(proj_dir, info["entryFile"])
    if not os.path.isfile(entry_path):
        return "入口文件不存在：%s" % info["entryFile"], 2, "entry"
    out, rc = cli_run([mode, entry_path], cwd=proj_dir)
    return out, rc, "entry"


TEMPLATES = {
    "hello": {
        "desc": "最小程序",
        "code": '// main.x —— 最小程序\nstatic Int main() {\n    print("hello, XNull")\n    print("1 + 2 = " + str(1 + 2))\n    return 0\n}\n',
    },
    "classes": {
        "desc": "类与对象",
        "code": '// main.x —— 类与对象：字段、方法、self、new\n'
                'class Counter {\n'
                '    Int total = 0;\n'
                '    String label = "counter";\n\n'
                '    Int add(Int v) {\n'
                '        self.total = self.total + v;\n'
                '        return self.total;\n'
                '    }\n\n'
                '    String name() {\n'
                '        return self.label;\n'
                '    }\n'
                '}\n\n'
                'static Int main() {\n'
                '    Counter c = new Counter();\n'
                '    print(c.name());\n'
                '    print(c.add(5));\n'
                '    print(c.total);\n'
                '    return 0\n'
                '}\n',
    },
    "containers": {
        "desc": "容器与遍历",
        "code": '// main.x —— 容器：数组 / List / Map / Set 与 for-in 遍历\n'
                'static Int sum(Int[] xs) {\n'
                '    Int total = 0;\n'
                '    for v in xs {\n'
                '        total = total + v;\n'
                '    }\n'
                '    return total;\n'
                '}\n\n'
                'static Int main() {\n'
                '    Int[] nums = [1, 2, 3, 4];\n'
                '    print(nums.length());\n'
                '    print(sum(nums));\n\n'
                '    List<Int> buf = [5];\n'
                '    buf.push(6);\n'
                '    print(buf.length());\n'
                '    return 0\n'
                '}\n',
    },
    "loops": {
        "desc": "控制流",
        "code": '// main.x —— 控制流：if / else / while / for-in\n'
                'static String grade(Int score) {\n'
                '    if score >= 90 {\n'
                '        return "A";\n'
                '    } else if score >= 60 {\n'
                '        return "B";\n'
                '    } else {\n'
                '        return "C";\n'
                '    }\n'
                '}\n\n'
                'static Int main() {\n'
                '    print(grade(95));\n'
                '    Int i = 0;\n'
                '    while i < 3 {\n'
                '        print("while " + str(i));\n'
                '        i = i + 1;\n'
                '    }\n'
                '    for v in [10, 20, 30] {\n'
                '        print("for " + str(v));\n'
                '    }\n'
                '    return 0\n'
                '}\n',
    },
    "errors": {
        "desc": "Result 错误处理",
        "code": '// main.x —— 错误即值：Result<T,E> + try 传播\n'
                'static Result<Int, String> double(Int n) {\n'
                '    if n < 0 {\n'
                '        return Err("negative: " + str(n));\n'
                '    }\n'
                '    return Ok(n * 2);\n'
                '}\n\n'
                'static Int main() {\n'
                '    Result<Int, String> ok = double(21);\n'
                '    print(ok.isOk());\n'
                '    Result<Int, String> bad = double(-3);\n'
                '    print(bad.isErr());\n'
                '    print("fallback " + str(bad.unwrapOr(0)));\n'
                '    return 0\n'
                '}\n',
    },
    "algo": {
        "desc": "递归算法",
        "code": '// main.x —— 递归：斐波那契与阶乘\n'
                'static Int fib(Int n) {\n'
                '    if n <= 1 {\n'
                '        return n;\n'
                '    }\n'
                '    return fib(n - 1) + fib(n - 2);\n'
                '}\n\n'
                'static Int fact(Int n) {\n'
                '    if n <= 1 {\n'
                '        return 1;\n'
                '    }\n'
                '    return n * fact(n - 1);\n'
                '}\n\n'
                'static Int main() {\n'
                '    print(fib(10));\n'
                '    print(fact(5));\n'
                '    return 0\n'
                '}\n',
    },
}

README_TPL = (
    "# {name}\n\n"
    "XNull 工程（由 Web IDE 模板「{desc}」生成）。\n\n"
    "## 结构\n\n"
    "- `xnull.project` —— 工程清单（groupId / artifactId / 版本 / 入口）\n"
    "- `src/main/x/main.x` —— 程序入口\n\n"
    "## 运行\n\n"
    "在 Web IDE 中打开本工程，点击「运行」（⌘↩）即可编译并执行。\n"
)


def create_project(name, group_id, version, template, readme=False, gitignore=False):
    """创建工程：目录 + xnull.project + src/main/x/main.x（按模板）+ 可选配套文件。"""
    if not PROJECT_RE.match(name or ""):
        raise ValueError("工程名只能包含字母、数字、下划线、连字符")
    proj_dir = safe_join(WORKSPACE, name)
    if os.path.exists(proj_dir):
        raise ValueError("工程已存在：%s" % name)
    tpl = TEMPLATES.get(template or "hello") or TEMPLATES["hello"]
    group_id = (group_id or "io.xnull").strip() or "io.xnull"
    if not re.match(r"^[A-Za-z][A-Za-z0-9_.]*$", group_id):
        raise ValueError("groupId 格式不合法")
    version = (version or "1.0.0").strip() or "1.0.0"
    if not re.match(r"^\d+\.\d+\.\d+$", version):
        raise ValueError("version 需为 a.b.c 格式")

    src = os.path.join(proj_dir, "src", "main", "x")
    os.makedirs(src)
    manifest = (
        "project {\n"
        "  groupId    = %s\n"
        "  artifactId = %s\n"
        "  version    = %s\n"
        "  packaging  = app\n"
        "\n"
        "  build {\n"
        "    entryFile = src/main/x/main.x\n"
        "  }\n"
        "}\n" % (group_id, name, version)
    )
    with open(os.path.join(proj_dir, "xnull.project"), "w", encoding="utf-8") as f:
        f.write(manifest)
    with open(os.path.join(src, "main.x"), "w", encoding="utf-8") as f:
        f.write(tpl["code"])
    if readme:
        with open(os.path.join(proj_dir, "README.md"), "w", encoding="utf-8") as f:
            f.write(README_TPL.format(name=name, desc=tpl["desc"]))
    if gitignore:
        with open(os.path.join(proj_dir, ".gitignore"), "w", encoding="utf-8") as f:
            f.write("target/\n*.out\n*.o\n")
    return proj_dir


class Handler(BaseHTTPRequestHandler):
    server_version = "XNullWebIDE/1.0"

    # ---------- 基础 ----------
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def _json_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:  # noqa: BLE001
            return {}

    def log_message(self, fmt, *args):  # 静默访问日志
        pass

    # ---------- 路由 ----------
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/" or u.path == "/index.html":
                with open(os.path.join(WEB_DIR, "index.html"), "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            elif u.path == "/api/projects":
                self._send(200, self.api_projects())
            elif u.path == "/api/project":
                self._send(200, self.api_project(q.get("name", [""])[0]))
            elif u.path == "/api/file":
                self._send(200, self.api_file_read(q.get("name", [""])[0], q.get("path", [""])[0]))
            elif u.path == "/api/search":
                self._send(200, self.api_search(q.get("name", [""])[0], q.get("q", [""])[0]))
            elif u.path == "/api/health":
                self._send(200, {"ok": True, "root": ROOT, "time": time.strftime("%Y-%m-%d %H:%M:%S")})
            elif u.path.startswith("/vendor/"):
                self._serve_vendor(u.path)
            else:
                self._send(404, {"error": "not found"})
        except (ValueError, FileNotFoundError) as e:
            self._send(400, {"error": str(e)})
        except Exception as e:  # noqa: BLE001
            self._send(500, {"error": "服务器错误：%s" % e})

    def do_POST(self):
        u = urlparse(self.path)
        body = self._json_body()
        try:
            if u.path == "/api/projects":
                self._send(200, self.api_project_create(body))
            elif u.path == "/api/file":
                self._send(200, self.api_file_write(body))
            elif u.path == "/api/file/delete":
                self._send(200, self.api_file_delete(body))
            elif u.path == "/api/cli":
                self._send(200, self.api_cli(body))
            elif u.path == "/api/fmt":
                self._send(200, self.api_fmt(body))
            elif u.path == "/api/fs":
                self._send(200, self.api_fs(body))
            elif u.path == "/api/import":
                self._send(200, self.api_import(body))
            else:
                self._send(404, {"error": "not found"})
        except (ValueError, FileNotFoundError) as e:
            self._send(400, {"error": str(e)})
        except Exception as e:  # noqa: BLE001
            self._send(500, {"error": "服务器错误：%s" % e})

    def _serve_vendor(self, path):
        """托管 ide/web/vendor 下的静态资源（仅白名单扩展名）。"""
        name = os.path.basename(path)
        if not name.endswith((".js", ".css")) or ".." in path:
            self._send(404, {"error": "not found"})
            return
        full = os.path.join(WEB_DIR, "vendor", name)
        if not os.path.isfile(full):
            self._send(404, {"error": "not found"})
            return
        ctype = "application/javascript" if name.endswith(".js") else "text/css"
        with open(full, "rb") as f:
            self._send(200, f.read(), ctype + "; charset=utf-8")

    # ---------- API 实现 ----------
    def api_projects(self):
        items = []
        if os.path.isdir(WORKSPACE):
            for name in sorted(os.listdir(WORKSPACE)):
                d = os.path.join(WORKSPACE, name)
                if os.path.isdir(d) and os.path.isfile(os.path.join(d, "xnull.project")):
                    info = parse_manifest(d) or {}
                    n = 0
                    for _root, _dirs, files in os.walk(d):
                        if set(_root.split(os.sep)) & SKIP_DIRS:
                            continue
                        n += len([f for f in files if not f.startswith(".") and f not in SKIP_FILES])
                    items.append({
                        "name": name,
                        "groupId": info.get("groupId", ""),
                        "version": info.get("version", ""),
                        "fileCount": n,
                    })
        return {"projects": items}

    def api_project(self, name):
        proj_dir = safe_join(WORKSPACE, name)
        if not os.path.isdir(proj_dir):
            raise FileNotFoundError("工程不存在：%s" % name)
        info = parse_manifest(proj_dir) or {}
        return {"name": name, "info": info, "tree": list_tree(proj_dir)}

    def api_project_create(self, body):
        proj_dir = create_project(body.get("name"), body.get("groupId"),
                                  body.get("version"), body.get("template"),
                                  bool(body.get("readme")), bool(body.get("gitignore")))
        return {"ok": True, "name": body.get("name"),
                "manifest": parse_manifest(proj_dir), "tree": list_tree(proj_dir)}

    def api_file_read(self, name, rel):
        path = safe_join(WORKSPACE, name, rel)
        if not os.path.isfile(path):
            raise FileNotFoundError("文件不存在：%s" % rel)
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return {"ok": True, "content": f.read(), "path": rel}

    def api_file_write(self, body):
        name, rel = body.get("project", ""), body.get("path", "")
        if not rel.endswith(TEXT_EXT):
            raise ValueError("只允许编辑文本类文件：%s" % ", ".join(TEXT_EXT))
        path = safe_join(WORKSPACE, name, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(body.get("content", ""))
        return {"ok": True, "path": rel}

    def api_fs(self, body):
        """文件系统操作：mkdir / touch / rename / delete（文件或目录）。"""
        op, name = body.get("op", ""), body.get("project", "")
        rel = body.get("path", "")
        if op != "delete" and rel == "xnull.project":
            raise ValueError("不允许修改工程清单文件名")
        base = safe_join(WORKSPACE, name)
        path = safe_join(base, rel)
        if op == "mkdir":
            os.makedirs(path, exist_ok=True)
        elif op == "touch":
            if os.path.exists(path):
                raise ValueError("已存在：%s" % rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(body.get("content", ""))
        elif op == "rename":
            new_rel = body.get("newPath", "")
            new_path = safe_join(base, new_rel)
            if os.path.exists(new_path):
                raise ValueError("目标已存在：%s" % new_rel)
            os.makedirs(os.path.dirname(new_path), exist_ok=True)
            os.rename(path, new_path)
            return {"ok": True, "newPath": new_rel}
        elif op == "delete":
            if os.path.abspath(path) == os.path.abspath(base):
                raise ValueError("不允许删除工程根目录")
            if os.path.isdir(path):
                if any(f == "xnull.project" for f in os.listdir(path)) and rel != os.path.basename(rel):
                    pass  # 子目录内的清单允许删
                shutil.rmtree(path)
            elif os.path.isfile(path):
                if rel == "xnull.project":
                    raise ValueError("不允许删除工程清单")
                os.remove(path)
            else:
                raise FileNotFoundError("不存在：%s" % rel)
        else:
            raise ValueError("不支持的操作：%s" % op)
        return {"ok": True}

    def api_search(self, name, qtext):
        """跨文件全文搜索（大小写不敏感），返回按文件分组的命中。"""
        if not qtext:
            return {"ok": True, "results": []}
        proj_dir = safe_join(WORKSPACE, name)
        needle = qtext.lower()
        results, total = [], 0
        for full in iter_source_files(proj_dir):
            rel = os.path.relpath(full, proj_dir).replace(os.sep, "/")
            try:
                with open(full, "r", encoding="utf-8", errors="replace") as f:
                    for i, line in enumerate(f, 1):
                        low = line.lower()
                        col = low.find(needle)
                        if col >= 0:
                            results.append({"file": rel, "line": i, "col": col + 1,
                                            "text": line.rstrip("\r\n")[:300]})
                            total += 1
                            if total >= 300:
                                return {"ok": True, "results": results, "truncated": True}
            except OSError:
                continue
        return {"ok": True, "results": results}

    def api_import(self, body):
        """导入本机已有工程（必须含 xnull.project）到工作区。"""
        src = os.path.abspath(os.path.expanduser(body.get("path", "")))
        if not os.path.isdir(src):
            raise ValueError("目录不存在：%s" % body.get("path", ""))
        if not os.path.isfile(os.path.join(src, "xnull.project")):
            raise ValueError("所选目录不含 xnull.project，不是 XNull 工程")
        name = body.get("name") or os.path.basename(src.rstrip(os.sep))
        if not PROJECT_RE.match(name or ""):
            raise ValueError("工程名只能包含字母、数字、下划线、连字符")
        dest = safe_join(WORKSPACE, name)
        if os.path.exists(dest):
            raise ValueError("工作区已有同名工程：%s" % name)
        shutil.copytree(src, dest, ignore=shutil.ignore_patterns(
            "target", ".git", "node_modules", ".DS_Store"))
        return {"ok": True, "name": name}

    def api_fmt(self, body):
        name, rel = body.get("project", ""), body.get("path", "")
        path = safe_join(WORKSPACE, name, rel)
        if not os.path.isfile(path):
            raise FileNotFoundError("文件不存在：%s" % rel)
        return {"ok": False, "output": "mini CLI 尚未提供 fmt；格式化将在 mini fmt 落地后恢复"}
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return {"ok": True, "content": f.read()}

    def api_cli(self, body):
        name, cmd = body.get("project", ""), body.get("cmd", "run")
        proj_dir = safe_join(WORKSPACE, name)
        if not os.path.isfile(os.path.join(proj_dir, "xnull.project")):
            raise ValueError("不是有效工程：%s" % name)
        t0 = time.time()
        if cmd in ("run", "build"):
            out, rc, path = run_project(proj_dir, cmd)
            mode_note = "mini 单文件"
        else:
            return {"ok": False, "exit": 2, "output": "mini CLI 尚未提供该命令：%s" % cmd,
                    "mode": "mini", "ms": 0, "problems": []}
        return {"ok": rc == 0, "exit": rc, "output": out, "mode": mode_note,
                "ms": int((time.time() - t0) * 1000),
                "problems": parse_problems(out, proj_dir)}


def main():
    os.makedirs(WORKSPACE, exist_ok=True)
    with open(os.path.join(WORKSPACE, ".gitkeep"), "a", encoding="utf-8"):
        pass
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("XNull Web IDE 已启动 → http://127.0.0.1:%d  （工作区：%s，Ctrl+C 退出）"
          % (port, WORKSPACE))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已退出")


if __name__ == "__main__":
    main()
