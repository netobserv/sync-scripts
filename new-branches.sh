#!/bin/bash

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Create new branches on downstream repositories, and bump version accordingly."
   echo
   echo "Syntax: new-branches.sh [-h|-y] SOURCE TARGET"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo
   echo "Arguments:"
   echo "  SOURCE     Source downstream branch"
   echo "  TARGET     Target downstream branch"
   echo
   echo "Example:"
   echo "  ./new-branches.sh release-1.12 release-1.13"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
yes_mode=0
repos=(operator ebpf-agent flowlogs-pipeline console-plugin cli)
cp_variants=(pf4 pf5)

while getopts "h?y" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 0
      ;;
    y)
			yes_mode=1
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

source="$1"
target="$2"

# Sanity checks
for repo in "${repos[@]}"; do
  echo -e "\n\033[1mSanity check on $repo\033[0m"
  pushd $repo
  git fetch downstream
  git ls-remote --exit-code --heads downstream refs/heads/$source
  if [[ "$?" != "0" ]]; then
    echo "Branch downstream/$source not found. Stopping here."
    exit 1
  fi
  git diff HEAD --exit-code
  if [[ "$?" != "0" ]]; then
    echo "There are uncommited changes in $repo, commit or reset manually before running this script. Stopping here."
    exit 1
  fi
  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      git ls-remote --exit-code --heads downstream refs/heads/$source-$variant
      if [[ "$?" != "0" ]]; then
        echo "Branch downstream/$source-$variant not found. Stopping here."
        exit 1
      fi
    done
  fi
  popd
done

x=`echo ${target} | cut -d - -f2 | cut -d . -f1`
y=`echo ${target} | cut -d - -f2 | cut -d . -f2`

echo ""
echo "Creating branches \"downstream/$target\" as copies of \"downstream/$source\", then bumping to $x.$y.0"

if [[ $yes_mode != 1 ]]; then
  read -p "Continue? [yN] " yn
  echo
  if [[ ! $yn =~ ^[Yy]$ ]] ; then
    exit 1
  fi
fi

bump_and_push() {
  local repo=$1
  local source_branch=$2
  local target_branch=$3
  local tmp_branch="tmp-$target_branch"

  git checkout -B $tmp_branch downstream/$source_branch
  if [[ "$?" != "0" ]]; then
    echo "Could not check out, please make sure all repos are in a clean state without uncommited changes. Stopping here."
    exit 1
  fi
  git reset --hard downstream/$source_branch

  local dockerfile_args_path="./Dockerfile-args.downstream"
  if [[ "$repo" == "flowlogs-pipeline" ]]; then
    dockerfile_args_path="./contrib/docker/Dockerfile-args.downstream"
  fi

  echo "  Updating ${dockerfile_args_path}..."
  sed -i -r "s/^BUILDVERSION=.+/BUILDVERSION=${x}.${y}.0/" ${dockerfile_args_path}
  sed -i -r "s/^BUILDVERSION_Y=.+/BUILDVERSION_Y=${x}.${y}/" ${dockerfile_args_path}

  echo "  Setting branch '${target_branch}' in ./tekton..."
  find .tekton -type f -exec sed -i -e "s/${source_branch}/${target_branch}/g" {} \;

  echo "  Displaying diff..."
  git add -A
  git diff HEAD

  if [[ $yes_mode != 1 ]]; then
    read -p "Looks good to you, and proceed to commit and push ${target_branch}? (you can bring manual changes before answering) [yN] " yn
    echo
    if [[ ! $yn =~ ^[Yy]$ ]] ; then
      exit 1
    fi
  fi

  echo "  Commiting and pushing to ${target_branch}..."
  git commit --allow-empty -m "Prepare ${target_branch}"
  git push downstream HEAD:${target_branch}
}

for repo in "${repos[@]}"; do
  echo -e "\n\033[1mProcessing $repo\033[0m"
  pushd $repo
  bump_and_push $repo $source $target
  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      bump_and_push $repo $source-$variant $target-$variant
    done
  fi
  popd
done
