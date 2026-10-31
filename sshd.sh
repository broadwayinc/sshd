#!/usr/bin/env bash
# Usage: sshd [-t target] [-i keyfile] [-u user] [-H host] [folder]
# Opens an interactive ssh session using a named target from sshd.conf (see README.md).
# With a folder, the session starts there; if it does not exist the remote home is used.
set -euo pipefail

KEY=""
USER_NAME=""
HOST=""
START_DIR=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SSHD_CONF:-$SCRIPT_DIR/sshd.conf}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Trim a config value, drop matching surrounding quotes, expand a leading ~ and $HOME
# (skipped when $2 is "raw", e.g. for remote paths).
strip_value() {
  local v
  v="$(trim "$1")"
  if [[ ${#v} -ge 2 ]] &&
     { [[ "${v:0:1}" == '"' && "${v: -1}" == '"' ]] || [[ "${v:0:1}" == "'" && "${v: -1}" == "'" ]]; }; then
    v="${v:1:${#v}-2}"
  fi
  if [[ "${2:-}" == raw ]]; then
    printf '%s' "$v"
    return 0
  fi
  if [[ "$v" == "~" || "$v" == "~/"* ]]; then
    v="$HOME${v#\~}"
  fi
  printf '%s' "${v//\$HOME/$HOME}"
}

# Target names in file order.
conf_targets() {
  [[ -f "$CONFIG" ]] || return 0
  local line re='^\[([^]]+)\]$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    if [[ "$line" =~ $re ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done < "$CONFIG"
}

# The "default = name" value written before the first section, if any.
conf_explicit_default() {
  [[ -f "$CONFIG" ]] || return 0
  local line re='^default[[:space:]]*=(.*)$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ "$line" == \[* ]] && return 0
    if [[ "$line" =~ $re ]]; then
      strip_value "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$CONFIG"
}

# The chosen default target if it exists, otherwise the first target.
conf_default() {
  local d first
  d="$(conf_explicit_default)"
  if [[ -n "$d" ]] && conf_targets | grep -xF -- "$d" >/dev/null; then
    printf '%s' "$d"
    return 0
  fi
  first="$(conf_targets | sed -n 1p)"
  printf '%s' "$first"
}

# Load KEY, USER_NAME, HOST and START_DIR from the named target; fails if it does not exist.
conf_load() {
  local want="$1" line sec="" found=1 k v
  local header_re='^\[([^]]+)\]$' kv_re='^([A-Za-z_]+)[[:space:]]*=(.*)$'
  [[ -f "$CONFIG" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ $header_re ]]; then
      sec="${BASH_REMATCH[1]}"
      [[ "$sec" == "$want" ]] && found=0
      continue
    fi
    [[ "$sec" == "$want" ]] || continue
    if [[ "$line" =~ $kv_re ]]; then
      k="${BASH_REMATCH[1]}"
      if [[ "$k" == dir ]]; then
        v="$(strip_value "${BASH_REMATCH[2]}" raw)"
      else
        v="$(strip_value "${BASH_REMATCH[2]}")"
      fi
      case "$k" in
        key) KEY="$v" ;;
        user) USER_NAME="$v" ;;
        host) HOST="$v" ;;
        dir) START_DIR="$v" ;;
      esac
    fi
  done < "$CONFIG"
  return "$found"
}

# Add or replace a target, rewriting the config file.
save_target() {
  local name="$1" key="$2" user="$3" host="$4" start_dir="$5" make_default="$6" dflt tmp
  dflt="$(conf_explicit_default)"
  if [[ "$make_default" == true ]]; then
    dflt="$name"
  fi
  mkdir -p -- "$(dirname -- "$CONFIG")"
  tmp="$(mktemp "$CONFIG.XXXXXX")"
  {
    if [[ -n "$dflt" ]]; then
      printf 'default = %s\n\n' "$dflt"
    fi
    if [[ -f "$CONFIG" ]]; then
      awk -v name="$name" '
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
          line = $0
          gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", line)
          insec = 1
          skip = (line == name)
        }
        !insec && /^[[:space:]]*default[[:space:]]*=/ { next }
        !skip { print }
      ' "$CONFIG"
    fi
    printf '\n[%s]\nkey = %s\nuser = %s\nhost = %s\n' "$name" "$key" "$user" "$host"
    [[ -z "$start_dir" ]] || printf 'dir = %s\n' "$start_dir"
  } | cat -s | sed '1{/^$/d}' > "$tmp"
  mv -- "$tmp" "$CONFIG"
}

# ask VAR "Label" ["suggested value"]: prompt until a non-empty value is given.
ask() {
  local __var="$1" label="$2" def="${3:-}" ans
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$label [$def]: " ans
      ans="${ans:-$def}"
    else
      read -r -p "$label: " ans
    fi
    ans="$(trim "$ans")"
    [[ -n "$ans" ]] && break
    echo "A value is required." >&2
  done
  printf -v "$__var" '%s' "$ans"
}

# Interactively add or edit a target (existing values are offered as defaults).
configure_target() {
  local name="${1:-}" key user host start_dir suggested="" answer make_default=false first_run=false
  if [[ ! -t 0 ]]; then
    echo "Configuring a target needs an interactive terminal." >&2
    exit 1
  fi
  if [[ -z "$(conf_targets)" ]]; then
    first_run=true
    suggested="default"
  fi
  if [[ -z "$name" ]]; then
    ask name "Target name" "$suggested"
  fi
  if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid target name '$name': use letters, digits, '.', '_' and '-'." >&2
    exit 1
  fi

  KEY="" USER_NAME="" HOST="" START_DIR=""
  if conf_load "$name"; then
    echo "Editing existing target '$name'."
  fi
  ask key "SSH key file" "$KEY"
  ask user "Remote username" "$USER_NAME"
  ask host "Remote host" "$HOST"
  read -r -p "Start directory (optional, '-' to clear)${START_DIR:+ [$START_DIR]}: " start_dir
  start_dir="$(trim "$start_dir")"
  if [[ "$start_dir" == "-" ]]; then
    start_dir=""
  else
    start_dir="$(strip_value "${start_dir:-$START_DIR}" raw)"
  fi

  if [[ "$first_run" != true && "$(conf_default)" != "$name" ]]; then
    read -r -p "Make '$name' the default target? [y/N] " answer
    [[ "$answer" == [yY]* ]] && make_default=true
  fi
  save_target "$name" "$key" "$user" "$host" "$start_dir" "$make_default"
  echo "Saved target '$name' in $CONFIG"
}

list_targets() {
  local d name
  if [[ -z "$(conf_targets)" ]]; then
    echo "No targets configured. Run: sshd -c"
    return 0
  fi
  d="$(conf_default)"
  while IFS= read -r name; do
    (
      KEY="" USER_NAME="" HOST="" START_DIR=""
      conf_load "$name" || true
      printf '%s%s  %s@%s  key=%s%s\n' "$name" "$([[ "$name" == "$d" ]] && echo ' (default)')" \
        "$USER_NAME" "$HOST" "$KEY" "${START_DIR:+  dir=$START_DIR}"
    )
  done < <(conf_targets)
}

# Pick the target, set up the first one if none exists, and load its values.
resolve_target() {
  local name="$TARGET"
  if [[ -z "$(conf_targets)" ]]; then
    [[ "$MODE" == "complete" ]] && exit 0
    if [[ -t 0 ]]; then
      echo "No targets configured yet. Let's set one up."
      configure_target ""
    else
      echo "No targets configured. Run: sshd -c" >&2
      exit 1
    fi
  fi
  [[ -n "$name" ]] || name="$(conf_default)"
  if ! conf_load "$name"; then
    [[ "$MODE" == "complete" ]] && exit 0
    echo "Unknown target: $name" >&2
    echo "Available targets:" >&2
    conf_targets | sed 's/^/  /' >&2
    exit 1
  fi
}

open_docs() {
  local docs="$SCRIPT_DIR/README.md"
  if [[ ! -f "$docs" ]]; then
    echo "Documentation not found: $docs" >&2
    exit 1
  fi
  cat "$docs"
}

# Quote a remote path for the remote shell, keeping a leading ~ or ~user expandable.
remote_quote() {
  local p="$1" head="" rest="$1" sq="'\\''" q="'"
  if [[ "$p" =~ ^(~[A-Za-z0-9_.-]*)(/.*)?$ ]]; then
    head="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]#/}"
    [[ -n "$head" ]] && head="$head/"
    [[ -n "${BASH_REMATCH[2]}" ]] || { printf '%s' "${head%/}"; return; }
    [[ -n "$rest" ]] || { printf '%s' "$head"; return; }
  fi
  rest="${rest//"$q"/$sq}"
  printf '%s%s' "$head" "'$rest'"
}

# Print remote folder completion candidates for a partial path (used by sshd-completion.bash).
complete_paths() {
  local cur="$1" dir base entry
  if [[ -z "$cur" ]]; then
    printf '/\n~/\n'
    return 0
  fi
  if [[ "$cur" == "~" ]]; then
    printf '~/\n'
    return 0
  fi
  [[ "$cur" == "~"* || "$cur" == /* ]] || return 0
  [[ "$cur" == */* ]] || return 0

  dir="${cur%/*}/"
  base="${cur##*/}"
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=5 \
    -o ControlMaster=auto -o ControlPersist=60 \
    -o "ControlPath=${XDG_RUNTIME_DIR:-$HOME/.ssh}/sshd-%C" \
    "$USER_NAME@$HOST" "ls -1ApL -- $(remote_quote "$dir") 2>/dev/null" 2>/dev/null |
    while IFS= read -r entry; do
      [[ "$entry" == */ ]] || continue
      [[ -z "$base" && "$entry" == .* ]] && continue
      [[ "$entry" == "$base"* ]] && printf '%s%s\n' "$dir" "$entry"
    done || true
}

usage() {
  local status="${1:-1}" out=1
  [[ "$status" -eq 0 ]] || out=2
  cat >&"$out" <<'EOF'
Usage: sshd [-t target] [-i keyfile] [-u user] [-H host] [folder]
       sshd -c [name] | -T | -d | -h

  -t  use this target from sshd.conf (default: the configured default,
      otherwise the first target)
  -i  override the target's key file
  -u  override the target's remote username
  -H  override the target's remote host
  -c  add or edit a target (asks for its values)
  -T  list configured targets
  -d  print the README documentation
  -h  show this help

With a folder (e.g. ~/projects or /var/www) the session starts there;
if the folder does not exist you land in the remote home folder.
Without one, the target's "dir" setting in sshd.conf is used, if set.
EOF
  exit "$status"
}

MODE="connect"
TARGET=""
OPT_KEY="" OPT_USER="" OPT_HOST=""

# -C (complete) and -N (print target names) are internal flags used by the tab completion script.
while getopts "t:i:u:H:hdcTCN" opt; do
  case "$opt" in
    t) TARGET="$OPTARG" ;;
    i) OPT_KEY="$OPTARG" ;;
    u) OPT_USER="$OPTARG" ;;
    H) OPT_HOST="$OPTARG" ;;
    d) open_docs; exit 0 ;;
    c) MODE="configure" ;;
    T) MODE="targets" ;;
    C) MODE="complete" ;;
    N) MODE="names" ;;
    h) usage 0 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

case "$MODE" in
  configure) configure_target "${TARGET:-${1:-}}"; exit 0 ;;
  targets) list_targets; exit 0 ;;
  names) conf_targets; exit 0 ;;
esac

[[ $# -le 1 ]] || { echo "Only one folder can be given." >&2; usage; }
FOLDER="${1:-}"

resolve_target
[[ -n "$FOLDER" ]] || FOLDER="$START_DIR"
[[ -z "$OPT_KEY" ]] || KEY="$OPT_KEY"
[[ -z "$OPT_USER" ]] || USER_NAME="$OPT_USER"
[[ -z "$OPT_HOST" ]] || HOST="$OPT_HOST"

for field in KEY USER_NAME HOST; do
  if [[ -z "${!field}" ]]; then
    echo "Missing '$field' for the selected target. Run: sshd -c" >&2
    exit 1
  fi
done
[ -f "$KEY" ] || { echo "Key file not found: $KEY" >&2; exit 1; }

if [[ "$MODE" == "complete" ]]; then
  complete_paths "${FOLDER}"
  exit 0
fi

if [[ -z "$FOLDER" ]]; then
  exec ssh -i "$KEY" "$USER_NAME@$HOST"
fi

# Bash expands an unquoted ~ to the LOCAL home before sshd runs. Try the path as given,
# then the same path under the remote home, and stay in the home folder if neither exists.
alt=""
if [[ "$FOLDER" == "$HOME" || "$FOLDER" == "$HOME/"* ]]; then
  alt="~${FOLDER#"$HOME"}"
fi
remote_cmd="cd $(remote_quote "$FOLDER") 2>/dev/null"
[[ -z "$alt" ]] || remote_cmd+=" || cd $(remote_quote "$alt") 2>/dev/null"
remote_cmd+="; exec \"\${SHELL:-/bin/sh}\" -l"
exec ssh -t -i "$KEY" "$USER_NAME@$HOST" "$remote_cmd"
