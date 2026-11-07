import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { XdkIndex, XdkItem, XdkPackage } from "./types";

export class StdlibIndex {
  private readonly indexPath: string;
  private cache: XdkIndex | undefined;

  constructor(extensionPath: string) {
    const local = path.join(extensionPath, "xdk", "index.json");
    const shared = path.join(extensionPath, "..", "xdk", "index.json");
    this.indexPath = fs.existsSync(local) ? local : shared;
  }

  load(): XdkIndex | undefined {
    if (this.cache) {
      return this.cache;
    }
    try {
      const raw = fs.readFileSync(this.indexPath, "utf8");
      this.cache = JSON.parse(raw) as XdkIndex;
      return this.cache;
    } catch {
      return undefined;
    }
  }

  async show(): Promise<void> {
    const index = this.load();
    if (!index) {
      vscode.window.showErrorMessage(`找不到 XDK 索引：${this.indexPath}`);
      return;
    }
    const picked = await vscode.window.showQuickPick(
      index.packages.map((pkg) => ({
        label: pkg.name,
        description: pkg.summary,
        detail: `稳定性：${pkg.stability}`,
        pkg,
      })),
      { title: `XDK ${index.version}`, placeHolder: "选择 XDK 包" }
    );
    if (!picked) {
      return;
    }
    const item = await vscode.window.showQuickPick(
      picked.pkg.items.map((entry) => ({
        label: entry.name,
        description: entry.signature,
        detail: entry.summary,
        entry,
      })),
      { title: picked.pkg.name, placeHolder: "选择 API" }
    );
    if (item) {
      vscode.window.showInformationMessage(
        `${picked.pkg.name}.${item.entry.name}\n${item.entry.signature}\n${item.entry.summary}`,
        { modal: true }
      );
    }
  }

  allPackages(): XdkPackage[] {
    return this.load()?.packages ?? [];
  }

  items(): XdkItem[] {
    return this.allPackages().flatMap((pkg) => pkg.items);
  }
}
