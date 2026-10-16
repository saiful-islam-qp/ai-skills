# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code skill (`/commit`) that drafts Conventional Commit v1.0.0 messages for staged changes, offers 2–3 options, validates them, and commits only after explicit user approval. It has two parts that must stay in sync:

- `SKILL.md`: the skill definition. YAML frontmatter (`name`, `description`, `disable-model-invocation: true` so it only runs via `/commit`, and an `allowed-tools` allowlist) followed by the instructions the model follows at runtime.
- `scripts/validate_commit_message.sh`: a standalone Bash validator that the skill calls on every draft before showing it, and again on the approved text before committing.

## Install path coupling

`SKILL.md` calls the validator by absolute path, `~/.claude/skills/commit/scripts/validate_commit_message.sh`, because at runtime the working directory is the user's repo, not this folder. That same path also appears in `allowed-tools`. This development copy lives elsewhere, so the skill only works once this folder is available at `~/.claude/skills/commit`. If you rename the script or move it, update both the `allowed-tools` entry and every `VALIDATE` reference in `SKILL.md`.

### Project copy in `.claude/skills/commit`

The repo also contains a project-level copy of the skill at `.claude/skills/commit/`, so `/commit` works inside this repo. The root `SKILL.md` and `scripts/` are the source of truth. After changing them, copy them over again. In the copy, the validator path is repo-relative (`.claude/skills/commit/scripts/validate_commit_message.sh`) in `allowed-tools`, in the `VALIDATE` definition, and in the section 6 example. Those three lines plus the sentence after `VALIDATE` are the only intended differences:

```bash
diff SKILL.md .claude/skills/commit/SKILL.md
diff scripts/validate_commit_message.sh .claude/skills/commit/scripts/validate_commit_message.sh
```

`allowed-tools` is deliberately narrow: read-only git commands plus `git commit -F -`, with no `git add`, `restore`, `push`, or `--amend`. That enforces the skill's hard rules. Any new command the instructions rely on has to be added there too.

## Validator

```bash
# Valid message → prints "ok", exit 0
printf 'feat(auth): refresh token before expiry\n' | ./scripts/validate_commit_message.sh

# From a file, with repo-specific rules (mirrors commitlint config)
./scripts/validate_commit_message.sh --max-header 100 --types feat,fix --scopes api,ui --require-scope msg.txt

./scripts/validate_commit_message.sh --help
```

Output contract, which `SKILL.md` depends on: `error: …` and `warn: …` lines, then a final `ok` or `fail`. Exit codes: 0 means valid (warnings are allowed), 1 means invalid, 2 means a usage error. Errors block a message. Warnings are advisory: imperative mood, vague words, body lines over 72 chars, `!` without a `BREAKING CHANGE:` footer or the reverse.

Behaviors that are easy to break when you edit it:
- Merge headers (`Merge …`, `chore: merge …`) and revert headers (`Revert "…"`, `revert: …`) only get a warning when they exceed the length limit, and they skip the type/scope check for git's native forms. This supports the skill's merge and revert modes (sections 5a and 5b).
- AI-attribution trailers and text (`Co-Authored-By: Claude…`, "generated with Claude", etc.) are hard errors. This matches a hard rule in `SKILL.md`.
- The CLI flags map one-to-one to commitlint rules (`header-max-length`, `type-enum`, `scope-enum`, `scope-empty`, `subject-case`). That mapping is documented in section 6 of `SKILL.md`, so change both together.

There is no test suite. To verify a change, pipe sample messages through the script and check the output and exit code.

### Bash 3.2 compatibility

On macOS, `#!/usr/bin/env bash` resolves to `/bin/bash` 3.2 unless a newer Bash comes first on `PATH`, so the script must stay Bash 3.2-compatible. Avoid Bash 4+ features such as `mapfile`/`readarray`, associative arrays, and `${var,,}`/`${var^^}` case conversion. That is why `lines` is filled with a `while IFS= read -r` loop. Test changes with `/bin/bash scripts/validate_commit_message.sh`.
