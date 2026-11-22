#!/usr/bin/env python3
"""M0.2 annotation processor platform: manifest, scheduler, diagnostics."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import platform as host_platform

PHASES = ["Resolve", "Validate", "Generate", "Finalize"]
SEV_RANK = {"Error": 0, "Warning": 1, "Note": 2}
CODE_RE = re.compile(r"^AN(\d{4})$")


def fail(message, code=2):
    print(f"annotation_platform: {message}", file=sys.stderr)
    return code


def manifest_error(message):
    return fail(f"manifest: {message}")


def load_manifest(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"cannot read manifest: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("manifest must be an object")
    if data.get("manifestVersion") != 1:
        raise ValueError("manifestVersion must be 1")
    processors = data.get("processors")
    if not isinstance(processors, list) or not processors:
        raise ValueError("processors must be a non-empty array")
    names = set()
    for index, proc in enumerate(processors):
        if not isinstance(proc, dict):
            raise ValueError(f"processors[{index}] must be an object")
        name = proc.get("name")
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"processors[{index}].name must be non-empty")
        if name in names:
            raise ValueError(f"duplicate processor name: {name}")
        names.add(name)
        phases = proc.get("phases")
        if not isinstance(phases, list) or not phases:
            raise ValueError(f"{name}: phases must be a non-empty array")
        if len(set(phases)) != len(phases):
            raise ValueError(f"{name}: duplicate phase")
        for phase in phases:
            if phase not in PHASES:
                raise ValueError(f"{name}: invalid phase {phase}")
        command = proc.get("command")
        if not isinstance(command, list) or not command or not all(isinstance(x, str) for x in command):
            raise ValueError(f"{name}: command must be a non-empty string array")
        outputs = proc.get("outputs")
        if not isinstance(outputs, list) or not all(isinstance(x, str) for x in outputs):
            raise ValueError(f"{name}: outputs must be a string array")
        for output in outputs:
            p = Path(output)
            if p.is_absolute() or ".." in p.parts or output == "":
                raise ValueError(f"{name}: output must be a relative path without ..: {output}")
        timeout = proc.get("timeoutSeconds", 30)
        if not isinstance(timeout, int) or timeout < 1 or timeout > 120:
            raise ValueError(f"{name}: timeoutSeconds must be 1..120")
        priority = proc.get("priority", 0)
        if not isinstance(priority, int):
            raise ValueError(f"{name}: priority must be an integer")
        sandbox = proc.get("sandbox", {})
        if not isinstance(sandbox, dict):
            raise ValueError(f"{name}: sandbox must be an object")
        allowed = {"enabled", "allowNetwork", "maxMemoryMB", "maxCpuSeconds"}
        extra = set(sandbox) - allowed
        if extra:
            raise ValueError(f"{name}: sandbox has unknown fields: {sorted(extra)}")
        enabled = sandbox.get("enabled", True)
        if not isinstance(enabled, bool):
            raise ValueError(f"{name}: sandbox.enabled must be bool")
        allow_network = sandbox.get("allowNetwork", False)
        if allow_network is not False:
            raise ValueError(f"{name}: sandbox.allowNetwork must be false")
        max_memory = sandbox.get("maxMemoryMB", 256)
        if not isinstance(max_memory, int) or max_memory < 32 or max_memory > 4096:
            raise ValueError(f"{name}: sandbox.maxMemoryMB must be 32..4096")
        max_cpu = sandbox.get("maxCpuSeconds", timeout)
        if not isinstance(max_cpu, int) or max_cpu < 1 or max_cpu > 120:
            raise ValueError(f"{name}: sandbox.maxCpuSeconds must be 1..120")
        proc["_sandbox"] = {
            "enabled": enabled, "allowNetwork": False,
            "maxMemoryMB": max_memory, "maxCpuSeconds": max_cpu,
        }
        proc["_timeout"] = timeout
        proc["_priority"] = priority
    return data


def resolve_command(proc, manifest_dir):
    command = []
    for part in proc["command"]:
        candidate = Path(part)
        if not part.startswith("-") and not candidate.is_absolute():
            local = manifest_dir / candidate
            if local.exists():
                command.append(str(local.resolve()))
                continue
        command.append(part)
    return command


def run_mini_ir(entry, xdk_root):
    mini = Path(__file__).resolve().parents[1] / "mini" / "bin" / "mini"
    result = subprocess.run(
        [str(mini), "--dump-annotations", str(entry), "--xdk-root", str(xdk_root)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "mini --dump-annotations failed")
    return result.stdout


def validate_diagnostic(item, processor):
    if not isinstance(item, dict):
        raise ValueError(f"{processor}: diagnostic must be an object")
    code = item.get("code")
    match = CODE_RE.match(code or "")
    if not match:
        raise ValueError(f"{processor}: diagnostic code must match ANdddd")
    number = int(match.group(1))
    if not (100 <= number <= 199 or 1000 <= number <= 1999):
        raise ValueError(f"{processor}: diagnostic code outside AN0100-0199/AN1000-1999: {code}")
    severity = item.get("severity")
    if severity not in SEV_RANK:
        raise ValueError(f"{processor}: invalid severity {severity}")
    line = item.get("line")
    col = item.get("col")
    if not isinstance(line, int) or line < 1 or not isinstance(col, int) or col < 1:
        raise ValueError(f"{processor}: line/col must be positive integers")
    if not isinstance(item.get("message"), str):
        raise ValueError(f"{processor}: message must be a string")
    return {
        "code": code,
        "severity": severity,
        "message": item["message"],
        "line": line,
        "col": col,
        "target": item.get("target", ""),
    }


def merge_diagnostics(diags):
    unique = {}
    for d in diags:
        key = (d["code"], d["line"], d["col"], d["message"])
        unique[key] = d
    ordered = sorted(
        unique.values(),
        key=lambda d: (SEV_RANK[d["severity"]], d["code"], d["line"], d["col"], d["message"]),
    )
    return ordered


SANDBOX_BACKEND = "darwin-sandbox-exec" if host_platform.system() == "Darwin" and Path("/usr/bin/sandbox-exec").exists() else "limits-only"


def sandbox_profile(outdir, tmpdir):
    return """(version 1)
(deny default)
(allow file-read*)
(allow file-write* (subpath \"""" + str(outdir) + """\") (subpath \"""" + str(tmpdir) + """\") (literal "/dev/null") (literal "/dev/stdout") (literal "/dev/stderr"))
(allow process*)
(allow sysctl-read)
(allow mach-lookup)
(deny network*)
""", ""


def resource_limits(proc):
    import resource
    def apply():
        cpu = proc["_sandbox"]["maxCpuSeconds"]
        mem = proc["_sandbox"]["maxMemoryMB"] * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_CPU, (cpu, cpu + 1))
        try:
            resource.setrlimit(resource.RLIMIT_AS, (mem, mem))
        except (ValueError, OSError):
            pass
        try:
            resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
        except (ValueError, OSError):
            pass
    return apply


def run_sandboxed(proc, command, cwd, ir_path, work):
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": os.environ.get("LANG", "C"),
        "PYTHONPATH": str(Path(__file__).resolve().parents[1]),
        "HOME": str(work),
        "TMPDIR": str(work),
    }
    prof = work.parent / (work.name + ".sandbox.sb")
    if proc["_sandbox"]["enabled"] and SANDBOX_BACKEND == "darwin-sandbox-exec":
        text, _ = sandbox_profile(work, work)
        prof.write_text(text, encoding="utf-8")
        full = ["/usr/bin/sandbox-exec", "-f", str(prof)] + command
    else:
        full = command
    return subprocess.run(
        full, capture_output=True, text=True, timeout=proc["_timeout"],
        cwd=str(cwd), env=env, preexec_fn=resource_limits(proc),
    )


def snapshot(root):
    result = {}
    if not root.exists():
        return result
    for path in sorted(root.rglob("*")):
        if path.is_file():
            result[path.relative_to(root).as_posix()] = path.read_bytes()
    return result


def generate(args):
    try:
        manifest = load_manifest(args.manifest)
    except ValueError as exc:
        return manifest_error(str(exc))
    manifest_dir = Path(args.manifest).resolve().parent
    # Allow the first dump to import generated-dir outputs that do not exist yet:
    # seed declared outputs with inert placeholders. Real processors overwrite them;
    # unreplaced placeholders are removed before success.
    stub_paths = []
    if args.generated_dir:
        for proc in manifest["processors"]:
            for rel in proc.get("outputs", []):
                stub = (Path(args.generated_dir).resolve() / rel)
                if not stub.exists():
                    stub.parent.mkdir(parents=True, exist_ok=True)
                    stub.write_text("// generated placeholder; DO NOT EDIT\n", encoding="utf-8")
                    stub_paths.append(rel)
    try:
        ir_text = run_mini_ir(args.entry, args.xdk_root)
        json.loads(ir_text)
    except Exception as exc:
        print(f"annotation_platform: IR failed: {exc}", file=sys.stderr)
        return 2

    out = Path(args.generated_dir or args.out).resolve()
    if args.generated_dir and args.out:
        return fail("use either --out or --generated-dir, not both")
    if not args.generated_dir and not args.out:
        return fail("missing --out or --generated-dir")
    backup = None
    if args.generated_dir:
        backup = out.parent / (".a8-backup-" + out.name)
        if backup.exists():
            shutil.rmtree(backup)
        if out.exists():
            out.rename(backup)
        out.mkdir(parents=True)
    else:
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
    (out / "ir.json").write_text(ir_text, encoding="utf-8")

    generated = {}
    diagnostics = []
    reports = []
    failure = None
    sandbox_profiles = []

    def platform_error(message):
        diagnostics.append({
            "code": "AN0100", "severity": "Error", "message": message,
            "line": 1, "col": 1, "target": "",
        })

    def invoke(proc, phase, round_no):
        nonlocal failure
        name = proc["name"]
        work = out / ".processors" / phase / str(round_no) / name
        work.mkdir(parents=True, exist_ok=True)
        command = resolve_command(proc, manifest_dir) + [
            "--phase", phase, "--ir", str(out / "ir.json"), "--out", str(work),
        ]
        try:
            result = run_sandboxed(proc, command, work, out / "ir.json", work)
        except subprocess.TimeoutExpired:
            failure = f"processor {name} timeout in {phase}"
            return []
        reports.append({
            "processor": name, "phase": phase, "round": round_no,
            "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
        })
        if result.returncode != 0:
            failure = f"processor {name} failed in {phase}: exit {result.returncode}"
            return []
        try:
            import resource
            peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
            limit_bytes = proc["_sandbox"]["maxMemoryMB"] * 1024 * 1024
            if host_platform.system() == "Darwin":
                over = peak > limit_bytes
            else:
                over = peak * 1024 > limit_bytes
            if over:
                failure = f"processor {name} exceeded memory limit"
                return []
        except Exception:
            pass
        for path in work.rglob("*"):
            if path.is_symlink():
                failure = f"processor {name} created symlink: {path.relative_to(work)}"
                return []
        files = snapshot(work)
        diag_path = work / "diagnostics.json"
        if diag_path.exists():
            try:
                raw = json.loads(diag_path.read_text(encoding="utf-8"))
                if not isinstance(raw, list):
                    raise ValueError("diagnostics.json must be an array")
                for item in raw:
                    diagnostics.append(validate_diagnostic(item, name))
            except Exception as exc:
                failure = str(exc)
                return []
            files.pop("diagnostics.json", None)
        return files

    for phase in PHASES:
        procs = [p for p in manifest["processors"] if phase in p["phases"]]
        procs.sort(key=lambda p: (p["_priority"], p["name"]))
        rounds = args.max_rounds if phase == "Generate" else 1
        round_no = 1
        while round_no <= rounds:
            changed = False
            for proc in procs:
                files = invoke(proc, phase, round_no)
                if failure:
                    break
                for rel, data in files.items():
                    if rel.startswith("diagnostics"):
                        continue
                    if rel not in proc.get("outputs", []):
                        failure = f"processor {proc['name']} wrote undeclared output: {rel}"
                        break
                    if rel.endswith(".x"):
                        head = data[:200].decode("utf-8", "ignore")
                        if "generated" not in head or proc["name"] not in head:
                            failure = f"processor {proc['name']} output lacks generated marker: {rel}"
                            break
                    if phase == "Finalize":
                        failure = f"processor {proc['name']} wrote file in Finalize: {rel}"
                        break
                    if generated.get(rel) != data:
                        generated[rel] = data
                        target = out / rel
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(data)
                        changed = True
                if failure:
                    break
            if failure or phase != "Generate" or not changed:
                break
            try:
                next_ir = run_mini_ir(args.entry, args.xdk_root)
                json.loads(next_ir)
                (out / "ir.json").write_text(next_ir, encoding="utf-8")
            except Exception:
                pass
            round_no += 1
        if failure:
            break
        if phase == "Generate" and round_no > args.max_rounds:
            failure = f"Generate did not converge after {args.max_rounds} rounds"

    if failure:
        platform_error(failure)

    merged = merge_diagnostics(diagnostics)
    report = {
        "sandboxBackend": SANDBOX_BACKEND,
        "sandboxProfile": str(out / ".processors"),
        "limits": {
            "maxMemoryMB": max((p["_sandbox"]["maxMemoryMB"] for p in manifest["processors"]), default=0),
            "maxCpuSeconds": max((p["_sandbox"]["maxCpuSeconds"] for p in manifest["processors"]), default=0),
        },
        "processors": reports,
    }
    (out / "diagnostics.json").write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for d in merged:
        print(f"{d['severity']} [{d['code']}] {d['message']} at {d['line']}:{d['col']}", file=sys.stderr)
    if not failure and not any(d["severity"] == "Error" for d in merged):
        for rel in stub_paths:
            if rel not in generated:
                try:
                    (out / rel).unlink()
                except FileNotFoundError:
                    pass
    if failure or any(d["severity"] == "Error" for d in merged):
        if args.generated_dir:
            artifact = out.parent / (out.name + ".diagnostics.json")
            artifact.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (out.parent / (out.name + ".report.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            shutil.rmtree(out)
            if backup is not None and backup.exists():
                backup.rename(out)
        return 1
    if backup is not None and backup.exists():
        shutil.rmtree(backup)
    return 0


def check_manifest(args):
    try:
        load_manifest(args.manifest)
    except ValueError as exc:
        return manifest_error(str(exc))
    print("annotation_platform: manifest OK")
    return 0


def check_generated(args):
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        gen = argparse.Namespace(
            entry=args.entry, xdk_root=args.xdk_root, manifest=args.manifest,
            out=None, generated_dir=str(Path(td) / "generated"), max_rounds=3,
        )
        rc = generate(gen)
        if rc != 0:
            return rc
        actual = Path(td) / "generated"
        expected = Path(args.generated_dir)
        expected_files = {k: v for k, v in snapshot(expected).items() if k.endswith(".x")}
        actual_files = {k: v for k, v in snapshot(actual).items() if k.endswith(".x")}
        for name in sorted(set(expected_files) | set(actual_files)):
            if name not in expected_files:
                return fail(f"generated source missing in target: {name}")
            if name not in actual_files:
                return fail(f"extra generated source: {name}")
            if expected_files[name] != actual_files[name]:
                return fail(f"generated source differs: {name}")
        print("annotation_platform: generated sources match")
        return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("--entry", required=True)
    gen.add_argument("--xdk-root", required=True)
    gen.add_argument("--manifest", required=True)
    gen.add_argument("--out")
    gen.add_argument("--generated-dir")
    gen.add_argument("--max-rounds", type=int, default=3)
    chk = sub.add_parser("check-manifest")
    chk.add_argument("--manifest", required=True)
    check = sub.add_parser("check")
    check.add_argument("--entry", required=True)
    check.add_argument("--xdk-root", required=True)
    check.add_argument("--manifest", required=True)
    check.add_argument("--generated-dir", required=True)
    args = parser.parse_args()
    if args.command == "generate":
        return generate(args)
    if args.command == "check":
        return check_generated(args)
    return check_manifest(args)


if __name__ == "__main__":
    sys.exit(main())
