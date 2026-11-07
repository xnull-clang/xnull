import * as path from "path";
import * as vscode from "vscode";
import { defaultOutput, runToolchainJson, runtimePath } from "./cli";
import {
  BuildResult,
  CheckResult,
  NewProjectResult,
} from "./types";

export function activeXNullFile(): string | undefined {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "xnull") {
    return undefined;
  }
  return editor.document.uri.fsPath;
}

export function workspaceRoot(file?: string): string | undefined {
  const folder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (folder) {
    return folder;
  }
  if (file) {
    return path.dirname(file);
  }
  return undefined;
}

export function binaryOutput(file: string): string {
  const root = workspaceRoot(file) ?? path.dirname(file);
  const name = path.parse(file).name;
  return path.join(root, defaultOutput(), name);
}

export async function newProject(): Promise<void> {
  const name = await vscode.window.showInputBox({
    title: "XNull: New Project",
    prompt: "工程目录名",
    value: "hello-xnull",
    validateInput: (value) =>
      value.trim().length === 0 ? "目录名不能为空" : undefined,
  });
  if (!name) {
    return;
  }
  const parent = await vscode.window.showOpenDialog({
    canSelectFiles: false,
    canSelectFolders: true,
    canSelectMany: false,
    openLabel: "选择父目录",
  });
  if (!parent || parent.length === 0) {
    return;
  }
  const target = path.join(parent[0].fsPath, name.trim());
  const { result, json } = await runToolchainJson<NewProjectResult>(
    ["new", "app", target, "--json"],
    parent[0].fsPath
  );
  if (!json?.ok) {
    const message = json?.error ?? result.stderr.trim() ?? "创建工程失败";
    vscode.window.showErrorMessage(message);
    return;
  }
  vscode.window.showInformationMessage(`已创建 XNull 工程：${target}`);
  await vscode.commands.executeCommand(
    "vscode.openFolder",
    vscode.Uri.file(target),
    { forceNewWindow: false }
  );
}

export async function checkFile(file: string): Promise<CheckResult | undefined> {
  const { result, json } = await runToolchainJson<CheckResult>(
    ["check", file, "--json"],
    workspaceRoot(file)
  );
  if (!json) {
    throw new Error(result.stderr.trim() || "检查失败：没有返回 JSON");
  }
  return json;
}

export async function buildFile(
  file: string,
  output: string
): Promise<BuildResult | undefined> {
  const args = ["build", file, "--json", "-o", output];
  const runtime = runtimePath();
  if (runtime.length > 0) {
    args.push("--runtime", runtime);
  }
  const { result, json } = await runToolchainJson<BuildResult>(
    args,
    workspaceRoot(file)
  );
  if (!json) {
    throw new Error(result.stderr.trim() || "构建失败：没有返回 JSON");
  }
  return json;
}
