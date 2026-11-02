#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
COMMAND_PATH="$BIN_DIR/sshd"
BASHRC="${BASHRC:-$HOME/.bashrc}"
BEGIN_MARK="# >>> sshd completion >>>"
END_MARK="# <<< sshd completion <<<"

remove_completion() {
  [[ -f "$BASHRC" ]] && grep -qxF "$BEGIN_MARK" "$BASHRC" || return 0
  local cleaned
  cleaned="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1 }
    !skip { print }
    $0 == e { skip = 0 }
  ' "$BASHRC"; printf x)"
  printf '%s' "${cleaned%x}" > "$BASHRC"
  echo "Removed tab completion block from $BASHRC"
}

if [[ ! -e "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]]; then
  echo "sshd is not installed at $COMMAND_PATH"
  remove_completion
  exit 0
fi

if [[ ! -f "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
  echo "Refusing to remove a command that is not a regular sshd launcher: $COMMAND_PATH" >&2
  exit 1
fi

mapfile -t existing_lines < "$COMMAND_PATH"
if [[ ${#existing_lines[@]} -eq 3 &&
      "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
      "${existing_lines[1]}" == '# Managed by install-sshd.sh' &&
      "${existing_lines[2]}" == exec\ bash\ *\ \"\$@\" ]]; then
  :
else
  echo "Refusing to remove a command not recognized as an sshd launcher: $COMMAND_PATH" >&2
  exit 1
fi

rm -- "$COMMAND_PATH"
echo "Uninstalled sshd from $COMMAND_PATH"
remove_completion
