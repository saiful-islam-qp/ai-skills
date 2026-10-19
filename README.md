# /commit

A [Claude Code](https://claude.com/claude-code) skill that writes
[Conventional Commit v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
messages for your staged changes. It reads the diff, drafts 2–3 different
options, checks each one with a bundled validator, and commits only after you
approve one.

```
**Staged files** (3 files, +42 −7)
src/features/auth/refresh.ts | 30 +++++++---
...

**Option 1**
feat(auth): refresh access token before it expires

Refs: EMP-101

**Option 2**
feat(auth): refresh access token before it expires

Requests made close to expiry were failing with 401 and forcing a
re-login. The token is now refreshed 60s ahead of its expiry.

Refs: EMP-101

Pick 1–3, paste your own edit, or tell me what to change.
```

## What it does

- **Uses only what's staged.** It never runs `git add`, `git restore`, or
  anything else that changes the index or working tree.
- **Commits only after you approve.** Picking an option counts as approval. Asking
  for a change does not, and you see the revised message before it commits.
- **Writes about intent, not mechanics.** Subjects describe what the change does
  ("prevent crash when user has no avatar"), not what the diff looks like ("add
  null check").
- **Picks type and scope consistently.** It applies tie-breakers for type and
  takes scope from the nearest meaningful folder, skipping generic ones like `src`,
  `lib`, and `utils`. It reuses scopes already in `git log`.
- **Flags breaking changes.** Removed exports, renamed props, and changed
  signatures get a `!` and a `BREAKING CHANGE:` footer.
- **Suggests splits.** If the staged changes mix unrelated concerns, it tells you
  which files go in which commit and gives you the commands to run yourself.
- **Adds a ticket footer.** It takes the ticket from the branch name
  (`fix/EMP-101-null-check` → `Refs: EMP-101`), or asks once if there isn't one.
- **Handles merges and reverts.** Merges in progress get git's default header or
  a `chore: merge …` form. Reverts get `revert: <original header>` with the sha.
- **Follows your commitlint config.** If the repo has a commitlint config, its
  `type-enum`, `scope-enum`, `scope-empty`, `header-max-length`, and
  `subject-case` rules override the defaults. If commitlint is installed, it also
  runs before the commit.

It never pushes, never uses `--amend` or `--no-verify`, and never adds
AI-attribution trailers such as `Co-Authored-By`. If a hook fails, it shows the
output and stops.

## Install

The skill calls its validator by absolute path, so the folder has to live at
`~/.claude/skills/commit`:

```bash
git clone https://github.com/saiful-islam-qp/ai-skills.git ~/.claude/skills/commit
```

If you already have a clone elsewhere, symlink it instead:

```bash
ln -s "$(pwd)" ~/.claude/skills/commit
```

Make sure the validator is executable:

```bash
chmod +x ~/.claude/skills/commit/scripts/validate_commit_message.sh
```

## Usage

Stage what you want to commit, then run the skill in Claude Code:

```
git add src/features/auth/
/commit
```

Pick an option by number, paste your own edit, or ask for changes such as
"shorter" or "mention the cache". The skill has `disable-model-invocation: true`,
so it runs only when you type `/commit`. Claude won't trigger it on its own.

## Validator

`scripts/validate_commit_message.sh` is a standalone Bash script. You can use it
on its own, for example in a `commit-msg` hook. It reads a message from a file
or from stdin:

```bash
$ printf 'feat(auth): refresh token before expiry\n' | ./scripts/validate_commit_message.sh
ok

$ printf 'fix(ui): Fixed the button\n' | ./scripts/validate_commit_message.sh --types feat,fix --scopes api,ui
error: description should start lowercase
warn: use imperative mood ('fixed' → e.g. 'add', not 'added'/'adding')
fail
```

| Flag | commitlint rule | Default |
|---|---|---|
| `--max-header N` | `header-max-length` | `72` |
| `--types a,b,c` | `type-enum` | the 11 standard types |
| `--scopes a,b,c` | `scope-enum` | any scope |
| `--require-scope` | `scope-empty: [2, 'never']` | scope optional |
| `--any-case` | `subject-case` disabled | lowercase required |

**Output:** zero or more `error: …` and `warn: …` lines, then `ok` or `fail`.

**Exit codes:** `0` means valid (warnings are allowed), `1` means invalid, and `2`
means a usage error.

Errors block the message: a malformed header, an unknown type or scope, a header
that's too long, a trailing period, or AI-attribution text. Warnings are advisory:
non-imperative mood, vague words, body lines over 72 characters, or a `!` without
a `BREAKING CHANGE:` footer (or the reverse).

The script is compatible with Bash 3.2, so it runs on the stock macOS `/bin/bash`.

## Repository layout

```
SKILL.md                          # skill definition: frontmatter + runtime instructions
scripts/validate_commit_message.sh
.claude/skills/commit/            # project copy so /commit works inside this repo
CLAUDE.md                         # notes for working on the skill itself
```

## Contributing

The root `SKILL.md` and `scripts/` are the source of truth. After changing them,
copy them into `.claude/skills/commit/`. In that copy, keep the validator path
repo-relative. Then check that the validator path lines are the only differences:

```bash
diff SKILL.md .claude/skills/commit/SKILL.md
diff scripts/validate_commit_message.sh .claude/skills/commit/scripts/validate_commit_message.sh
```

If the instructions start relying on a new command, add it to `allowed-tools` in
the frontmatter. The allowlist is deliberately narrow because it enforces the
skill's hard rules.

There's no test suite. To verify a validator change, pipe sample messages through
it with `/bin/bash scripts/validate_commit_message.sh` and check the output and
exit code. See [CLAUDE.md](CLAUDE.md) for the behaviors that are easy to break.
