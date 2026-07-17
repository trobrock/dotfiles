import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { Type, type Static } from "typebox";

const CUSTOM_TYPE = "dream";
const STATUS_DIRS = ["inbox", "accepted", "ticketed", "in_progress", "rejected", "archive"] as const;
type DreamStatus = typeof STATUS_DIRS[number];

type DreamCandidate = {
  id: string;
  title: string;
  kind: string;
  confidence: "high" | "medium" | "low";
  impact: "high" | "medium" | "low";
  risk: "low" | "medium" | "high";
  score: number;
  evidence: string[];
  files: string[];
  proposed_work: string;
  validation: string[];
  estimated_diff: string;
  autonomous_patch_allowed: boolean;
};

type DreamReport = {
  id: string;
  status: DreamStatus;
  createdAt: string;
  updatedAt: string;
  mode: string;
  recipe: string;
  repo: { path: string; name: string; branch?: string | null; head?: string | null; dirty?: boolean };
  summary?: string;
  candidates: DreamCandidate[];
  rejectionReason?: string;
  developerlyActions?: Array<Record<string, unknown>>;
};

type FoundDream = {
  report: DreamReport;
  jsonPath: string;
  mdPath: string;
};

const DreamToolParams = Type.Object({
  action: StringEnum(["list", "show", "accept", "reject", "archive", "ticket", "implement"] as const),
  id: Type.Optional(Type.String({ description: "Dream report ID or unique prefix for show/accept/reject/archive/ticket/implement" })),
  candidate: Type.Optional(Type.String({ description: "Candidate ID, such as C1, for ticket/implement" })),
  status: Type.Optional(StringEnum(["inbox", "accepted", "ticketed", "in_progress", "rejected", "archive", "all"] as const)),
  reason: Type.Optional(Type.String({ description: "Reason when rejecting a dream report" })),
  dryRun: Type.Optional(Type.Boolean({ description: "For ticket/implement, show the Developerly command without creating anything" })),
});

type DreamToolInput = Static<typeof DreamToolParams>;

function stateRoot(): string {
  const root = process.env.PI_DREAM_HOME
    ?? join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state"), "pi-dream");
  return resolve(root.replace(/^~(?=\/|$)/, homedir()));
}

function ensureStateDirs(root = stateRoot()): void {
  mkdirSync(root, { recursive: true });
  for (const status of STATUS_DIRS) mkdirSync(join(root, status), { recursive: true });
}

function readDream(file: string): DreamReport | undefined {
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as DreamReport;
    if (!parsed?.id || !Array.isArray(parsed.candidates)) return undefined;
    return parsed;
  } catch {
    return undefined;
  }
}

function listDreams(status: DreamStatus | "all" = "inbox"): DreamReport[] {
  ensureStateDirs();
  const statuses = status === "all" ? STATUS_DIRS : [status];
  const reports: DreamReport[] = [];

  for (const currentStatus of statuses) {
    const dir = join(stateRoot(), currentStatus);
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir)) {
      if (!entry.endsWith(".json")) continue;
      const report = readDream(join(dir, entry));
      if (report) reports.push(report);
    }
  }

  return reports.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}

function findDream(id: string): FoundDream | undefined {
  ensureStateDirs();
  const matches: FoundDream[] = [];

  for (const status of STATUS_DIRS) {
    const dir = join(stateRoot(), status);
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir)) {
      if (!entry.endsWith(".json")) continue;
      if (!entry.startsWith(id) && !entry.includes(id)) continue;
      const jsonPath = join(dir, entry);
      const report = readDream(jsonPath);
      if (!report) continue;
      if (report.id === id || report.id.startsWith(id)) {
        matches.push({ report, jsonPath, mdPath: join(dir, `${report.id}.md`) });
      }
    }
  }

  if (matches.length > 1) throw new Error(`Ambiguous dream id '${id}': ${matches.map((match) => match.report.id).join(", ")}`);
  return matches[0];
}

function moveDream(id: string, targetStatus: DreamStatus, reason?: string): DreamReport {
  const found = findDream(id);
  if (!found) throw new Error(`Dream report not found: ${id}`);

  const report = {
    ...found.report,
    status: targetStatus,
    updatedAt: new Date().toISOString(),
  };
  if (targetStatus === "rejected") report.rejectionReason = reason?.trim() || "No reason recorded.";

  const targetDir = join(stateRoot(), targetStatus);
  mkdirSync(targetDir, { recursive: true });
  const jsonPath = join(targetDir, `${report.id}.json`);
  const mdPath = join(targetDir, `${report.id}.md`);
  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(mdPath, formatDream(report));

  for (const oldPath of [found.jsonPath, found.mdPath]) {
    if (oldPath !== jsonPath && oldPath !== mdPath && existsSync(oldPath)) unlinkSync(oldPath);
  }

  return report;
}

function formatDreamList(reports: DreamReport[], status = "inbox"): string {
  if (reports.length === 0) return `No ${status} dream reports.`;

  const lines = [`# Dream ${status}`, ""];
  for (const report of reports) {
    const top = report.candidates[0];
    lines.push(`- ${report.id}`);
    lines.push(`  - Repo: ${report.repo.name} (${report.repo.branch ?? "unknown"})`);
    lines.push(`  - Recipe: ${report.recipe}; candidates: ${report.candidates.length}`);
    if (top) lines.push(`  - Top: ${top.score} ${top.confidence}/${top.risk} — ${top.title}`);
    if (report.summary) lines.push(`  - Summary: ${report.summary}`);
  }
  lines.push("");
  lines.push("Commands: /dream show <id>, /dream accept <id>, /dream ticket <id> <candidate>, /dream implement <id> <candidate>, /dream reject <id> <reason>, /dream archive <id>, /dream review, /dream run [repo]");
  return lines.join("\n");
}

function formatDream(report: DreamReport): string {
  const lines = [`# Pi Dream Report: ${report.id}`, ""];
  lines.push(`- Status: ${report.status}`);
  lines.push(`- Repo: ${report.repo.path}`);
  lines.push(`- Branch: ${report.repo.branch ?? "unknown"}`);
  lines.push(`- Head: ${report.repo.head ?? "unknown"}`);
  lines.push(`- Recipe: ${report.recipe}`);
  lines.push(`- Mode: ${report.mode}`);
  lines.push(`- Created: ${report.createdAt}`);
  if (report.rejectionReason) lines.push(`- Rejection reason: ${report.rejectionReason}`);
  if (Array.isArray(report.developerlyActions) && report.developerlyActions.length > 0) {
    lines.push(`- Developerly actions: ${report.developerlyActions.length}`);
  }
  lines.push("");
  lines.push("## Summary", "", report.summary || "No summary provided.", "", "## Candidates", "");

  if (!report.candidates.length) lines.push("No candidates found.");
  for (const candidate of report.candidates) {
    lines.push(`### ${candidate.id}: ${candidate.title}`, "");
    lines.push(`- Kind: ${candidate.kind}`);
    lines.push(`- Score: ${candidate.score}`);
    lines.push(`- Confidence: ${candidate.confidence}`);
    lines.push(`- Impact: ${candidate.impact}`);
    lines.push(`- Risk: ${candidate.risk}`);
    lines.push(`- Estimated diff: ${candidate.estimated_diff}`);
    lines.push(`- Autonomous patch allowed: ${candidate.autonomous_patch_allowed ? "yes" : "no"}`);
    lines.push("", "Evidence:");
    (candidate.evidence.length ? candidate.evidence : ["none supplied"]).forEach((item) => lines.push(`- ${item}`));
    lines.push("", "Files:");
    (candidate.files.length ? candidate.files : ["none supplied"]).forEach((file) => lines.push(`- ${file}`));
    lines.push("", "Proposed work:", candidate.proposed_work, "", "Validation:");
    (candidate.validation.length ? candidate.validation : ["none supplied"]).forEach((command) => lines.push(`- ${command}`));
    lines.push("");
  }

  return lines.join("\n");
}

function renderDreamMessage(text: string, theme: Theme) {
  return new Text(theme.fg("accent", "dream") + "\n" + text, 0, 0);
}

function parseCommandArgs(input: string): string[] {
  const output: string[] = [];
  let current = "";
  let quote: string | undefined;
  let escaping = false;

  for (const char of input.trim()) {
    if (escaping) {
      current += char;
      escaping = false;
      continue;
    }
    if (char === "\\") {
      escaping = true;
      continue;
    }
    if (quote) {
      if (char === quote) quote = undefined;
      else current += char;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current) {
        output.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }
  if (current) output.push(current);
  return output;
}

function commandPath(): string {
  if (process.env.PI_DREAM_BIN) return process.env.PI_DREAM_BIN;
  const configScript = join(homedir(), ".config", "scripts", "pi-dream");
  if (existsSync(configScript)) return configScript;
  const dotfilesScript = join(homedir(), "dotfiles", "dot-config", "scripts", "pi-dream");
  if (existsSync(dotfilesScript)) return dotfilesScript;
  return configScript;
}

async function runPiDream(args: string[], cwd: string): Promise<{ ok: boolean; text: string; json?: unknown }> {
  const finalArgs = [...args, "--json"];

  return new Promise((resolvePromise) => {
    const proc = spawn(commandPath(), finalArgs, {
      cwd,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    proc.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    proc.on("error", (error) => resolvePromise({ ok: false, text: error.message }));
    proc.on("close", (code) => {
      if (code !== 0) {
        resolvePromise({ ok: false, text: stderr || stdout || `pi-dream exited with ${code}` });
        return;
      }
      try {
        const parsed = JSON.parse(stdout);
        if (args[0] === "scout") {
          resolvePromise({ ok: true, text: `Created dream report ${parsed.id}\n${parsed.paths?.markdown ?? parsed.paths?.json ?? ""}`, json: parsed });
          return;
        }
        resolvePromise({ ok: true, text: stdout.trim(), json: parsed });
      } catch {
        resolvePromise({ ok: true, text: stdout.trim() || "Dream command finished." });
      }
    });
  });
}

function toolResultFor(action: DreamToolInput["action"], params: DreamToolInput) {
  if (action === "list") {
    const status = (params.status ?? "inbox") as DreamStatus | "all";
    const reports = listDreams(status);
    return { text: formatDreamList(reports, status), details: { reports } };
  }

  if (!params.id) throw new Error(`id is required for action '${action}'`);

  if (action === "show") {
    const found = findDream(params.id);
    if (!found) throw new Error(`Dream report not found: ${params.id}`);
    return { text: formatDream(found.report), details: { report: found.report } };
  }

  if (action === "ticket" || action === "implement") {
    if (!params.candidate) throw new Error(`candidate is required for action '${action}'`);
    throw new Error(`${action} must be run with /dream ${action} <id> <candidate> so the Developerly side effect is explicit.`);
  }

  const target = action === "accept" ? "accepted" : action === "reject" ? "rejected" : "archive";
  const report = moveDream(params.id, target, params.reason);
  return { text: `${report.id} -> ${target}`, details: { report } };
}

export default function (pi: ExtensionAPI) {
  pi.registerMessageRenderer(CUSTOM_TYPE, (message, _options, theme) => renderDreamMessage(String(message.content ?? ""), theme));

  function post(content: string, details?: unknown): void {
    pi.sendMessage({ customType: CUSTOM_TYPE, content, display: true, details });
  }

  pi.registerTool({
    name: "dream_inbox",
    label: "Dream Inbox",
    description: "List, show, accept, reject, archive, ticket, or implement Pi Dream scout reports from the local dream inbox.",
    promptSnippet: "Inspect and manage local Pi Dream scout reports.",
    promptGuidelines: [
      "Use dream_inbox when the user asks about overnight dream scout findings, candidate work items, or dream reports.",
      "Only use dream_inbox ticket or implement after an explicit user request because they call Developerly and may create work items or launch agents.",
      "Do not run new dream scouts with dream_inbox; it only manages existing reports.",
    ],
    parameters: DreamToolParams,
    async execute(_toolCallId, params) {
      const result = toolResultFor(params.action, params);
      return {
        content: [{ type: "text", text: result.text }],
        details: result.details,
      };
    },
  });

  pi.registerCommand("dream", {
    description: "Review and manage Pi Dream scout reports",
    getArgumentCompletions: (prefix) => {
      const commands = ["inbox", "list", "review", "show", "accept", "ticket", "implement", "reject", "archive", "run", "paths", "help"];
      const filtered = commands.filter((command) => command.startsWith(prefix));
      return filtered.length ? filtered.map((command) => ({ value: command, label: command })) : null;
    },
    handler: async (args, ctx) => {
      const parts = parseCommandArgs(args);
      const subcommand = parts[0] || "inbox";

      try {
        if (subcommand === "help") {
          post("Usage: /dream inbox | review | show <id> | accept <id> | ticket <id> <candidate> [--dry-run] | implement <id> <candidate> [--dry-run] | reject <id> <reason> | archive <id> | run [repo] [recipe] | paths");
          return;
        }

        if (subcommand === "paths") {
          post(`Dream state: ${stateRoot()}\nRunner: ${commandPath()}`);
          return;
        }

        if (subcommand === "inbox" || subcommand === "list") {
          const status = (parts[1] ?? "inbox") as DreamStatus | "all";
          post(formatDreamList(listDreams(status), status));
          return;
        }

        if (subcommand === "show") {
          const id = parts[1];
          if (!id) throw new Error("Usage: /dream show <id>");
          const found = findDream(id);
          if (!found) throw new Error(`Dream report not found: ${id}`);
          post(formatDream(found.report), found.report);
          return;
        }

        if (subcommand === "accept" || subcommand === "reject" || subcommand === "archive") {
          const id = parts[1];
          if (!id) throw new Error(`Usage: /dream ${subcommand} <id>`);
          const reason = subcommand === "reject" ? parts.slice(2).join(" ") : undefined;
          const target = subcommand === "accept" ? "accepted" : subcommand === "reject" ? "rejected" : "archive";
          const report = moveDream(id, target, reason);
          post(`${report.id} -> ${target}`, report);
          return;
        }

        if (subcommand === "ticket" || subcommand === "implement") {
          const id = parts[1];
          const candidateId = parts[2];
          if (!id || !candidateId) throw new Error(`Usage: /dream ${subcommand} <id> <candidate-id> [--dry-run]`);
          const found = findDream(id);
          if (!found) throw new Error(`Dream report not found: ${id}`);
          if (ctx.hasUI) ctx.ui.notify(`Running pi-dream ${subcommand} for ${found.report.id} ${candidateId}...`, "info");
          const result = await runPiDream([subcommand, id, candidateId, ...parts.slice(3)], found.report.repo.path);
          post(result.text, result.json);
          if (!result.ok && ctx.hasUI) ctx.ui.notify(`Dream ${subcommand} failed`, "error");
          return;
        }

        if (subcommand === "review") {
          const reports = listDreams("inbox");
          if (!reports.length) {
            post("No inbox dream reports.");
            return;
          }
          if (!ctx.hasUI) {
            post(formatDreamList(reports, "inbox"));
            return;
          }
          const labels = reports.map((report) => {
            const top = report.candidates[0];
            return `${report.id} — ${report.repo.name}${top ? ` — ${top.score}: ${top.title}` : ""}`;
          });
          const selected = await ctx.ui.select("Dream inbox", labels);
          if (!selected) return;
          const report = reports[labels.indexOf(selected)];
          const action = await ctx.ui.select(`Dream ${report.id}`, ["show", "accept", "ticket", "implement", "reject", "archive", "cancel"]);
          if (!action || action === "cancel") return;
          if (action === "show") {
            post(formatDream(report), report);
            return;
          }
          if (action === "ticket" || action === "implement") {
            const candidateId = await ctx.ui.input("Candidate ID", "C1");
            if (!candidateId) return;
            const result = await runPiDream([action, report.id, candidateId], report.repo.path);
            post(result.text);
            if (!result.ok && ctx.hasUI) ctx.ui.notify(`Dream ${action} failed`, "error");
            return;
          }
          const reason = action === "reject" ? await ctx.ui.input("Reject reason", "not useful / too risky / already done") : undefined;
          const moved = moveDream(report.id, action === "accept" ? "accepted" : action === "reject" ? "rejected" : "archive", reason);
          post(`${moved.id} -> ${moved.status}`, moved);
          return;
        }

        if (subcommand === "run") {
          const repo = resolve(parts[1] || ctx.cwd);
          const recipe = parts[2];
          if (ctx.hasUI) ctx.ui.notify(`Starting dream scout for ${basename(repo)}...`, "info");
          const result = await runPiDream(["scout", "--repo", repo, ...(recipe ? ["--recipe", recipe] : [])], repo);
          post(result.text);
          if (!result.ok && ctx.hasUI) ctx.ui.notify("Dream scout failed", "error");
          return;
        }

        throw new Error(`Unknown /dream command: ${subcommand}`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        post(`Dream error: ${message}`);
        if (ctx.hasUI) ctx.ui.notify(message, "error");
      }
    },
  });
}
