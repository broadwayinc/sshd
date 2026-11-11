#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home/.ssh" "$work/remote/dir space"
touch "$work/home/.ssh/key"
export HOME="$work/home" XDG_BIN_HOME="$work/installed" SSHD_CONF="$work/config"
export LOG="$work/log" PATH="$work/bin:$PATH" SHELL=/bin/bash
printf '[default]\nkey = %s\nuser = user\nhost = host\n' "$HOME/.ssh/key" > "$SSHD_CONF"

cat > "$work/bin/ssh" <<'EOF'
#!/usr/bin/env bash
for last; do :; done
case "$last" in
  *'exec "${SHELL:-/bin/sh}" -l'*) printf '%s\n' "$last" >> "$LOG" ;;
  *) /bin/sh -c "$last" ;;
esac
EOF
chmod +x "$work/bin/ssh"

bash "$repo/install-sshd.sh" --completion
bash "$repo/install-sshd.sh" --completion
"$XDG_BIN_HOME/sshd" -T | grep -q 'default (default)'
"$XDG_BIN_HOME/sshd" -C "$work/remote/" | grep -Fq "$work/remote/dir space/"
source "$repo/sshd-completion.bash"
COMP_WORDS=(sshd -t def) COMP_CWORD=2
_sshd_complete
[[ "${COMPREPLY[0]}" == default ]]
COMP_WORDS=(sshd "$work/remote/no-match") COMP_CWORD=1
_sshd_complete
[[ -z "${COMPREPLY[0]-}" ]]
"$XDG_BIN_HOME/sshd" "$work/remote/dir space"
"$XDG_BIN_HOME/sshd" '~'
grep -q 'exec "${SHELL:-/bin/sh}" -l' "$LOG"
bash "$repo/uninstall-sshd.sh"
! grep -q '# >>> sshd completion >>>' "$HOME/.bashrc"
SHELL=/bin/zsh bash "$repo/install-sshd.sh" --completion
grep -q 'sshd-completion.zsh' "$HOME/.zshrc"
bash "$repo/uninstall-sshd.sh"
! grep -q '# >>> sshd completion >>>' "$HOME/.zshrc"
printf 'not a launcher\n' > "$XDG_BIN_HOME/sshd"
if bash "$repo/install-sshd.sh" --no-completion || bash "$repo/uninstall-sshd.sh"; then
  echo 'An unrelated command was accepted as an sshd launcher.' >&2
  exit 1
fi
echo 'sshd compatibility tests passed'
