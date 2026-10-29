# A Ralph Wiggum Loop implementation that works™

[![@pageai/ralph-loop version](https://img.shields.io/npm/v/@pageai/ralph-loop?label=npm&style=flat)](https://www.npmjs.com/package/@pageai/ralph-loop)

📚 Full docs: [ralphloop.sh](https://ralphloop.sh)

Ralph is a long-running AI agent loop. Ralph automates software development tasks by iteratively working through a task list until completion. This allows for long running agent loops, effectively enabling AI to code for days at a time.

This is an implementation that actually works, containing a hackable script so you can configure it to your env and favorite agentic AI CLI. It's set up by default to use Claude Code in Docker Sandboxes, and supports [multiple Docker Sandboxes agents](#running-with-a-different-agentic-cli).

#### 👉 [Watch the video](https://www.youtube.com/watch?v=3TL8Ez66I3o) for an in-depth walkthrough.

[![Ralph Wiggum Loop](https://github.com/user-attachments/assets/be94b8ba-b073-489d-b07e-d11db975a907)](https://www.youtube.com/watch?v=3TL8Ez66I3o)

- [Getting Started](#getting-started)
  - [(Optional) Set up code base](#optional-set-up-code-base)
  - [1️⃣ Step 1: Install Ralph](#1️⃣-step-1-install-ralph)
  - [2️⃣ Step 2: Create a PRD + task list](#2️⃣-step-2-create-a-prd--task-list)
  - [3️⃣ Step 3: Set up the agent inside Docker Sandboxes](#3️⃣-step-3-set-up-the-agent-inside-docker-sandboxes)
  - [4️⃣ Step 4: Run Ralph](#4️⃣-step-4-run-ralph)
- [Running the Ralph Loop with custom options](#running-the-ralph-loop-with-custom-options)
  - [(Optional) Adjusting to your language/framework](#optional-adjusting-to-your-languageframework)
- [How It Works](#how-it-works)
- [How Is This Different from Other Ralphs?](#how-is-this-different-from-other-ralphs)
- [Steering the Agent](#steering-the-agent)
- [Support](#support)
  - [Promise Tags](#promise-tags)
  - [Exit Codes](#exit-codes)
- [Structure](#structure)
- [Continued Development](#continued-development)
- [Skills](#skills)
  - [Available Skills](#available-skills)
  - [Skills Directory Structure](#skills-directory-structure)
- [Reference](#reference)
  - [Docker Sandboxes](#docker-sandboxes)
  - [Playwright configuration](#playwright-configuration)
  - [Vitest configuration](#vitest-configuration)
  - [Running with a different agentic CLI](#running-with-a-different-agentic-cli)
  - [OpenCode wrapper and manual project setup](#opencode-wrapper-and-manual-project-setup)
  - [Starting from scratch](#starting-from-scratch)
- [Debugging](#debugging)
  - [How to inspect the sandbox and debug](#how-to-inspect-the-sandbox-and-debug)
  - [Allowing network access](#allowing-network-access)
  - [Authentication issues in Sandboxes / Login not persisting](#authentication-issues-in-sandboxes--login-not-persisting)
- [License](#license)

---------------------------------

## Getting Started

### (Optional) Set up code base

I recommend using a CLI to bootstrap your project with the necessary tools and dependencies, e.g.:

```bash
# for a Tanstack app:
npx @tanstack/cli create lib --add-ons eslint,form,tanstack-query,nitro --no-git

# or for a Next.js app
npx create-next-app@latest my-app --typescript --tailwind --eslint --app
```

> If you must start from a blank slate, which is not recommended, see [Starting from scratch](#starting-from-scratch). You can also go for a more barebone start by running `npx create-vite@latest src --template react-ts`

### 1️⃣ Step 1: Install Ralph

Run this in your project's directory to install Ralph.

```bash
npx @pageai/ralph-loop
```

> Docs: [ralphloop.sh](https://ralphloop.sh)

### 2️⃣ Step 2: Create a PRD + task list

Use the `prd-creator` skill to generate a PRD from your requirements.<br/>
Open up Claude Code or Cursor etc., **switch to plan mode**, and prompt it with **your requirements**. Like so:

```
Use the prd-creator skill to help me create a PRD and task list for the below requirements.

An app is already set up with React, Tailwind CSS and TypeScript.

Requirements:

- A SaaS product that helps users manage their finances.
- Target audience: Small business owners and freelancers.
- Core features:
  - Track income and expenses.
  - Create and send invoices.
  - Track payments and receipts.
  - Generate reports and insights.
  - Connect to bank accounts and credit cards.
  - Connect to accounting software.
  - Connect to payment processors.
- Use the shadcn/ui library for components.
- Integrate with Stripe for payments.
- Use Supabase for database.
- You can find env variables in the .env.example file: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, STRIPE_SECRET_KEY, etc. are available in the runtime.

// etc.
```

> Check out [the video](https://www.youtube.com/watch?v=3TL8Ez66I3o&t=403s) for a more realistic example on how to write requirements.

<details>
<summary><strong>✨ Pro tips</strong></summary>

- mention libraries and frameworks you want to use
- mention env variables, e.g. for DB, 3rd party API keys, etc. Store them in `.env` and add it to **.gitignore**
- describe user flows and journeys
- add relevant docs and UI references if applicable inside `/docs` and mention them in the requirements
- be as descriptive as possible
- *it's fine to write in your own language*

</details>
<br/>

Then, follow the Skill's instructions and verify the PRD and then tasks.<br/>
**It is highly recommended that you review individual task requirements before starting the loop. Review EACH TASK INDIVIDUALLY.**

### 3️⃣ Step 3: Set up the agent inside Docker Sandboxes

Install and sign in to Docker Sandboxes first. See Docker's [AI overview](https://docs.docker.com/ai-overview/) and [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/) for the official setup flow.

Authenticate your chosen Docker Sandboxes agent before running Ralph. Claude is the default:

```bash
./ralph.sh --login
```

Ralph prints all supported login commands, then opens the selected agent inside the correctly named sandbox. To log in to a different supported agent, pass `--agent`:

```bash
./ralph.sh --login --agent codex
```

Follow the instructions to log in to that agent. Ralph names sandboxes as `ralph-<agent>-<current-dir>-<hash8>`, for example `ralph-claude-my-app-a1b2c3d4`. To print the exact sandbox name without starting the loop, run:

```bash
./ralph.sh --print-name
./ralph.sh --print-name --agent cursor
```

Once the sandbox exists (after the first `--login` or after Ralph runs at least once), publish your dev server port to the host with `./ralph.sh --ports`. The port is captured from the dev-server URL you set during install and stored in `RALPH_DEFAULT_PORTS` in `ralph.sh`:

```bash
./ralph.sh --ports
./ralph.sh --ports --agent codex
```

👉 Answer "Yes" to `Bypass Permissions mode`, that's the exact reason why you are using the Docker sandbox.

> **Alternative: API keys** — you can configure API keys for supported agents instead of interactive login, but this is usually more expensive and not recommended. See Docker's [supported agents docs](https://docs.docker.com/ai/sandboxes/agents/) for per-agent setup details.

> If you want to use a different agentic CLI, see [Running with a different agentic CLI](#running-with-a-different-agentic-cli).

### 4️⃣ Step 4: Run Ralph

```bash
./ralph.sh -n 50 # Run Ralph Loop with 50 iterations
```

> ✍️ Note: the first iteration will be spent on ensuring the named sandbox environment is set up correctly. Expect 5 minutes to complete.

## Running the Ralph Loop with custom options

```bash
# Run the agent loop (default: 10 iterations)
./ralph.sh

# Run with custom iteration limit
./ralph.sh 5
./ralph.sh -n 5
./ralph.sh --max-iterations 5

# Run exactly one iteration
./ralph.sh --once

# Run with a different supported agent
./ralph.sh --agent codex
./ralph.sh -a cursor -n 5

# Log in to an agent inside Ralph's deterministic sandbox
./ralph.sh --login
./ralph.sh --login --agent cursor

# Publish the configured dev port to the selected agent sandbox
./ralph.sh --ports
./ralph.sh --ports --agent codex

# Print the deterministic sandbox name
./ralph.sh --print-name
./ralph.sh --print-name --agent codex

# Pass extra options to the selected agent
./ralph.sh --agent codex -- --model gpt-5.5
./ralph.sh -a gemini -- --model pro

# Show help
./ralph.sh --help
```

> NB: you might need to run `chmod +x ralph.sh` to make the script executable.

> The default "mode" is "implementation". Depending on your use case, you might want to change `.agent/PROMPT.md` to a different mode, e.g. "refactor", "review", "test" etc.

⚠️ If you want to use a different language or testing framework, see below.

### (Optional) Adjusting to your language/framework

This script assumes the following are installed:
- [Playwright](https://playwright.dev/) for e2e testing
- [Vitest](https://vitest.dev/) for unit testing
- [TypeScript](https://www.typescriptlang.org/) for type checking
- [ESLint](https://eslint.org/) for linting
- [Prettier](https://prettier.io/) for formatting

If you'd like to use a different language, testing framework etc. please adjust `.agent/PROMPT.md` to reflect your setup, server ports and startup commands etc.

👉 The loop is controlled by this prompt, which will be sent to the agent each iteration.

---------------------------------

## How It Works

Each run, Ralph will:
1. Pick the next task itself: the first task in `.agent/tasks.json` array order that doesn't pass, isn't parked, and has all its `dependencies` done (`priority` doesn't select work)
2. Hand that one task to a fresh builder, which works through `.agent/tasks/TASK-{ID}.json`
3. Let the builder run tests, linting and type checking, take screenshots, set `passes: true` and commit
4. Check the result itself: the task flipped to `passes: true`, no other task's `passes` changed, a new commit exists, and the project check passes (see below)
5. Repeat until all tasks pass, or one of the stop conditions below hits

### Running overnight

Ralph is built to be left alone. Options:

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `-n`, `--max-iterations` | 10 | Runs that count against the budget |
| `--max-stalls` | 3 | Stop after this many runs in a row without progress |
| `--iteration-timeout` | 30m | Stop a run's container after this long |
| `--max-outage` | 3h | Give up after this long of continuous environment failures |
| `--check-timeout` | 10m | Time limit for the project check |

Durations accept `90`, `90s`, `30m` or `3h`.

What each run counts as:

| Outcome | Uses a run | Stall counter |
| ------- | ---------- | ------------- |
| progress (task flipped, committed, check green) | yes | reset |
| parked (BLOCKED or DECIDE) | yes | unchanged |
| environment (provider outage, Copilot budget, auth, Docker, or a `RETRY` tag) | no | unchanged |
| timeout, nonzero exit, or no progress | yes | +1 |

Environment failures rerun the same task after 1, 2, 4, 8, then every 15 minutes. When a run doesn't count, Ralph puts `passes` back the way it was and keeps the builder's commits, and the next run gets a note about what went wrong.

**Project check.** `.agent/check.json` names a command that proves the project is healthy, and the task that makes it pass:

```json
{ "command": "npm test", "enabled_by": "TASK-4" }
```

The check runs in a fresh container once `enabled_by` passes. The run that flips the `enabled_by` task must make the check green too. Without `check.json`, Ralph warns and skips the check.

**Parking.** The foundation is every task up to and including `enabled_by` (or just the first task without `check.json`). BLOCKED or DECIDE before the foundation is done stops the loop. After that, Ralph saves the run's work on the branch `ralph/parked/TASK-ID`, resets the working branch to where the run started, records a `parked` field in `tasks.json`, and skips the task and everything that depends on it. To unpark, remove the `parked` field, then merge or cherry-pick the branch.

Ralph prints a summary of every run when it stops, also on Ctrl+C, and saves it to `.agent/history/SUMMARY-*.txt`.

## How Is This Different from Other Ralphs?

This was kept hackable so you can make it your own.<br/>
The script follows the original concepts of the Ralph Wiggum Loop, working with fresh contexts and providing clear verifiable feedback.

It also works generically with any task set.

<details>
<summary><strong>✨ Features</strong></summary>

- **PRD generation** - Creates a PRD and task list from requirements
- **Task lookup table generation** - Creates a task lookup table from the PRD
- **Task breakdown + step generation** - Breaks down each task into manageable steps
- **Iteration tracking** - Shows progress through iterations with timing
- **Stream preview** - Shows live output from the Agent
- **Step detection** - Identifies current activity (Thinking, Implementing, Testing, etc.)
- **Screenshot capture** - Captures a screenshot of the current screen
- **Notifications** - Alerts when human input is needed
- **History logging** - Saves clean output from each iteration
- **Timing** - Shows timing metrics for each iteration and total time
- **Steering** - Allows prioritizing critical work that needs to be done before the loop can continue
</details>

<br/>
Besides that:

- it allows you to dump unstructured requirements and have the agent create a PRD and task list for you.
- it uses a task lookup table with individual detailed steps → more scalable as you get 100s of tasks done.
- it's sandboxed and more secure
- it shows progress and stats so you can keep an eye on what's been done
- it instructs the agent to write and run automated tests and screenshots per task
- it provides observability and traceability of the agent's work, showing a stream of output and capturing full historical logs per iteration

## Steering the Agent

In some cases, you might notice the agent is having trouble, slowed down or struggling to overcome a blocker.

While the loop is running, you can edit the `.agent/STEERING.md` file to add critical work that needs to be done before the loop can continue.

The agent will check this file each iteration and if it finds any critical work, it will skip tasks and complete the critical work first.

## Support

The `ralph.sh` script is designed to be hackable.
It is configured to use Claude Code in Docker Sandboxes by default, and you can select another supported agent with `--agent`.
Other than OpenCode, each run uses a deterministic sandbox name in the form `ralph-<agent>-<current-dir>-<hash8>`, so different agents get separate sandboxes for the same project. On exit or double Ctrl+C, Ralph stops only the named sandbox for the current invocation. OpenCode uses the personal Docker wrapper described below and records its actual container ID for cleanup.

> NB: skills are supported by all major agentic AI CLIs via symlinks.

### Promise Tags

Ralph reads these tags from the builder's final message:
- `<promise>TASK-ID:DONE</promise>` - Informational, Ralph checks the work itself
- `<promise>RETRY:reason</promise>` - Transient trouble, wait and rerun the task
- `<promise>BLOCKED:reason</promise>` - Agent needs human help
- `<promise>DECIDE:question</promise>` - Agent needs a decision

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| 0    | All tasks finished |
| 1    | Used all runs |
| 2    | BLOCKED on a foundation task |
| 3    | DECIDE on a foundation task |
| 4    | Docker not ready on the first run, or `script`/`jq` missing |
| 5    | Invalid API key on the first run |
| 6    | Too many runs in a row without progress |
| 7    | Gave up on a long environment outage |
| 8    | Every remaining task is parked or depends on a parked task |
| 9    | Setup error: invalid `tasks.json`, no commits, or a failed bookkeeping commit |
| 130  | Ctrl+C |
| 143  | SIGTERM |

## Structure

```
.agent/
├── PROMPT.md           # Prompt sent to Agent each iteration
├── tasks.json          # Task lookup table (required)
├── tasks/              # Individual task specs (TASK-{ID}.json)
├── prd/
│   ├── PRD.md          # Product requirements document
│   └── SUMMARY.md      # Short project overview sent to Agent each iteration
├── logs/
│   └── LOG.md          # Progress log (auto-created)
├── history/            # Iteration output logs
└── skills/             # Shared skills (source of truth)
```

## Continued Development

As Ralph implements tasks, you might notice that you want some tweaks, features or even bug fixes.<br/>
To do so, you need to continue using the `prd-creator` skill to update the PRD and task list.

For example:

```
I would like to expand the PRD. Use the prd-creator skill to create these tasks:

- there is a bug in X that should be fixed by doing Y
- create a new feature that implement Z

etc.
```

It's fine to add multiple tasks at once.

## Skills

Skills are reusable agent capabilities that provide specialized knowledge and workflows. The canonical source is `.agent/skills/`, which is symlinked to multiple agent tool directories for compatibility.

### Available Skills

| Skill                         | Description                                             |
| ----------------------------- | ------------------------------------------------------- |
| `agent-browser`               | Browser automation for web apps and desktop apps        |
| `component-refactoring`       | Patterns for splitting and refactoring React components |
| `e2e-tester`                  | End-to-end testing workflows                            |
| `frontend-code-review`        | Code quality and performance review guidelines          |
| `frontend-testing`            | Unit and integration testing patterns                   |
| `mysql`                       | MySQL/InnoDB schema, indexing, query tuning, and ops    |
| `postgres`                    | PostgreSQL best practices and query optimization        |
| `prd-creator`                 | Create PRDs and task breakdowns for Ralph               |
| `shadcn`                      | Manage shadcn components, registries, and UI composition |
| `skill-creator`               | Create new skills                                       |
| `vercel-react-best-practices` | React/Next.js performance patterns                      |
| `vitest-best-practices`       | Vitest structure, assertions, mocks, async tests, and performance |
| `web-design-guidelines`       | UI/UX design principles                                 |

### Skills Directory Structure

Skills are symlinked from `.agent/skills/` to multiple locations for cross-tool compatibility:

```
 # Source of truth
.agent/skills/
    ├── component-refactoring/
    ├── e2e-tester/
    ├── postgres/
    ├── ...

# Symlinks -> .agent/skills/*
.agents/skills/*
.claude/skills/*
.codex/skills/*
.cursor/skills/*
```

## Reference

### Docker Sandboxes

Docker Sandboxes runs coding agents in isolated microVMs. Ralph uses the standalone `sbx` CLI and starts agents with a deterministic `--name` so the sandbox can be reused and stopped cleanly.

Use `./ralph.sh --login` to authenticate inside the correct named sandbox. Use `./ralph.sh --print-name` if you only need the deterministic sandbox name for debugging.

Useful Docker references:
- [Docker AI overview](https://docs.docker.com/ai-overview/) explains how Docker Sandboxes fits with Gordon, Model Runner, MCP Toolkit, and Docker Agent.
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) covers installation, usage, security, credentials, and troubleshooting.
- [Supported Docker Sandboxes agents](https://docs.docker.com/ai/sandboxes/agents/) lists the agent CLIs Docker supports.

### Playwright configuration

If you are using Playwright, here is a recommended configuration:

```typescript:playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  globalTimeout: 30 * 60 * 1000,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 3 : 6,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },


  // NB: only chromium will run in Docker (arm64).
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    }
  ],
});
```

### Vitest configuration

If you are using Vitest, here is a recommended configuration:

```typescript:vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "node",
    globals: true,
    include: ["lib/**/*.test.ts", "lib/**/*.test.tsx"],
    // setupFiles: ['./vitest.setup.ts'], // Include this if using Next.js
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});

```

If you are using Next.js, you'll also need a `vitest.setup.ts` file to mock the `next/image` and `next/link` components.

```typescript:vitest.setup.ts
import '@testing-library/jest-dom/vitest'
import { vi } from 'vitest'
import React from 'react'

// If using Next.js, mock next/image
vi.mock('next/image', () => ({
  default: ({ src, alt, ...props }: { src: string; alt: string }) => {
    return React.createElement('img', { src, alt, ...props })
  },
}))

// If using Next.js, mock next/link
vi.mock('next/link', () => ({
  default: ({
    children,
    href,
    ...props
  }: {
    children: React.ReactNode
    href: string
  }) => {
    return React.createElement('a', { href, ...props }, children)
  },
}))
```

### Running with a different agentic CLI

Ralph can run several agents without editing the script. OpenCode uses `~/bin/ocd.sh`; the others use Docker Sandboxes:

```bash
./ralph.sh --agent claude    # default
./ralph.sh --agent codex
./ralph.sh --agent copilot
./ralph.sh --agent cursor
./ralph.sh --agent gemini
./ralph.sh --agent opencode
```

You can also pass agent-specific options after Ralph's `--` separator:

```bash
./ralph.sh --agent codex -- --model gpt-5.3-codex
./ralph.sh --agent gemini -- --model pro
```

Ralph currently supports: `claude`, `codex`, `copilot`, `cursor`, `gemini`, and `opencode`.
See Docker's full list of supported agentic AI CLIs in [Docker's docs](https://docs.docker.com/ai/sandboxes/agents/).
For Docker Sandboxes agents, the agent name is part of Ralph's sandbox name, so switching agents creates or reuses that agent's own sandbox for the project.

### OpenCode wrapper and manual project setup

This checkout's OpenCode backend sources `~/bin/ocd.sh` with:

```bash
~/.opencode/bin/opencodedev --standalone run --agent ralph-build --yolo --format json
```

Each iteration starts a fresh session and a private service in its container.
The host needs Bash, `script`, `jq`, Docker, and the wrapper; OpenCode needs
working provider authentication and the globally deployed `ralph-build` agent.
`--yolo` approves permission requests, not explicit denies. Other backends still
default to Docker Sandboxes, and the default backend is still Claude.

Ralph sets `OCD_QUIET=1` to hide wrapper chatter, including prompt echoes, while
keeping errors visible. `OCD_CIDFILE` records the container to stop on exit.
Only a successfully finished final assistant message supplies OpenCode promise
tags. Tool output, reasoning, prompt echoes, and failed processes cannot finish
the loop. If the CLI emits text without a terminal event, Ralph starts a second
short-lived container to export that session, without running a model. It uses
only a completed, stopped final assistant response matching the observed session
and message. Export failures stop the loop rather than guess at completion.
Raw iteration output, including failures, is kept in `.agent/history/`.

**Copy into the target repository root, not just anywhere on PATH:**

```text
ralph.sh
scripts/lib/                 # the complete directory, including execution.sh
.agent/PROMPT.md             # copy as a template, then tailor it
.agent/STEERING.md           # optional instructions read by the stock prompt
```

Create `.agent/logs/`, `.agent/prd/`, `.agent/tasks/`, and, for UI work,
`.agent/screenshots/`. Set the prompt's actual setup, test, lint, and build
commands; remove the stock npm/TypeScript assumptions when inappropriate.
Include one task per invocation, commit identity/trailer rules, and the promise
protocol. Supply `.agent/STRUCTURE.md` if the prompt tells the builder to read it.
Merge deliberately if these paths already exist; do not overwrite project work.

**Generated in the target project, not copied from this checkout:**

- Run `/ralph-spec` there. The globally installed `ralph-interview` skill writes
  `.agent/prd/REQUIREMENTS.md` and asks for approval.
- Approve the handoff to the globally installed `prd-creator`. It creates
  `.agent/prd/PRD.md`, `.agent/prd/SUMMARY.md`, `.agent/tasks.json`, and detailed
  `.agent/tasks/TASK-*.json` files. Review these before running the builder.
- Resolve all human decisions and prerequisite access checks before looping.
  In particular, `TASK-1` must be executable without asking questions.
- The skill may create `.env.local` placeholders; fill real values yourself
  and Git-ignore secrets, history logs, and unwanted screenshots.
- Ralph creates `.agent/logs/LOG.md` if absent and `.agent/history/` with each
  iteration's output. The builder updates task status and the progress log.

The four global agent/command/interview files and the complete global
`prd-creator/` directory do not need copying into each project. Project-specific
skills under `.agent/skills/` are not automatically discovered by OpenCode; use
a supported skill directory or configure that source if you need them.

Run the first iteration under supervision from the target repository:

```bash
./ralph.sh --agent opencode --once
```

Copying `ralph.sh` alone is not enough. It changes directory to its own location;
calling this checkout's script from another project still operates on this
checkout. An empty `tasks.json` is not a prepared project. Timeouts, stall
detection, and independent acceptance/integration checks are not implemented;
this integration is not yet a watchdog for long unattended runs. The wrapper's
writable mounts also include other repositories, not just the target project.

### Starting from scratch

For AI to actually verify its implementation and for the loop to work, you need a way to verify it.

To that end, at the minimum you'll need an end-to-end test framework and a unit test framework.

For example, you can use the following commands to install Playwright and Vitest:

```bash
npm i @playwright/test vitest jsdom typescript eslint prettier -D

# If using React, also recommend installing:
npm i @vitejs/plugin-react @testing-library/dom @testing-library/jest-dom @testing-library/react @testing-library/user-event -D
```

It is recommended that you add skills for your specific language and framework. See [skills.sh](https://skills.sh) to discover existing skills.

## Debugging

### How to inspect the sandbox and debug

You might be wondering... if this is not a Docker container, how can you see what's going on inside Docker!?
How to debug/install things?

That's quite straightforward.

You first need to run:

```bash
sbx ls
```

Note down the name of the sandbox for the agent you ran, e.g. `ralph-claude-my-app-a1b2c3d4`. Ralph also prints this name when it starts.

And then you can run bash into any of the sandboxes like so:
```bash
sbx exec -it <sandbox-name> bash # e.g. sbx exec -it ralph-claude-my-app-a1b2c3d4 bash
```

And you have full control over the sandbox, just like a regular container. You can install packages, run commands, etc.

You can also run the agent CLI inside the sandbox (make sure to navigate to the project directory first).

```bash
sbx exec -it <sandbox-name> bash
cd /path/to/your/project # this is the same path as the path in the root machine, e.g. /Users/your-username/Documents/your-project
claude # or codex, copilot, cursor, gemini, opencode
```

Re-running `./ralph.sh`, `./ralph.sh --login`, or `./ralph.sh --ports` is safe at any point — Ralph probes `sbx ls` and emits `sbx run --name ... <agent> .` only when the sandbox doesn't exist yet, and `sbx run <sandbox-name>` to reattach afterwards. The first form is create-only and would otherwise error with `--name can only be used when creating a new sandbox`. See [RALPH.md](RALPH.md#create-vs-attach-lifecycle) for the full lifecycle.

### Allowing network access

Docker Sandboxes block outbound HTTP/HTTPS by default (deny-by-default, or a "Balanced" allowlist depending on the policy you chose at install). If the agent can't reach a host it needs — `npm install` fails, an API call is refused, package downloads hang — grant access with `sbx policy`. Changes take effect immediately and persist across sandbox restarts.

Use the sandbox name from `sbx ls` (or `./ralph.sh --print-name`), e.g. `ralph-claude-my-app-a1b2c3d4`.

Allow a single domain for one sandbox:

```bash
sbx policy allow network <my-sandbox> api.example.com
```

Allow all outbound traffic for one sandbox (use sparingly — this opts that sandbox out of network filtering):

```bash
sbx policy allow network <my-sandbox> "**"
```

Allow several domains at once with a comma-separated list (handy when package installs are blocked):

```bash
sbx policy allow network <my-sandbox> "*.npmjs.org,*.pypi.org,files.pythonhosted.org,github.com"
```

Apply a rule to every sandbox on the machine with the global flag `-g` instead of a sandbox name:

```bash
sbx policy allow network -g api.example.com
```

Inspect and manage rules:

```bash
sbx policy ls                                  # list active rules
sbx policy log                                 # inspect connection history
sbx policy deny network <my-sandbox> ads.example.com   # block a host
```

Domain matching notes:
- `example.com` matches only the exact domain (any port); it does **not** match subdomains.
- `*.example.com` matches subdomains like `api.example.com` but **not** the root `example.com` — specify both to cover both.
- Append a port to scope the rule, e.g. `example.com:443`.
- If a domain matches both an allow and a deny rule, the deny rule wins.

See Docker's [Policies](https://docs.docker.com/ai/sandboxes/security/policy/) and [Network policies](https://docs.docker.com/ai/sandboxes/network-policies/) docs for the full reference.

### Authentication issues in Sandboxes / Login not persisting

Agentic CLIs might change their auth mechanism over time and Docker Sandboxes might fail persisting OAuth tokens (when you perform `/login` inside the sandbox shell).

Fortunately, Docker Sandboxes also forward env variables **when you create a sandbox**.

Here's how to set up authentication using an API key:

1. Important 🚨: delete the sandbox that needs authentication. Env vars are only picked up when you create a new sandbox.

2. Go to [Docker security credentials](https://docs.docker.com/ai/sandboxes/security/credentials/) to find each env variables you need. For example, anthropic needs `ANTHROPIC_API_KEY`, OpenAI need `OPENAI_API_KEY`, Cursor needs `CURSOR_API_KEY`, etc.

3. Export the env variables in your shell. For example:

```bash
export ANTHROPIC_API_KEY=your-anthropic-api-key
export OPENAI_API_KEY=your-openai-api-key
export CURSOR_API_KEY=your-cursor-api-key
```

> If you use bash, you can export the env variables in your `.bashrc` file, or if you use zsh, you can export the env variables in your `.zshrc` file.

4. Recreate the sandbox by running `./ralph.sh --login` again.

## License

MIT
