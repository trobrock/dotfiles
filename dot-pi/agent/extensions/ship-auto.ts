import { existsSync, readFileSync } from "fs";
import { join } from "path";
import type { ExtensionAPI, Model } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const DEFAULT_SHIP_MODEL = process.env.PI_SHIP_MODEL || "openai-codex/gpt-5.3-codex-spark";

function parseModelSpec(spec: string): { provider: string; modelId: string } | undefined {
  if (!spec.includes("/")) {
    return undefined;
  }

  const index = spec.indexOf("/");
  const provider = spec.slice(0, index);
  const modelId = spec.slice(index + 1);

  if (!provider || !modelId) {
    return undefined;
  }

  return { provider, modelId };
}

function stripFrontmatter(markdown: string): string {
  const match = markdown.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
  if (!match) {
    return markdown;
  }

  return markdown.slice(match[0].length);
}

function findModel(
  candidate: string | undefined,
  modelRegistry: {
    find: (provider: string, modelId: string) => Model<any> | undefined;
    getAll: () => Model<any>[];
  },
  fallbackProvider?: string,
): Model<any> | undefined {
  const trimmed = candidate?.trim();

  if (!trimmed) {
    const parsedDefault = parseModelSpec(DEFAULT_SHIP_MODEL);
    return parsedDefault ? modelRegistry.find(parsedDefault.provider, parsedDefault.modelId) : undefined;
  }

  const parsed = parseModelSpec(trimmed);
  if (parsed) {
    return modelRegistry.find(parsed.provider, parsed.modelId);
  }

  if (fallbackProvider) {
    const byCurrentProvider = modelRegistry.find(fallbackProvider, trimmed);
    if (byCurrentProvider) {
      return byCurrentProvider;
    }
  }

  for (const model of modelRegistry.getAll()) {
    if (model.id === trimmed) {
      return model;
    }
  }

  return undefined;
}

export default function shipAuto(pi: ExtensionAPI) {
  const shipPromptPath = join(getAgentDir(), "prompts", "ship.md");
  function loadShipPrompt(): string {
    if (!existsSync(shipPromptPath)) {
      throw new Error(`Ship prompt missing at ${shipPromptPath}`);
    }

    const raw = readFileSync(shipPromptPath, "utf8");
    return stripFrontmatter(raw).trim();
  }

  pi.on("input", (event) => {
    const trimmed = event.text.trim();
    if (!/^\/ship(?:\s|$)/.test(trimmed)) {
      return { action: "continue" };
    }

    return {
      action: "transform",
      text: `/ship-auto${event.text.slice("/ship".length)}`,
    };
  });

  pi.registerCommand("ship-auto", {
    description: "Ship the current branch using a cheap model, then restore your original model",
    handler: async (args, ctx) => {
      const modelArg = args.trim() || undefined;
      const originalModel = ctx.model;
      const targetModel = findModel(modelArg, ctx.modelRegistry, originalModel?.provider);

      await ctx.waitForIdle();

      if (!targetModel) {
        ctx.ui.notify(
          `Could not resolve ship model ${modelArg ? `"${modelArg}"` : `"${DEFAULT_SHIP_MODEL}"`}.`,
          "error",
        );
        return;
      }

      const shouldSwitchModel =
        !originalModel ||
        originalModel.provider !== targetModel.provider ||
        originalModel.id !== targetModel.id;
      let didSwitchForShip = false;

      if (shouldSwitchModel) {
        const modelOk = await pi.setModel(targetModel);
        if (modelOk) {
          didSwitchForShip = true;
          ctx.ui.notify(`Switched to ${targetModel.provider}/${targetModel.id} for shipping.`, "info");
        } else {
          ctx.ui.notify(
            `No API key for ship model ${targetModel.provider}/${targetModel.id}; continuing with current model.`,
            "warning",
          );
        }
      }

      try {
        const prompt = loadShipPrompt();
        pi.sendUserMessage(prompt);
        await ctx.waitForIdle();
      } finally {
        if (didSwitchForShip && originalModel) {
          await pi.setModel(originalModel);
          ctx.ui.notify(
            `Restored model to ${originalModel.provider}/${originalModel.id}.`,
            "info",
          );
        }
      }
    },
  });
}
