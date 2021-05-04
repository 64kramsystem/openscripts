#!/bin/bash
# shellcheck disable=SC2002 # annoying `cat | jq`

set -o errexit
set -o pipefail
set -o nounset
shopt -s inherit_errexit

# Source: https://github.com/Tarvinder91/aws-utils/blob/master/S3/Delete-old-version-objects-1000obj-at-a-time.sh
#         https://gist.github.com/pecigonzalo/3f89a4b29b6fae933000ca03720e15c5
#
# Incomplete:
#
# - it needs testing;
# - it needs to be checked if there is an upper limit to the number of objects that `list-object-versions`
#   returns;
# - some functions not only find, but also set, so they should be split.
#
# Note that this purpose can be easily accomplished by lifetimes, so this is mostly a reference for
# how to work with awscli in general.

v_bucket=
v_prefix=
v_data_dir=
v_batch_size=1000
v_execute=        # boolean: false=blank, true=anything else

v_no_of_obj=

c_blank_prefix_dirname=blank_prefix
c_help="Usage: $(basename "$0") [-h|--help] [-x|--execute] [-p|--prefix <prefix>] [-b|--batch-size <size>] [-d|--data-dir <dir>] <bucket_name>

No write actions are performed, unless the execute option is specified.

The batch size defaults to $v_batch_size.

The prefix defaults to blank.

The data dir default to <prefix_name> in the current directory (\"blank_prefix\" if no prefix is provided."

function decode_cmdline_options {
  local data_dir

  local params
  params=$(getopt --options hxp:b:d: --long help,execute,prefix:,batch-size:,data-dir: --name "$(basename "$0")" -- "$@")

  eval set -- "$params"

  while true; do
    case "$1" in
      -h|--help)
        echo "$c_help"
        exit 0 ;;
      -x|--execute)
        v_execute=1
        shift ;;
      -p|--prefix)
        v_prefix=$2
        shift 2 ;;
      -b|--batch-size)
        v_batch_size=$2
        shift 2 ;;
      -d|--data-dir)
        data_dir=$2
        shift 2 ;;
      --)
        shift
        break ;;
    esac
  done

  if [[ $# -ne 1 ]]; then
    >&2 echo "$c_help"
    exit 1
  fi

  v_bucket=$1
  v_data_dir=${data_dir:-$(pwd)/${v_prefix:-$c_blank_prefix_dirname}}
}

function print_params {
  echo "Running with params:"
  echo "- prefix:     ${v_prefix:-(none)}"
  echo "- data_dir:   ${v_data_dir}"
  echo "- batch_size: ${v_batch_size}"
  echo "- execute:    ${v_execute:-no}"
  echo
}

function create_and_switch_to_prefix_objects_dir {
  if [[ -d $v_data_dir ]]; then
    echo "The data dir already exists. Press enter to delete it and proceed..."
    read -rsn 1
    rm -r "$v_data_dir"
    echo
  fi

  mkdir -p "$v_data_dir"
  pushd "$v_data_dir" > /dev/null
}

function register_exit_hook {
  function _exit_hook { popd > /dev/null; }
  trap _exit_hook EXIT
}

function get_prefix_size {
  local filename=$1

  echo -n "Objects number/size currently${v_prefix:+ with prefix '$v_prefix'} (current version): "

  aws s3 ls --summarize --human-readable "s3://$v_bucket/$v_prefix" --recursive > "$filename"

  tail -2 "$filename" | perl -0777 -ne 'print join("/", m/: (.+)$/mg)."\n"'
}

function find_objects_total_number {
  local filename=$1

  echo -n "Total no. of objects${v_prefix:+ with prefix '$v_prefix'} including old version objects: "

  aws s3api list-object-versions --max-items 2 --prefix "$v_prefix" --bucket "$v_bucket" | jq '.Versions' | tee "$filename"

  cat "$filename" | jq 'length'
}

function find_and_set_old_version_objects_number {
  local all_objects_filename=$1
  local old_objects_filename=$2

  echo -n "Old version objects${v_prefix:+ with prefix '$v_prefix'}: "

  cat "$all_objects_filename" | jq '.[] | select(.IsLatest | not)' | jq -s '.' > "$old_objects_filename"
  v_no_of_obj=$(cat "$old_objects_filename" | jq 'length')

  echo "$v_no_of_obj"
}

function delete_old_versions {
  local filename_prefix=$1

  echo

  for ((i = 0; i < v_no_of_obj; i+=v_batch_size)); do
    local oldversions
    local next=$((i + v_batch_size - 1))

    echo "Deleting records from $i to $next${v_execute:- (dry run)}..."

    oldversions=$(cat "old-objects-$v_bucket.json" |  jq '.[] | {Key,VersionId}' | jq -s '.' | jq ".[$i:$next]")
    cat > "$filename_prefix$i.json" << EOF
{
"Objects":$oldversions,
"Quiet":true
}
EOF

    if [[ -n $v_execute ]]; then
      aws s3api delete-objects --bucket "$v_bucket" --delete "file://$filename_prefix$i.json"
    fi
  done
}

function delete_markers {
  local filename_prefix=$1

  echo

  aws s3api list-object-versions --bucket "$v_bucket" --prefix "$v_prefix"  | jq '.DeleteMarkers' > "delete-markers-$v_bucket.json"

  local no_of_markers
  no_of_markers=$(cat "delete-markers-$v_bucket.json" | jq 'length')

  for ((i=0; i < no_of_markers; i+=v_batch_size)); do
    local markers
    local next=$((i + v_batch_size - 1))

    echo "Deleting markers from $i to $next${v_execute:- (dry run)}..."

    markers=$(cat "delete-markers-$v_bucket.json" |  jq '.[] | {Key,VersionId}' | jq -s '.' | jq ".[$i:$next]")

    cat > "$filename_prefix$i.json" << EOF
{
"Objects":$markers,
"Quiet":true
}
EOF
    if [[ -n $v_execute ]]; then
      aws s3api delete-objects --bucket "$v_bucket" --delete "file://$filename_prefix$i.json"
    fi
  done
}

decode_cmdline_options "$@"
print_params
create_and_switch_to_prefix_objects_dir
register_exit_hook
get_prefix_size "object-list-$v_bucket.txt"
find_objects_total_number "all-objects-$v_bucket.json"
find_and_set_old_version_objects_number "all-objects-$v_bucket.json" "old-objects-$v_bucket.json"
delete_old_versions "deleted-files-start-index-"
delete_markers "deleted-markers-start-index-"
get_prefix_size "object-list-$v_bucket-AFTER-DELETION.txt"
