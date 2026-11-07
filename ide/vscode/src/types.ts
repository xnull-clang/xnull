export interface JsonDiagnostic {
  file: string;
  line: number;
  column: number;
  code: string;
  message: string;
  hint?: string;
  snippet?: string;
  width?: number;
}

export interface CheckResult {
  ok: boolean;
  file: string;
  diagnostics: JsonDiagnostic[];
}

export interface BuildResult {
  ok: boolean;
  file: string;
  output?: string;
  exitCode: number;
  diagnostics: JsonDiagnostic[];
  log?: string;
}

export interface NewProjectResult {
  ok: boolean;
  template?: string;
  directory?: string;
  files?: string[];
  error?: string;
}

export interface XdkItem {
  name: string;
  signature: string;
  summary: string;
}

export interface XdkPackage {
  name: string;
  summary: string;
  stability: string;
  items: XdkItem[];
}

export interface XdkIndex {
  version: string;
  source: string;
  note?: string;
  packages: XdkPackage[];
}

export interface ToolchainResult {
  code: number;
  stdout: string;
  stderr: string;
}
