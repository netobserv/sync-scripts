#!/bin/bash

source "$(dirname "$0")/common.sh"

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Create new branches on downstream repositories, and bump version accordingly."
   echo
   echo "Syntax: new-branches.sh [-h|-y|-p] SOURCE TARGET"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo "  -p         PR-mode (push to fork and create PRs instead of pushing directly to downstream)."
   echo
   echo "Arguments:"
   echo "  SOURCE     Source downstream branch"
   echo "  TARGET     Target downstream branch"
   echo
   echo "Example:"
   echo "  ./new-branches.sh release-1.12 release-1.13"
   echo "  ./new-branches.sh -p release-1.12 release-1.13   # for non-admin users"
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

if [[ "$#" == "0" || "$#" == "1" ]]; then
	echo "Missing arguments"
	show_help
	exit 1
fi

if [ "$#" != "2" ]; then
	echo "Too many arguments: $@"
	show_help
	exit 1
fi

source_branch="$1"
target="$2"

sanity_check_repos "$source_branch"

x=`echo ${target} | cut -d - -f2 | cut -d . -f1`
y=`echo ${target} | cut -d - -f2 | cut -d . -f2`

echo ""
echo "Creating branches \"downstream/$target\" as copies of \"downstream/$source_branch\", then bumping to $x.$y.0"

confirm || exit 1

bump_and_push() {
  local repo=$1
  local src_branch=$2
  local target_branch=$3
  local downstream_repo=$4
  local tmp_branch="tmp-$target_branch"

  git checkout -B $tmp_branch downstream/$src_branch
  if [[ "$?" != "0" ]]; then
    echo "Could not check out, please make sure all repos are in a clean state without uncommited changes. Stopping here."
    exit 1
  fi
  git reset --hard downstream/$src_branch

  local dockerfile_args_path
  dockerfile_args_path=$(get_dockerfile_args_path "$repo")

  echo "  Updating ${dockerfile_args_path}..."
  $SED -i -r "s/^BUILDVERSION=.+/BUILDVERSION=${x}.${y}.0/" ${dockerfile_args_path}
  $SED -i -r "s/^BUILDVERSION_Y=.+/BUILDVERSION_Y=${x}.${y}/" ${dockerfile_args_path}

  echo "  Setting branch '${target_branch}' in ./tekton..."
  find .tekton -type f -exec $SED -i -e "s/${src_branch}/${target_branch}/g" {} \;

  echo "  Displaying diff..."
  git add -A
  git diff HEAD

  confirm "Looks good to you, and proceed to commit and push ${target_branch}? (you can bring manual changes before answering)" || exit 1

  echo "  Commiting and pushing to ${target_branch}..."
  git commit --allow-empty -m "Prepare ${target_branch}"
  push_or_pr "${downstream_repo}" "${target_branch}" "Prepare ${target_branch}"
}

i_cpnt=0
for repo in "${repos[@]}"; do
  echo -e "\n\033[1mProcessing $repo\033[0m"
  pushd $repo
  ds_repo=${downstream_repos[$i_cpnt]}
  bump_and_push $repo $source_branch $target $ds_repo
  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      bump_and_push $repo $source_branch-$variant $target-$variant $ds_repo
    done
  fi
  popd
  i_cpnt="$((i_cpnt+1))"
done
