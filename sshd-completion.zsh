# Zsh tab completion for sshd.
_SSHD_ZSH_SCRIPT="${${(%):-%x}:A:h}/sshd.sh"

_sshd_zsh_complete() {
  local cur="${words[CURRENT]}" prev="${words[CURRENT-1]}" word
  local -a flags candidates
  local -i i

  case "$prev" in
    -i) _files; return ;;
    -t)
      candidates=("${(@f)$(bash "$_SSHD_ZSH_SCRIPT" -N 2>/dev/null)}")
      compadd -- "${candidates[@]}"
      return ;;
    -u|-H) return ;;
  esac

  for ((i=2; i<CURRENT; i++)); do
    word="${words[i]}"
    case "$word" in
      -t|-i|-u|-H)
        if ((i + 1 < CURRENT)); then
          flags+=("$word" "${words[i+1]}")
        fi
        ((i++)) ;;
    esac
  done
  if [[ "$cur" == -* ]]; then
    compadd -- -t -i -u -H -c -T -d -h
    return
  fi

  candidates=("${(@f)$(bash "$_SSHD_ZSH_SCRIPT" "${flags[@]}" -C "$cur" 2>/dev/null)}")
  (( ${#candidates} )) && compadd -S '' -- "${candidates[@]}"
  return 0
}

compdef _sshd_zsh_complete sshd
