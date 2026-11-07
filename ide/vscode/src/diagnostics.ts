import * as path from "path";
import * as vscode from "vscode";
import { JsonDiagnostic } from "./types";

export class DiagnosticManager implements vscode.Disposable {
  private readonly collection: vscode.DiagnosticCollection;

  constructor() {
    this.collection = vscode.languages.createDiagnosticCollection("xnull");
  }

  clear(): void {
    this.collection.clear();
  }

  publish(file: string, diagnostics: JsonDiagnostic[]): void {
    const uri = this.uriFor(file);
    if (diagnostics.length === 0) {
      this.collection.delete(uri);
      return;
    }
    const items = diagnostics.map((d) => {
      const line = Math.max(0, (d.line || 1) - 1);
      const column = Math.max(0, (d.column || 1) - 1);
      const width = Math.max(1, d.width || 1);
      const range = new vscode.Range(line, column, line, column + width);
      const message = d.hint ? `${d.message}\n${d.hint}` : d.message;
      const diagnostic = new vscode.Diagnostic(range, message, vscode.DiagnosticSeverity.Error);
      diagnostic.code = d.code;
      diagnostic.source = "xnull";
      return diagnostic;
    });
    this.collection.set(uri, items);
  }

  dispose(): void {
    this.collection.dispose();
  }

  private uriFor(file: string): vscode.Uri {
    if (path.isAbsolute(file)) {
      return vscode.Uri.file(file);
    }
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (folder) {
      return vscode.Uri.file(path.join(folder, file));
    }
    return vscode.Uri.file(file);
  }
}
