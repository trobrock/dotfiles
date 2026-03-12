import type { Plugin } from "@opencode-ai/plugin"

export const NotificationsPlugin: Plugin = async ({ $ }) => {
  const hook = `${process.env.HOME}/.config/scripts/llm-status-hook`

  return {
    event: async ({ event }) => {
      if (event.type === "session.status") {
        const { status } = event.properties
        if (status.type === "busy") {
          await $`${hook} thinking`.quiet()
        }
      }
      if (event.type === "session.idle") {
        await $`${hook} waiting`.quiet()
      }
      if (event.type === "permission.asked") {
        await $`${hook} input`.quiet()
      }
      if (event.type === "permission.replied") {
        await $`${hook} thinking`.quiet()
      }
    },
  }
}
