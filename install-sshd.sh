#!/usr/bin/env bash
# Installs the sshd command in ~/.local/bin (or $XDG_BIN_HOME).
#
#   From a checkout:  ./install-sshd.sh [--completion | --no-completion]
#   From the web:     curl -fsSL https://raw.githubusercontent.com/broadwayinc/sshd/main/install-sshd.sh | bash
#                     (pass an option with: ... | bash -s -- --completion)
#
# Run next to sshd.sh, it installs that copy. Run any other way (piped into bash, or a
# lone downloaded file), it downloads the files from SSHD_BASE_URL into SSHD_HOME
# (default ~/.local/share/sshd) and installs those. Re-run it to update; sshd.conf is kept.
# Nothing runs until the last line, so a partly downloaded script does nothing.
set -euo pipefail

# Where a web install downloads from. Point this (or SSHD_BASE_URL) at your own server
# if you host the files yourself.
DEFAULT_BASE_URL="https://raw.githubusercontent.com/broadwayinc/sshd/main"
WEB_FILES=(sshd.sh sshd-completion.bash sshd-completion.zsh README.md uninstall-sshd.sh)

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
COMMAND_PATH="$BIN_DIR/sshd"
BASHRC="${BASHRC:-$HOME/.bashrc}"
ZSHRC="${ZSHRC:-${ZDOTDIR:-$HOME}/.zshrc}"
RC_FILE="$BASHRC"
[[ "${SHELL:-}" != */zsh ]] || RC_FILE="$ZSHRC"
BEGIN_MARK="# >>> sshd completion >>>"
END_MARK="# <<< sshd completion <<<"
COMPLETION="ask"
CLEANUP=()

cleanup() {
  [[ -z "${CLEANUP[*]-}" ]] || rm -rf -- "${CLEANUP[@]}"
}

# Ask a y/N question on the terminal. Reads /dev/tty when stdin is not one, which is the
# case with curl | bash (stdin is this script). Fails when there is no terminal at all.
confirm() {
  local answer
  if [[ -t 0 ]]; then
    read -r -p "$1 [y/N] " answer
  elif { : </dev/tty; } 2>/dev/null; then
    read -r -p "$1 [y/N] " answer </dev/tty
  else
    return 1
  fi
  [[ "$answer" == [yY]* ]]
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "Downloading needs curl or wget." >&2
    return 1
  fi
}

# Download the program files into $1, replacing older copies. sshd.conf is never touched.
download_files() {
  local dir="$1" base="${SSHD_BASE_URL:-$DEFAULT_BASE_URL}" tmp f first
  base="${base%/}"
  mkdir -p -- "$dir"
  tmp="$(mktemp -d "$dir/.download.XXXXXX")"
  CLEANUP+=("$tmp")
  echo "Downloading sshd from $base"
  for f in "${WEB_FILES[@]}"; do
    if ! fetch "$base/$f" "$tmp/$f"; then
      echo "Download failed: $base/$f" >&2
      exit 1
    fi
    # A web server may answer a missing file with an HTML page; never install that as a script.
    if [[ "$f" == *.sh || "$f" == *.bash || "$f" == *.zsh ]]; then
      first=""
      IFS= read -r first < "$tmp/$f" || true
      if [[ "$first" != \#* ]]; then
        echo "Not a shell script: $base/$f" >&2
        exit 1
      fi
      if [[ "$f" == *.zsh ]]; then
        if command -v zsh >/dev/null 2>&1 && ! zsh -n "$tmp/$f"; then
          echo "Invalid zsh script: $base/$f" >&2
          exit 1
        fi
      elif ! bash -n "$tmp/$f"; then
        echo "Invalid bash script: $base/$f" >&2
        exit 1
      fi
    fi
  done
  chmod 755 "$tmp"/*.sh
  for f in "${WEB_FILES[@]}"; do
    mv -f -- "$tmp/$f" "$dir/$f"
  done
}

strip_completion_block() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip = 1 }
    !skip { print }
    $0 == e { skip = 0 }
  ' "$RC_FILE"
}

setup_completion() {
  [[ -f "$COMPLETION_PATH" ]] || return 0
  local has_block=false cleaned
  [[ -f "$RC_FILE" ]] && grep -qxF "$BEGIN_MARK" "$RC_FILE" && has_block=true

  if [[ "$has_block" != true ]]; then
    if [[ "$COMPLETION" == "ask" ]]; then
      if confirm "Enable tab completion for sshd by adding a block to $RC_FILE?"; then
        COMPLETION="yes"
      else
        COMPLETION="no"
      fi
    fi
    if [[ "$COMPLETION" != "yes" ]]; then
      echo "Tab completion not enabled. To enable it, add this to $RC_FILE:"
      [[ "$RC_FILE" != "$ZSHRC" ]] || echo '  autoload -Uz compinit; (( $+functions[compdef] )) || compinit'
      printf '  source %q\n' "$COMPLETION_PATH"
      return 0
    fi
  fi

  touch -- "$RC_FILE"
  cleaned="$(strip_completion_block; printf x)"
  cleaned="${cleaned%x}"
  {
    printf '%s' "$cleaned"
    printf '%s\n' "$BEGIN_MARK"
    [[ "$RC_FILE" != "$ZSHRC" ]] || printf '%s\n' 'autoload -Uz compinit; (( $+functions[compdef] )) || compinit'
    printf '[ -f %q ] && source %q\n' "$COMPLETION_PATH" "$COMPLETION_PATH"
    printf '%s\n' "$END_MARK"
  } > "$RC_FILE"
  echo "Tab completion enabled in $RC_FILE (open a new terminal to use it)."
}

# When the launcher moves to another copy of sshd.sh, bring the old copy's targets along.
carry_over_config() {
  local old_script="$1" old_conf
  old_conf="$(dirname -- "$old_script")/sshd.conf"
  if [[ "$old_script" != "$SCRIPT_PATH" && -f "$old_conf" && ! -e "$SCRIPT_DIR/sshd.conf" ]]; then
    cp -p -- "$old_conf" "$SCRIPT_DIR/sshd.conf"
    echo "Copied your targets from $old_conf"
  fi
}

finish() {
  setup_completion
  if [[ "$WEB_INSTALL" == true ]]; then
    echo "Files are in $SCRIPT_DIR. Run the same command again to update (your targets are kept)."
    printf 'To uninstall: bash %q\n' "$SCRIPT_DIR/uninstall-sshd.sh"
  fi
}

main() {
  case "${1:-}" in
    --completion) COMPLETION="yes" ;;
    --no-completion) COMPLETION="no" ;;
    "") ;;
    *) echo "Usage: install-sshd.sh [--completion | --no-completion]" >&2; exit 1 ;;
  esac
  trap cleanup EXIT

  # BASH_SOURCE is empty when the script is piped into bash.
  local src="${BASH_SOURCE[0]:-}"
  SCRIPT_DIR=""
  if [[ -n "$src" && -f "$src" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$src")" && pwd)"
    [[ -f "$SCRIPT_DIR/sshd.sh" ]] || SCRIPT_DIR=""
  fi
  WEB_INSTALL=false
  if [[ -z "$SCRIPT_DIR" ]]; then
    WEB_INSTALL=true
    SCRIPT_DIR="${SSHD_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/sshd}"
    download_files "$SCRIPT_DIR"
    SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" && pwd)"
  fi
  SCRIPT_PATH="$SCRIPT_DIR/sshd.sh"
  COMPLETION_PATH="$SCRIPT_DIR/sshd-completion.bash"
  [[ "$RC_FILE" != "$ZSHRC" ]] || COMPLETION_PATH="$SCRIPT_DIR/sshd-completion.zsh"

  if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Script not found: $SCRIPT_PATH" >&2
    exit 1
  fi

  mkdir -p -- "$BIN_DIR"

  local temp_file
  temp_file="$(mktemp "$BIN_DIR/.sshd.XXXXXX")"
  CLEANUP+=("$temp_file")

  printf '#!/usr/bin/env bash\n# Managed by install-sshd.sh\nexec bash %q "$@"\n' "$SCRIPT_PATH" > "$temp_file"
  chmod 755 "$temp_file"

  if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
    if cmp -s -- "$temp_file" "$COMMAND_PATH"; then
      echo "sshd is already installed at $COMMAND_PATH"
      finish
      exit 0
    fi

    local replaceable=false old_script="" line existing_lines=()
    if [[ -f "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do existing_lines+=("$line"); done < "$COMMAND_PATH"
      if [[ -n "${existing_lines[0]-}" && ${#existing_lines[@]} -eq 3 &&
            "${existing_lines[0]}" == '#!/usr/bin/env bash' &&
            "${existing_lines[1]}" == '# Managed by install-sshd.sh' &&
            "${existing_lines[2]}" == exec\ bash\ *\ \"\$@\" ]]; then
        replaceable=true
        old_script="${existing_lines[2]#exec bash }"
      fi
    fi

    if [[ "$replaceable" != true ]]; then
      echo "Refusing to overwrite a command not recognized as an sshd launcher: $COMMAND_PATH" >&2
      exit 1
    fi

    echo "Replacing the existing sshd launcher at $COMMAND_PATH"
    # The launcher holds the path as printed by %q; a path that needed quoting is skipped.
    carry_over_config "${old_script% \"\$@\"}"
  fi

  mv -- "$temp_file" "$COMMAND_PATH"
  echo "Installed sshd at $COMMAND_PATH"
  finish

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      echo "$BIN_DIR is not currently in PATH."
      echo "Add this to your shell configuration, then open a new terminal:"
      echo "  export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
}

main "$@"
