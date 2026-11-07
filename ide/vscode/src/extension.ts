import * as vscode from "vscode";
import {
  defaultOutput,
  runToolchain,
  runtimePath,
  shellQuote,
  toolchainPath,
} from "./cli";
import { DiagnosticManager } from "./diagnostics";
import {
  binaryOutput,
  buildFile,
  checkFile,
  newProject,
  workspaceRoot,
} from "./project";
import { StdlibIndex } from "./stdlib";
import { BuildResult } from "./types";

let diagnostics: DiagnosticManager;
let output: vscode.OutputChannel;
let status: vscode.StatusBarItem;
let stdlib: StdlibIndex;

export function activate(context: vscode.ExtensionContext): void {
  diagnostics = new DiagnosticManager();
  output = vscode.window.createOutputChannel("XNull");
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  status.text = "$(symbol-method) XNull";
  status.tooltip = "XNull IDE";
  status.command = "xnull.ide.doctor";
  status.show();
  stdlib = new StdlibIndex(context.extensionPath);

  context.subscriptions.push(
    diagnostics,
    output,
    status,
    vscode.commands.registerCommand("xnull.ide.newProject", () => newProject()),
    vscode.commands.registerCommand("xnull.ide.check", () => checkActive()),
    vscode.commands.registerCommand("xnull.ide.build", () => buildActive("build")),
    vscode.commands.registerCommand("xnull.ide.packageBinary", () => buildActive("package")),
    vscode.commands.registerCommand("xnull.ide.run", () => runActive()),
    vscode.commands.registerCommand("xnull.ide.showStdlib", () => stdlib.show()),
    vscode.commands.registerCommand("xnull.ide.doctor", () => doctor())
  );

  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.languageId !== "xnull") {
        return;
      }
      if (!vscode.workspace.getConfiguration("xnull").get<boolean>("checkOnSave", true)) {
        return;
      }
      void checkDocument(doc);
    })
  );
}

export function deactivate(): void {
  // Disposables are owned by the extension context.
}

async function savedActiveFile(): Promise<string | undefined> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "xnull") {
    return undefined;
  }
  if (editor.document.isDirty) {
    const saved = await editor.document.save();
    if (!saved) {
      return undefined;
    }
  }
  return editor.document.uri.fsPath;
}

async function checkActive(): Promise<void> {
  const file = await savedActiveFile();
  if (!file) {
    vscode.window.showWarningMessage("请先打开一个 .x 文件。");
    return;
  }
  await checkPath(file);
}

async function checkDocument(doc: vscode.TextDocument): Promise<void> {
  await checkPath(doc.uri.fsPath);
}

async function checkPath(file: string): Promise<void> {
  try {
    status.text = "$(sync~spin) XNull: Checking";
    const result = await checkFile(file);
    if (!result) {
      throw new Error("检查没有返回结果");
    }
    diagnostics.publish(file, result.diagnostics);
    if (result.diagnostics.length > 0) {
      status.text = "$(error) XNull";
      output.appendLine(`[check] ${file}: ${result.diagnostics.length} 个诊断`);
      if (vscode.workspace.getConfiguration("xnull").get<boolean>("autoOpenProblems", true)) {
        await vscode.commands.executeCommand("workbench.actions.view.problems");
      }
    } else {
      status.text = "$(check) XNull";
      output.appendLine(`[check] ${file}: ok`);
    }
  } catch (err) {
    status.text = "$(error) XNull";
    const message = err instanceof Error ? err.message : String(err);
    output.appendLine(`[check] ${message}`);
    vscode.window.showErrorMessage(message);
  }
}

async function buildActive(mode: "build" | "package"): Promise<void> {
  const file = await savedActiveFile();
  if (!file) {
    vscode.window.showWarningMessage("请先打开一个 .x 文件。");
    return;
  }
  const outputPath = binaryOutput(file);
  await vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: mode === "package" ? "XNull: Packaging Binary" : "XNull: Building",
      cancellable: false,
    },
    async () => {
      try {
        status.text = "$(sync~spin) XNull: Building";
        const result = await buildFile(file, outputPath);
        if (!result) {
          throw new Error("构建没有返回结果");
        }
        publishBuild(result);
        if (result.ok) {
          status.text = "$(check) XNull";
          const label = mode === "package" ? "单文件二进制已生成" : "构建成功";
          vscode.window.showInformationMessage(`${label}：${result.output ?? outputPath}`);
          output.appendLine(`[build] ok: ${result.output ?? outputPath}`);
        } else {
          status.text = "$(error) XNull";
          output.appendLine(`[build] failed: ${result.log ?? result.exitCode}`);
          vscode.window.showErrorMessage("XNull 构建失败，详见输出面板。");
        }
      } catch (err) {
        status.text = "$(error) XNull";
        const message = err instanceof Error ? err.message : String(err);
        output.appendLine(`[build] ${message}`);
        vscode.window.showErrorMessage(message);
      }
    }
  );
}

function publishBuild(result: BuildResult): void {
  if (result.diagnostics.length > 0) {
    diagnostics.publish(result.file, result.diagnostics);
  }
  if (result.log) {
    output.appendLine(result.log.trimEnd());
  }
}

async function runActive(): Promise<void> {
  const file = await savedActiveFile();
  if (!file) {
    vscode.window.showWarningMessage("请先打开一个 .x 文件。");
    return;
  }
  const cwd = workspaceRoot(file);
  const terminal = vscode.window.createTerminal({
    name: "XNull Run",
    cwd,
  });
  const parts = [toolchainPath(), "run", file];
  const runtime = runtimePath();
  if (runtime.length > 0) {
    parts.push("--runtime", runtime);
  }
  terminal.show();
  terminal.sendText(parts.map(shellQuote).join(" "));
}

async function doctor(): Promise<void> {
  const config = vscode.workspace.getConfiguration("xnull");
  output.appendLine("== XNull Doctor ==");
  output.appendLine(`toolchain: ${toolchainPath()}`);
  output.appendLine(`runtime: ${config.get<string>("runtimePath", "") || "(auto)"}`);
  output.appendLine(`defaultOutput: ${defaultOutput()}`);
  output.appendLine(`workspace: ${workspaceRoot() ?? "(none)"}`);
  try {
    const result = await runToolchain(["--version"]);
    output.appendLine(`version: ${result.stdout.trim() || result.stderr.trim()}`);
    output.show(true);
    vscode.window.showInformationMessage(
      `XNull 工具链：${result.stdout.trim() || "未知版本"}`
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    output.appendLine(message);
    output.show(true);
    vscode.window.showErrorMessage(message);
  }
}
