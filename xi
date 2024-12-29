#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset
set -o errtrace
shopt -s inherit_errexit

c_wsl_command=(clip.exe)
c_native_command=(xsel -ib)

c_help="Usage: $(basename "$0") [-h|--help] [<filename>]

Without a filename, it pastes stdin into the clipboard.
With a filename, it copies its content.

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

  if [[ $# -gt 1 ]]; then
    echo "$c_help"
    exit 1
  fi
}

function main {
  if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
    local command=("${c_wsl_command[@]}")
  else
    local command=("${c_native_command[@]}")
  fi

  # See https://unix.stackexchange.com/a/273284 about `tee >(cmd)`.
  #
  perl -pe 'chomp if eof' "$@" | tee >("${command[@]}")
}

decode_cmdline_args "$@"
main "$@"
