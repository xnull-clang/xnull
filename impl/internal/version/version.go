// Package version 记录工具链版本体系：版本号、commit、构建日期、规范集与运行时 ABI。
// 构建时可用 -ldflags -X 注入 Commit/BuildDate；未注入时回退 dev/unknown。
package version

import "strings"

// Base 是工具链语义化版本（B4 前保持 0.x）。
const Base = "0.1.0-dev"

// ABI 是运行时 ABI 版本。
const ABI = "v1"

// SpecSet 是当前规范集版本（与工具链版本独立）。
const SpecSet = "S1 v3.3.0, S2 v3.3.0, S3 v3.0.0, S4 v1.0.0, S5 v1.0.0, S6 v1.1.0, S7 v1.0.0, S8 v5.2.0"

// Commit 与 BuildDate 由 ldflags 注入（未注入回退）。
var (
	Commit    = "dev"
	BuildDate = "unknown"
)

// ShortCommit 返回 commit 前 7 位（dev 原样）。
func ShortCommit() string {
	if Commit == "" || Commit == "dev" {
		return "dev"
	}
	if len(Commit) > 7 {
		return Commit[:7]
	}
	return Commit
}

// Full 返回工具链完整版本：<Base>[+<短哈希>]。
func Full() string {
	short := ShortCommit()
	if short == "dev" {
		return Base
	}
	return Base + "+" + short
}

// Info 返回多行版本信息（version/--version 共用）。
func Info() string {
	var b strings.Builder
	b.WriteString(Full() + "\n")
	b.WriteString("commit: " + Commit + "\n")
	b.WriteString("build date: " + BuildDate + "\n")
	b.WriteString("specs: " + SpecSet + "\n")
	b.WriteString("abi: " + ABI + "\n")
	return b.String()
}
