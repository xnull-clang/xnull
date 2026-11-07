import { spawn } from "child_process";
import * as vscode from "vscode";
import { ToolchainResult } from "./types";

export function toolchainPath(): string {
  const configured = vscode.workspace
    .getConfiguration("xnull")
    .get<string>("toolchainPath", "xnull")
    .trim();
  return configured.length > 0 ? configured : "xnull";
}

export function runtimePath(): string {
  return vscode.workspace
    .getConfiguration("xnull")
    .get<string>("runtimePath", "")
    .trim();
}

export function defaultOutput(): string {
  const configured = vscode.workspace
    .getConfiguration("xnull")
    .get<string>("defaultOutput", "target")
    .trim();
  return configured.length > 0 ? configured : "target";
}

export function runToolchain(args: string[], cwd?: string): Promise<ToolchainResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(toolchainPath(), args, {
      cwd,
      shell: false,
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (err: NodeJS.ErrnoException) => {
      if (err.code === "ENOENT") {
        reject(
          new Error(
            `找不到 XNull 工具链：${toolchainPath()}。请设置 xnull.toolchainPath，或把 xnull 加入 PATH。`
          )
        );
        return;
      }
      reject(err);
    });
    child.on("close", (code: number | null) => {
      resolve({ code: code ?? -1, stdout, stderr });
    });
  });
}

export async function runToolchainJson<T>(
  args: string[],
  cwd?: string
): Promise<{ result: ToolchainResult; json: T | undefined }> {
  const result = await runToolchain(args, cwd);
  const text = result.stdout.trim();
  if (text.length === 0) {
    return { result, json: undefined };
  }
  try {
    return { result, json: JSON.parse(text) as T };
  } catch (err) {
    throw new Error(
      `工具链返回的 JSON 无法解析：${err instanceof Error ? err.message : String(err)}`
    );
  }
}

export function shellQuote(value: string): string {
  if (process.platform === "win32") {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return `'${value.replace(/'/g, "'\\''")}'`;
}
