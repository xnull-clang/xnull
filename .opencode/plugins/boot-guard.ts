import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"

const MARKER = "<!-- xnull-boot -->"

function bootReport(root: string, sessionID?: string): string {
  const boot = join(root, ".agent", "bin", "boot.py")
  if (!existsSync(boot)) return ""
  try {
    return execFileSync("python3", [boot], {
      cwd: root,
      encoding: "utf8",
      timeout: 15000,
      env: { ...process.env, OPENCODE_SESSION_ID: sessionID ?? "", BOOT_FAST: "1" },
    }).trim()
  } catch (error) {
    const stdout = (error as { stdout?: string }).stdout ?? ""
    if (stdout.trim()) return stdout.trim()
    return `BOOT: ERROR\n- boot.py failed: ${(error as Error).message}`
  }
}

export default Plugin.define({
  id: "xnull.boot-guard",
  async setup(ctx) {
    const root = ctx.location.project?.canonical ?? ctx.location.directory

    const registration = await ctx.session.hook("prompt", (event) => {
      try {
        if (event.prompt.text.includes(MARKER)) return
        const sessionID = (event as { sessionID?: string }).sessionID
        const report = bootReport(root, sessionID)
        if (!report) return

        if (report.startsWith("BOOT: BLOCKED")) {
          const blocked = join(root, ".agent", "state", "blocked")
          mkdirSync(blocked, { recursive: true })
          const stamp = new Date().toISOString().replace(/[:.]/g, "-")
          writeFileSync(
            join(blocked, `${sessionID ?? "unknown"}-${stamp}.md`),
            event.prompt.text,
            "utf8",
          )
          event.prompt.text =
            `${MARKER}\n[BOOT]\n${report}\n[/BOOT]\n` +
            "BLOCKED: 不得执行原任务。先处理上述阻塞项（如完成复盘）；" +
            "处理完后让用户重新发送原任务。原任务已暂存到 `.agent/state/blocked/`。"
          return
        }

        const state = report.match(/^- state: (.+)$/m)?.[1] ?? "ok";
        if (report.startsWith("BOOT: OK") && state === "ok") {
          const role = report.match(/^- role: (.+)$/m)?.[1] ?? "?";
          const batch = report.match(/^- batch: (.+)$/m)?.[1] ?? "?";
          event.prompt.text =
            `${MARKER}\n[BOOT] OK · role=${role} · ${batch}\n[/BOOT]\n\n${event.prompt.text}`;
          return;
        }

        event.prompt.text = `${MARKER}\n[BOOT]\n${report}\n[/BOOT]\n按 NEXT 执行。\n\n${event.prompt.text}`
      } catch {
        // Never block admission because the guard itself failed.
      }
    })

    return () => registration.dispose()
  },
})
