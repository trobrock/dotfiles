import type { Plugin } from "@opencode-ai/plugin"
import { appendFile } from "node:fs/promises"

const DEBUG = process.env.LLM_HOOK_DEBUG === "1"

async function log(msg: string) {
  if (!DEBUG) return
  const line = `[${new Date().toISOString()}] ${msg}\n`
  await appendFile("/tmp/llm-status-hook.log", line).catch(() => {})
}

export const NotificationsPlugin: Plugin = async ({ $ }) => {
  const hook = `${process.env.HOME}/.config/scripts/llm-status-hook`

  return {
    event: async ({ event }) => {
      if (event.type === "session.status") {
        const { status } = event.properties
        await log(`session.status: ${status.type}`)
        if (status.type === "busy") {
          await $`${hook} thinking`.quiet()
        } else if (status.type === "idle") {
          await $`${hook} waiting`.quiet()
        }
      }
      if (event.type === "session.idle") {
        await log(`session.idle`)
        await $`${hook} waiting`.quiet()
      }
      if (event.type === "permission.asked") {
        await log(`permission.asked`)
        await $`${hook} input`.quiet()
      }
      if (event.type === "permission.replied") {
        await log(`permission.replied`)
        await $`${hook} thinking`.quiet()
      }
    },
  }
}
