# Bash tab completion for sshd: completes target names and remote folders over ssh.
# Loaded from ~/.bashrc by install-sshd.sh; only affects the `sshd` command.

_SSHD_SH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sshd.sh"

_sshd_read_compreply() {
  local line
  COMPREPLY=()
  while IFS= read -r line; do COMPREPLY+=("$line"); done
}

_sshd_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="" i line esc
  local -a flags=() lines=()
  _SSHD_LOCAL_COMPLETION=false
  COMPREPLY=()
  [[ $COMP_CWORD -ge 1 ]] && prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "$prev" in
    -i) _SSHD_LOCAL_COMPLETION=true; _sshd_read_compreply < <(compgen -f -- "$cur"); return 0 ;;
    -t) _sshd_read_compreply < <(compgen -W "$(bash "$_SSHD_SH" -N 2>/dev/null)" -- "$cur"); return 0 ;;
    -u|-H) return 0 ;;
  esac

  # Reuse any -t/-i/-u/-H the user already typed.
  for ((i = 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      -t|-i|-u|-H)
        if ((i + 1 < COMP_CWORD)); then
          flags+=("${COMP_WORDS[i]}" "${COMP_WORDS[i+1]}")
          ((i++))
        fi
        ;;
    esac
  done

  if [[ "$cur" == -* ]]; then
    _sshd_read_compreply < <(compgen -W "-t -i -u -H -c -T -d -h" -- "$cur")
    return 0
  fi

  # Inside quotes the word starts with the quote character; otherwise undo backslash escapes.
  local q=""
  if [[ "$cur" == \'* || "$cur" == \"* ]]; then
    q="${cur:0:1}"
    cur="${cur:1}"
  else
    cur="${cur//\\/}"
  fi
  while IFS= read -r line; do lines+=("$line"); done < <(bash "$_SSHD_SH" ${flags[@]+"${flags[@]}"} -C "$cur" 2>/dev/null)

  for line in ${lines[@]+"${lines[@]}"}; do
    case "$q" in
      "'")
        esc="'${line//\'/\'\\\'\'}"
        ;;
      '"')
        esc="${line//[\\\"\$\`]/\\&}"
        esc="\"$esc"
        ;;
      *)
        # %q keeps a backslash before a leading ~ so the local shell cannot expand it.
        printf -v esc '%q' "$line"
        ;;
    esac
    if [[ "$line" == */ ]]; then
      type compopt >/dev/null 2>&1 && compopt -o nospace 2>/dev/null
    elif [[ -n "$q" ]]; then
      esc+="$q"
    fi
    COMPREPLY+=("$esc")
  done
  return 0
}

_sshd_complete_legacy() {
  local item escaped
  local -a results=()
  _sshd_complete
  for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do
    if [[ "$_SSHD_LOCAL_COMPLETION" == true ]]; then
      printf -v escaped '%q' "$item"
      if [[ -d "$item" ]]; then
        item="$escaped/"
      else
        item="$escaped "
      fi
    elif [[ "$item" != */ ]]; then
      item="$item "
    fi
    results+=("$item")
  done
  COMPREPLY=(${results[@]+"${results[@]}"})
}

if type compopt >/dev/null 2>&1; then
  complete -F _sshd_complete sshd
else
  complete -o nospace -F _sshd_complete_legacy sshd
fi
