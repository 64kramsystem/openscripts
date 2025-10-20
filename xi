#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

c_wsl_command=(clip.exe)
c_native_command=(xsel -ib)

c_help="Usage: $(basename "$0") [-h|--help] [<filename|args…>]

If the arguments are:

- none: it pastes stdin into the clipboard
- one argument (existing filename): copies its content
- multiple args, or one argument (not an existing filename): copies it

Invokes the clipboard commands for the given environment:

- native: '${c_native_command[*]}'
- wsl:    '${c_wsl_command[*]}'"

function decode_cmdline_args {
  local params
  params=$(getopt --options h --long help --name "$(basename "$0")" -- "$@")

  eval set -- "$params"

  while true; do
    case $1 in
      -h|--help)
        echo "$c_help"
        exit 0 ;;
      --)
        shift
        break ;;
    esac
  done
}

function main {
  if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
    local proc_command=("${c_wsl_command[@]}")
  else
    local proc_command=("${c_native_command[@]}")
  fi

  # See https://unix.stackexchange.com/a/273284 about `tee >(cmd)`.

  if [[ $# -eq 0 ]]; then
    perl -pe 'chomp if eof' | tee >("${proc_command[@]}")
  elif [[ $# -eq 1 && -f $1 ]]; then
    # This command also works for the no-args case, actually.
    perl -pe 'chomp if eof' "$@" | tee >("${proc_command[@]}")
  else
    echo -n "$*" | perl -pe 'chomp if eof' | tee >("${proc_command[@]}")
  fi
}

decode_cmdline_args "$@"
main "$@"
