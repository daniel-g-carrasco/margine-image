# shellcheck shell=bash
# Share bash history across terminal windows (Margine, issue #278):
# append each command to the history file immediately (history -a) and pull
# in the lines other sessions wrote (history -n), so up-arrow works across
# multiple Ptyxis windows instead of each keeping a private history.
# Appends to PROMPT_COMMAND so it composes with vte.sh's Ptyxis cwd tracking
# ( += promotes a scalar to an array on bash 5.1+; Margine ships bash 5.3 ).
if [ -n "${BASH_VERSION:-}" ]; then
  shopt -s histappend 2>/dev/null
  __margine_hist() { history -a; history -n; }
  case " ${PROMPT_COMMAND[*]-} " in
    *" __margine_hist "*) : ;;
    *) PROMPT_COMMAND+=(__margine_hist) ;;
  esac
fi
