#!/bin/bash

source "$(dirname "$0")/common.sh"

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Set the z-stream version after a release. Switch tekton from ystream to zstream if necessary."
   echo
   echo "Syntax: set-z.sh [-h|-y|-p] VERSION"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo "  -p         PR-mode (push to fork and create PRs instead of pushing directly to downstream)."
   echo
   echo "Arguments:"
   echo "  VERSION    Version to set for the next z-stream."
   echo
   echo "Example:"
   echo "  ./set-z.sh 2.0.1"
   echo "  ./set-z.sh -p 2.0.1   # for non-admin users"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
yes_mode=0
pr_mode=0

while getopts "h?yp" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 0
      ;;
    y)
			yes_mode=1
      ;;
    p)
			pr_mode=1
      ;;
  esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

if [[ "$#" == "0" ]]; then
	echo "Missing arguments"
	show_help
	exit 1
fi

if [ "$#" != "1" ]; then
	echo "Too many arguments: $@"
	show_help
	exit 1
fi

version="$1"
x=`echo ${version} | cut -d . -f1`
y=`echo ${version} | cut -d . -f2`
z=`echo ${version} | cut -d . -f3`
target="release-${x}.${y}"

sanity_check_repos "$target"

echo ""
echo "Bump branches \"downstream/$target\" to $x.$y.$z"

confirm || exit 1

check_tekton_file_names() {
  local tekton_y=$1
  local tekton_z=$2
  if [[ -f ${tekton_y} ]]; then
    if [[ -f ${tekton_z} ]]; then
      echo "  WARNING: both ystream and zstream tekton files found; deleting ystream."
      rm ${tekton_y}
    else
      echo "  Moving tekton ystream to zstream."
      mv ${tekton_y} ${tekton_z}
    fi
  fi
}

bump_and_push() {
  local repo=$1
  local target_branch=$2
  local tekton_component=$3
  local downstream_repo=$4
  local tmp_branch="tmp-$target_branch"

  git checkout -B $tmp_branch downstream/$target_branch
  if [[ "$?" != "0" ]]; then
    echo "Could not check out, please make sure all repos are in a clean state without uncommited changes. Stopping here."
    exit 1
  fi
  git reset --hard downstream/$target_branch

  local dockerfile_args_path
  dockerfile_args_path=$(get_dockerfile_args_path "$repo")

  old=`cat ${dockerfile_args_path} | grep "BUILDVERSION=" | sed -r 's/BUILDVERSION=(.+)/\1/'`
  oldx=`echo ${old} | cut -d . -f1`
  oldy=`echo ${old} | cut -d . -f2`
  oldz=`echo ${old} | cut -d . -f3`
  nextz="$((oldz+1))"
  if [[ "$oldx" == "$x" && "$oldy" == "$y" && "$oldz" == "$z" ]]; then
    echo "${repo}: same version detected; assuming you're just re-running the script? That's ok."
  elif [[ "$oldx" != "$x" || "$oldy" != "$y" || "$nextz" != "$z" ]]; then
    warnings+=("Skipping ${repo}: it doesn't look like a z-stream bump (old version: ${old}, new version: ${version}). Please check manually.")
    return
  fi

  echo "  Updating ${dockerfile_args_path}..."
  $SED -i -r "s/^BUILDVERSION=.+/BUILDVERSION=${x}.${y}.${z}/" ${dockerfile_args_path}

  echo "  Checking ./tekton files..."
  find .tekton -type f -exec $SED -i -e "s/ystream/zstream/g" {} \;
  check_tekton_file_names "./.tekton/${tekton_component}-ystream-pull-request.yaml" "./.tekton/${tekton_component}-zstream-pull-request.yaml"
  check_tekton_file_names "./.tekton/${tekton_component}-ystream-push.yaml" "./.tekton/${tekton_component}-zstream-push.yaml"
  if [[ "$repo" == "operator" ]]; then
    # Operator also has the bundle component
    check_tekton_file_names "./.tekton/${tekton_component}-bundle-ystream-pull-request.yaml" "./.tekton/${tekton_component}-bundle-zstream-pull-request.yaml"
    check_tekton_file_names "./.tekton/${tekton_component}-bundle-ystream-push.yaml" "./.tekton/${tekton_component}-bundle-zstream-push.yaml"
  fi

  echo "  Displaying diff..."
  git add -A
  git diff HEAD

  confirm "Looks good to you, and proceed to commit and push ${target_branch}? (you can bring manual changes before answering)" || return

  echo "  Commit and push to ${target_branch}..."
  git commit --allow-empty -m "Prepare ${x}.${y}.${z}"
  push_or_pr "${downstream_repo}" "${target_branch}" "Prepare ${x}.${y}.${z}"
}

i_cpnt=0
for repo in "${repos[@]}"; do
  echo -e "\n\033[1mProcessing $repo\033[0m"
  pushd $repo
  tekton_cpnt=${tekton_all_cpnt[$i_cpnt]}
  ds_repo=${downstream_repos[$i_cpnt]}
  bump_and_push $repo $target $tekton_cpnt $ds_repo
  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      bump_and_push $repo $target-$variant $tekton_cpnt-$variant $ds_repo
    done
  fi
  popd
  i_cpnt="$((i_cpnt+1))"
done

print_warnings
