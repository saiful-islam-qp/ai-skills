#!/usr/bin/env bash
# Validate a commit message against Conventional Commits v1.0.0 plus house rules.
#
# Usage:
#   validate_commit_message.sh [options] [FILE]     (reads stdin if FILE is omitted)
#
# Options (use them to apply the repo's commitlint config):
#   --max-header N     max header length (default 72)
#   --types LIST       comma-separated allowed types (default: standard 11)
#   --scopes LIST      comma-separated allowed scopes (default: any)
#   --require-scope    error when a non-merge/revert header has no scope
#   --any-case         don't require a lowercase first letter in the description
#
# Output: "error: ..." and "warn: ..." lines, then "ok" or "fail".
# Exit:   0 = valid (warnings allowed), 1 = invalid, 2 = usage error.

set -uo pipefail

max_header=72
types="feat,fix,refactor,perf,style,test,docs,build,ci,revert,chore"
scopes=""
require_scope=0
any_case=0
file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --max-header)    max_header="${2:-}"; shift 2 ;;
    --types)         types="${2:-}"; shift 2 ;;
    --scopes)        scopes="${2:-}"; shift 2 ;;
    --require-scope) require_scope=1; shift ;;
    --any-case)      any_case=1; shift ;;
    -h|--help)       sed -n '2,16p' "$0"; exit 0 ;;
    -*)              echo "usage error: unknown option $1" >&2; exit 2 ;;
    *)               file="$1"; shift ;;
  esac
done

if ! [[ "$max_header" =~ ^[0-9]+$ ]]; then
  echo "usage error: --max-header needs a number" >&2; exit 2
fi

if [ -n "$file" ]; then
  [ -r "$file" ] || { echo "usage error: cannot read $file" >&2; exit 2; }
  msg="$(cat -- "$file")"
else
  msg="$(cat)"
fi

errors=0
err()  { echo "error: $*"; errors=$((errors + 1)); }
warn() { echo "warn: $*"; }
in_list() { [[ ",$2," == *",$1,"* ]]; }

# Drop trailing blank lines; keep everything else exactly.
msg="$(printf '%s' "$msg" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"

if [ -z "${msg//[[:space:]]/}" ]; then
  err "message is empty"; echo "fail"; exit 1
fi

# Split into lines without mapfile, which macOS's /bin/bash 3.2 lacks.
lines=()
while IFS= read -r l; do lines+=("$l"); done <<< "$msg"
header="${lines[0]}"

# ---- Header ---------------------------------------------------------------
is_merge=0; is_revert=0
if [[ "$header" =~ ^Merge\  ]] || [[ "$header" =~ ^chore:\ merge\  ]]; then
  is_merge=1
elif [[ "$header" =~ ^Revert\ \" ]] || [[ "$header" =~ ^revert(\([^\)]*\))?!?:\  ]]; then
  is_revert=1
fi

hlen=${#header}
if [ "$hlen" -gt "$max_header" ]; then
  # Revert/merge headers embed another header, so overflow is only a warning.
  if [ $is_revert -eq 1 ] || [ $is_merge -eq 1 ]; then
    warn "header is $hlen chars (max $max_header); acceptable for merge/revert"
  else
    err "header is $hlen chars, max is $max_header"
  fi
fi

if [ $is_merge -eq 0 ] && [[ ! "$header" =~ ^Revert\ \" ]]; then
  re='^([a-z]+)(\(([^()]*)\))?(!)?: (.*)$'
  if [[ "$header" =~ $re ]]; then
    type="${BASH_REMATCH[1]}"
    has_scope="${BASH_REMATCH[2]}"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    desc="${BASH_REMATCH[5]}"

    in_list "$type" "$types" || err "type '$type' not allowed (allowed: $types)"

    if [ -n "$has_scope" ]; then
      if [ -z "$scope" ]; then
        err "empty scope '()'; remove the parentheses or name a scope"
      elif [[ ! "$scope" =~ ^[a-z0-9][a-z0-9._/-]*$ ]]; then
        err "scope '$scope' should be lowercase (letters, digits, . _ / -)"
      elif [ -n "$scopes" ] && ! in_list "$scope" "$scopes"; then
        err "scope '$scope' not allowed (allowed: $scopes)"
      fi
    elif [ $require_scope -eq 1 ] && [ $is_revert -eq 0 ]; then
      err "scope is required"
    fi

    if [ -z "${desc//[[:space:]]/}" ]; then
      err "description is empty"
    else
      [[ "$desc" =~ ^[[:space:]] ]] && err "exactly one space after the colon"
      [[ "$desc" =~ \.$ ]] && err "no trailing period in the header"
      if [ $any_case -eq 0 ] && [[ "$desc" =~ ^[A-Z][a-z] ]]; then
        err "description should start lowercase"
      fi
      first_word="$(printf '%s' "$desc" | awk '{print tolower($1)}')"
      if { [[ "$first_word" =~ ed$ ]] || { [[ "$first_word" =~ ing$ ]] && [ ${#first_word} -ge 6 ]; }; } \
         && [[ ! "$first_word" =~ ^(need|embed|speed|bring|string|seed|feed|shed|bleed|proceed|exceed|succeed)$ ]]; then
        warn "use imperative mood ('$first_word' → e.g. 'add', not 'added'/'adding')"
      fi
      [[ "$first_word" =~ ^[a-z]+s$ ]] && [[ "$first_word" =~ ^(adds|fixes|removes|updates|changes|makes|moves|uses|renames|improves)$ ]] \
        && warn "use imperative mood ('$first_word' → drop the trailing s)"
      if printf '%s' "$desc" | grep -qiwE 'misc|various|stuff|wip|improvements|tweaks|cleanup'; then
        warn "vague wording in description; say what changed and its effect"
      fi
    fi
  else
    err "header must match 'type(scope): description' (or 'type: description')"
    bang=""
  fi
else
  bang=""
fi

# ---- Body / footers -------------------------------------------------------
n=${#lines[@]}
if [ "$n" -gt 1 ] && [ -n "${lines[1]//[[:space:]]/}" ]; then
  err "line 2 must be blank (separate header from body)"
fi

has_breaking_footer=0
for ((i = 1; i < n; i++)); do
  line="${lines[$i]}"
  if [[ "$line" =~ ^BREAKING[\ -]CHANGE:\ .+ ]]; then
    has_breaking_footer=1
  elif printf '%s' "$line" | grep -qiE '^breaking[ -]change:' ; then
    err "line $((i + 1)): footer token must be exactly 'BREAKING CHANGE:' (uppercase)"
  fi
  if printf '%s' "$line" | grep -qiE '^co-authored-by:.*(claude|anthropic|openai|chatgpt|copilot|gpt)'; then
    err "line $((i + 1)): AI attribution trailer is not allowed"
  fi
  if printf '%s' "$line" | grep -qiE '(generated|written) (with|by) (claude|chatgpt|copilot|ai)'; then
    err "line $((i + 1)): AI attribution text is not allowed"
  fi
  if [ ${#line} -gt 72 ] && [[ ! "$line" =~ https?:// ]] && [[ ! "$line" =~ ^BREAKING ]]; then
    warn "line $((i + 1)) is ${#line} chars; wrap body at 72"
  fi
done

if [ -n "${bang:-}" ] && [ $has_breaking_footer -eq 0 ]; then
  warn "'!' without a 'BREAKING CHANGE:' footer; add one telling consumers what to change"
fi
if [ $has_breaking_footer -eq 1 ] && [ -z "${bang:-}" ] && [ $is_merge -eq 0 ]; then
  warn "'BREAKING CHANGE:' footer without '!' in the header; add '!' so it's visible in one-line logs"
fi

if [ $errors -gt 0 ]; then echo "fail"; exit 1; fi
echo "ok"; exit 0
