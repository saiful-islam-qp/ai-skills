---
name: commit
description: Writes a Conventional Commit message for the currently staged changes, offers 2–3 options to pick or edit, validates the chosen one with a bundled script, and commits only after explicit approval. Handles merges and reverts in progress. Run manually with /commit.
disable-model-invocation: true
allowed-tools: Bash(git rev-parse:*), Bash(git status:*), Bash(git diff:*), Bash(git branch:*), Bash(git log:*), Bash(git commit -F -:*), Bash(npx --no-install commitlint:*), Bash(.claude/skills/commit/scripts/validate_commit_message.sh:*), Read, Glob
---

# /commit

Turn the staged changes into a clear Conventional Commit (v1.0.0) message, let the
user choose or edit it, then commit. The user is the decision-maker: you propose,
they approve. Nothing is committed until they say so.

`VALIDATE` below means `.claude/skills/commit/scripts/validate_commit_message.sh`.
Call it by that repo-relative path from the repo root; this project copy of the skill lives inside this repo.

## Hard rules

These exist because a commit is hard to take back once it's shared, and the user
invoked this skill to get a message, not to have their working tree changed.

- Work from staged changes only. Never run `git add`, `git rm`, `git restore`, or anything that changes what's staged.
- Never commit without an explicit approval in this conversation.
- Never push, never `--amend`, never `--no-verify`. Hooks are the repo's safety net.
- Never touch unstaged or untracked files.
- Never present or commit a message that `VALIDATE` rejects.
- Never add `Co-Authored-By` or any other AI-attribution trailer or text.

## 1. Preflight

1. `git rev-parse --is-inside-work-tree` — if this fails, say it's not a git repo and stop.
2. Detect an operation in progress (each command exits 0 if it applies):
   - `git rev-parse -q --verify MERGE_HEAD` → **merge mode** (section 5a)
   - `git rev-parse -q --verify REVERT_HEAD` → **revert mode** (section 5b)
   - `git rev-parse -q --verify CHERRY_PICK_HEAD` → tell the user a cherry-pick is in
     progress, suggest `git cherry-pick --continue` so the original message is kept, and stop.
3. In merge or revert mode, check `git diff --name-only --diff-filter=U`. Any output
   means unresolved conflicts: list the files, tell the user to resolve and stage
   them, and stop.
4. `git diff --staged --quiet` — exit code 0 means nothing is staged. Outside merge
   mode, show `git status --short`, tell the user to stage what they want committed,
   and stop. Don't offer to stage it for them. (In merge mode an empty staged diff is
   legitimate; continue.)
5. `git diff --quiet` — if there are unstaged changes, remember them for a heads-up
   in the preview ("these won't be included"). Don't act on them.

## 2. Gather context

Collect all of this before writing anything; guessing from file names alone produces
vague messages.

- `git diff --staged --stat` — file list and size of the change.
- `git diff --staged --name-status` and `git diff --staged --numstat` — spot the
  special shapes:
  - **Deletions only** (every line `D`): use "remove" phrasing; say what is gone and why it's safe.
  - **Renames/moves only** (every line `R…`): usually `refactor`; name the old → new location.
  - **Binary only** (numstat shows `-` `-` for every file): there's no text diff to
    read, so infer intent from paths, names, and extensions (`assets/`, `.png`,
    `.woff2`) and keep the message factual.
- `git diff --staged` — the actual content. For large diffs (roughly 500+ lines),
  start from the stat and read files selectively, using `git diff --staged -- <path>`.
  Lock files (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) and generated files
  (`dist/`, `*.min.*`, snapshots, codegen output): note that they changed, don't analyze
  them line by line.
- `git branch --show-current` — for the ticket.
- `git log -n 15 --oneline` — existing scope names and style to stay consistent with.
- Commitlint config: look for `commitlint.config.*`, `.commitlintrc*`, or a
  `commitlint` key in `package.json`. If found, read it and note `type-enum`,
  `scope-enum`, `scope-empty`, `header-max-length`, `subject-case`, and any extended
  preset (e.g. `@commitlint/config-conventional`). **Repo rules override every
  default below**, and you pass them to `VALIDATE` (section 6).

## 3. Analyze

### Intent first

Before choosing words, answer: what does this change do for a user or for the
codebase? A diff that adds a null check is "stop the profile page crashing when a user
has no avatar", not "add null check". The message describes the effect.

Write each subject so it could go straight into release notes: a developer should
see what changed and where, a stakeholder should see what they'd notice.

### Type

| Type | When |
|---|---|
| `feat` | New behavior or capability a user or consumer can notice |
| `fix` | Broken behavior corrected |
| `refactor` | Same behavior, different structure |
| `perf` | Same behavior, measurably faster or lighter |
| `style` | Formatting, whitespace, lint-only changes; no logic |
| `test` | Tests only |
| `docs` | Documentation only (README, comments, JSDoc, `.md`) |
| `build` | Build system, bundler config, dependencies, lock files |
| `ci` | CI pipeline config (`.github/workflows`, etc.) |
| `revert` | Reverts a previous commit |
| `chore` | Anything else that doesn't touch src or tests |

Tie-breakers:
- New behavior beats everything: a feature that also refactors is `feat`.
- A fix that required restructuring is still `fix`.
- Source change plus its tests: use the source change's type, not `test`.
- Dependency bump that exists to fix a bug: `fix` if the user-visible bug is the point, otherwise `build`.
- If `refactor` vs `perf` is genuinely ambiguous, offer one option of each.

### Breaking changes

Look for: removed or renamed exports, props, or API fields; changed function
signatures or argument order; changed default values; removed CSS classes or tokens
in a published library; narrowed accepted types.

When found, add `!` after the type/scope and a `BREAKING CHANGE:` footer that tells
consumers what they must change (old → new). This matters because published packages
use these markers to decide the semver bump; a missed one ships a breaking change as a
minor release.

If you're unsure whether something is public API (e.g. an export that may only be used
internally), say so in the preview and let the user decide.

### Split detection

If the staged changes hold unrelated concerns (a bug fix plus an unrelated refactor,
a feature plus a dependency bump), recommend splitting and list which files belong in
which commit. Include the commands for the user to run themselves, e.g.
`git restore --staged <files>`. You don't run them. If the user declines, write the
best combined message: lead with the most significant change and mention the other
in the body.

## 4. Scope

Scope is the nearest meaningful module or feature folder, as a single lowercase word.

- Skip generic folders: `src`, `app`, `lib`, `components`, `utils`, `hooks`,
  `helpers`, `packages`, `shared`, `common`.
- Prefer a scope already used in `git log` when it fits; consistent history is
  easier to search and changelog.
- If commitlint has a `scope-enum`, choose only from that list (or omit scope if
  none fits and the config allows it).
- Multi-area:
  - Related changes → nearest meaningful common parent (often the package name).
  - No meaningful common parent → omit the scope.
  - Unrelated changes → suggest a split (above).

Examples:

| Path | Scope |
|---|---|
| `packages/ui/src/components/button/Button.tsx` | `button` |
| `src/features/auth/refresh.ts` | `auth` |
| `packages/ui/src/components/button/*` + `.../input/*` (same token change) | `ui` |
| `src/utils/date.ts` | `date` (file name when the folder is generic) |
| `README.md` + `.github/workflows/ci.yml` | none, and probably a split |

The goal: the same files always produce the same scope.

## 5. Write the message

### Subject

`type(scope): description` (or `type: description` with no scope)

- ≤72 characters total, or the commitlint `header-max-length` if set.
- Imperative mood: "add", "remove", "prevent", not "added" or "adds".
- Lowercase after the colon, unless commitlint's `subject-case` says otherwise.
- No trailing period.
- Plain, specific words describing the actual change. Avoid "update", "change",
  "fix stuff", "misc", "improvements", "various", "wip" unless the change really is
  that generic (e.g. `build: update dependencies` for a routine bump is fine).

### Body

Add one only when the subject doesn't already explain why. Blank line after the
subject, wrap at 72 characters, a few lines at most. Explain what and why, not how;
the diff shows how.

### Footers

In this order, one per line, after a blank line:

1. `BREAKING CHANGE: <what consumers must change>` (if any; uppercase token exactly)
2. `Refs: <TICKET>` (if any)

### Ticket

Match `[A-Z][A-Z0-9]+-\d+` in the branch name (`fix/EMP-101-null-check` → `EMP-101`).
If there's no match, ask once in the preview: the user can type a ticket or skip.
Skipping means no `Refs:` line. Don't ask again in the same run. Never invent one.

### 5a. Merge mode

Read `.git/MERGE_MSG` (git's prepared message). Offer:
- **Option 1:** git's default first line as-is (`Merge branch 'x' into y`). Many repos
  and tools expect this form, and commitlint's conventional preset ignores it.
- **Option 2:** `chore: merge <branch> into <current>`, for repos whose history is
  strictly conventional.

Drop git's `#` comment lines. If conflicts were resolved in a meaningful way, mention
the resolution in a short body. No scope, no ticket prompt.

### 5b. Revert mode

Get the reverted commit's sha from `git rev-parse REVERT_HEAD` and its header from
`git log -1 --format=%s REVERT_HEAD`. Message:

```
revert: <original header>

This reverts commit <full sha>.
<one line on why, if the user said or it's evident>

Refs: <short sha>
```

If the original header was git's own `Revert "..."` form, keep the conventional
`revert:` form above anyway. No ticket prompt unless the branch name has one.

### Good vs bad

| Bad | Good |
|---|---|
| `fix: fix bug` | `fix(profile): prevent crash when user has no avatar` |
| `feat(auth): Added refresh token logic.` | `feat(auth): refresh access token before it expires` |
| `refactor: various improvements` | `refactor(listing): move filter state into zustand store` |
| `fix(source): use regex match not first span` | `fix(source): match the timestamp span, fixing wrong listing times` |
| `feat(button): update props` | `feat(button)!: rename variant prop to appearance` + `BREAKING CHANGE: replace variant="primary" with appearance="primary"` |

## 6. Validate the drafts, then preview

Run every option through `VALIDATE` **before** showing it, passing the message on a
quoted heredoc so quotes, `$`, and backticks survive untouched:

```bash
.claude/skills/commit/scripts/validate_commit_message.sh <flags> <<'EOF'
<draft message>
EOF
```

Flags (derive from commitlint config when present; omit otherwise):
- `--max-header N` from `header-max-length` (default 72)
- `--types a,b,c` from `type-enum`
- `--scopes a,b,c` from `scope-enum`
- `--require-scope` when `scope-empty` is `[2, 'never']`
- `--any-case` when `subject-case` is disabled or allows sentence/start case

Exit 1 (`error:` lines): revise and re-run until it passes. Never show a failing
option. `warn:` lines: fix them if the fix is reasonable, otherwise mention the
warning under that option.

Then show exactly this structure:

````
**Staged files** (N files, +X −Y)
<from --stat; group by folder if more than ~10 files>

**Heads-up**            ← only if any apply
- Merge in progress / Revert of <sha> in progress
- Unstaged changes in: <files> (won't be included)
- Looks like two separate changes, suggest splitting: <groups>
- No ticket found in branch "<name>". Enter one, or say "skip".
- Unsure if <export> is public API, marked as breaking in option 1 only.

**Option 1**
```<full message, footers included>```

**Option 2**
```<full message>```

**Option 3** (only if it's genuinely different)
```<full message>```

Pick 1–3, paste your own edit, or tell me what to change.
````

Options must be meaningfully different, not rewordings. They can differ in:
- Detail: subject-only vs with a body.
- Interpretation: `refactor` vs `perf`, `fix` vs `feat`, breaking vs not.
- Emphasis: user-facing effect vs technical change.

Two strong options beat three padded ones.

**Editing:** the user can paste an edited message or ask for tweaks ("shorter",
"mention the cache"). After any change, re-run `VALIDATE`, show the final message
again in full, and ask for approval. Picking a number counts as approval; asking for a
change does not. If the user's own pasted message fails validation, show the errors
and a corrected version, and ask which to use.

## 7. Commit

1. Re-run `VALIDATE` on the exact approved text (cheap, and catches edits made in
   between). If commitlint is installed, also run it the same way:
   ```bash
   npx --no-install commitlint <<'EOF'
   <approved message>
   EOF
   ```
   If commitlint fails, show the error, propose a corrected version, and get approval
   again. If commitlint isn't installed, skip it silently.
2. Commit with a quoted heredoc so multi-line messages are kept exactly:
   ```bash
   git commit -F - <<'EOF'
   <approved message>
   EOF
   ```
3. If a hook fails, show its output and stop. Don't retry with `--no-verify`, don't
   fix the code; the user decides what to do.
4. On success, show `git log -1 --stat` as confirmation. Don't push.
