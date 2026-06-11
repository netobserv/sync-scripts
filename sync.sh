#!/bin/bash

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Synchronize downstream repositories from upstream"
   echo
   echo "Syntax: sync.sh [-h|-d|-y] TARGET"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -d         Dry run (do not push to remote downstream)."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo
   echo "Arguments:"
   echo "  TARGET     Target downstream branch"
   echo
   echo "Example:"
   echo "  ./sync.sh release-1.12"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
dry_run=0
yes_mode=0
repos=(operator ebpf-agent flowlogs-pipeline console-plugin cli)
cp_variants=(pf4 pf5)

while getopts "h?dy" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 0
      ;;
    d)
			dry_run=1
      ;;
    y)
			yes_mode=1
      ;;
  esac
done

shift $((OPTIND-1))
[ "${1:-}" = "--" ] && shift

if [ "$#" == "0" ]; then
	echo "Missing argument: TARGET"
	show_help
	exit 1
fi

if [ "$#" != "1" ]; then
	echo "Too many arguments: $@"
	show_help
	exit 1
fi

dry_run_text=""
if [[ $dry_run == 1 ]]; then
  echo "DRY RUN: remote will not be updated"
  dry_run_text=" (dry run)"
fi

target="$1"

echo "Synchronizing \"downstream/$target\" with \"upstream/main${dry_run_text}\". A temporary local branch named \"tmp-$target\" will be created/overwritten."

if [[ $yes_mode != 1 ]]; then
  read -p "Continue? [yN] " yn
  echo
  if [[ ! $yn =~ ^[Yy]$ ]] ; then
    exit 1
  fi
fi

warnings=()

print_warnings() {
	for warning in "${warnings[@]}"; do
		echo "WARNING: $warning"
	done
}

merge_and_push() {
  local repo=$1
  local downstream_branch=$2
  local upstream_branch=$3
  local tmp_branch="tmp-$downstream_branch"

  git checkout -B $tmp_branch downstream/$downstream_branch
  git reset --hard downstream/$downstream_branch

  git merge upstream/$upstream_branch
  if [[ "$?" != "0" ]]; then
 		warnings+=("Merge failed in \"$repo\", branch \"$downstream_branch\"; resolve conflicts, merge and push manually.")
  elif [[ $dry_run == 1 ]]; then
    echo "DRY RUN: skip push $tmp_branch to downstream/$downstream_branch. You can push manually if you wish."
  else
    if [[ $yes_mode != 1 ]]; then
      read -p "Merge done. Proceed with push? [yN] " yn
      echo
      if [[ ! $yn =~ ^[Yy]$ ]] ; then
        return
      fi
    fi
    # Proceed with push
    git push downstream HEAD:$downstream_branch
  fi
}

for repo in "${repos[@]}"; do
  echo -e "\n\033[1mProcessing $repo\033[0m"
  pushd $repo
  git fetch upstream
  git fetch downstream
  git ls-remote --exit-code --heads downstream refs/heads/$target
  if [[ "$?" != "0" ]]; then
    echo "Branch downstream/$target not found. Create the branches before running sync.sh. You can use new-branches.sh."
    exit 1
  fi
  merge_and_push $repo $target main

  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      git diff HEAD --exit-code
      if [[ "$?" != "0" ]]; then
        warnings+=("Sounds like console-plugin previous merge failed, cannot proceed with this variant. Run again the script after resolving conflicts for syncing next variant.")
      else
        git ls-remote --exit-code --heads downstream refs/heads/$target-$variant
        if [[ "$?" != "0" ]]; then
          echo "Branch downstream/$target-$variant not found. Create the branches before running sync.sh. You can use new-branches.sh."
          exit 1
        fi
        merge_and_push $repo $target-$variant main-$variant
      fi
    done
  fi
  popd
done

print_warnings
