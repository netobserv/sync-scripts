#!/bin/bash

source "$(dirname "$0")/common.sh"

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Synchronize downstream repositories from upstream"
   echo
   echo "Syntax: sync.sh [-h|-d|-y|-p] [-l log_lines] TARGET"
   echo "Options:"
   echo "  -h             Print this help."
   echo "  -d             Dry run (do not push to remote downstream)."
   echo "  -y             Yes-mode (non-interactive: proceed without asking)."
   echo "  -p             PR-mode (push to fork and create PRs instead of pushing directly to downstream)."
   echo "  -l log_lines   Number of log lines to show (default: 30)."
   echo
   echo "Arguments:"
   echo "  TARGET     Target downstream branch"
   echo
   echo "Example:"
   echo "  ./sync.sh release-1.12"
   echo "  ./sync.sh -p release-1.12   # for non-admin users"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
dry_run=0
yes_mode=0
pr_mode=0
log_lines=30

while getopts "h?dypl:" opt; do
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
    p)
			pr_mode=1
      ;;
    l)
      log_lines="$OPTARG"
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

confirm || exit 1

merge_and_push() {
  local repo=$1
  local downstream_branch=$2
  local upstream_branch=$3
  local downstream_repo=$4
  local tmp_branch="tmp-$downstream_branch"

  git checkout -B $tmp_branch downstream/$downstream_branch
  git reset --hard downstream/$downstream_branch

  git merge --no-edit upstream/$upstream_branch
  if [[ "$?" != "0" ]]; then
 		warnings+=("Merge failed in \"$repo\", branch \"$downstream_branch\"; resolve conflicts, merge and push manually.")
  elif [[ $dry_run == 1 ]]; then
    echo "DRY RUN: skip push $tmp_branch to downstream/$downstream_branch. You can push manually if you wish."
  else
    git log -${log_lines} --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset' --abbrev-commit --abbrev=8 --date=format:'%Y-%m-%d %H:%M'
    confirm "Merge done. Proceed with push?" || return
    push_or_pr "${downstream_repo}" "${downstream_branch}" "Sync ${downstream_branch} from upstream"
  fi
}

i_cpnt=0
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
  ds_repo=${downstream_repos[$i_cpnt]}
  merge_and_push $repo $target main $ds_repo

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
        merge_and_push $repo $target-$variant main-$variant $ds_repo
      fi
    done
  fi
  popd
  i_cpnt="$((i_cpnt+1))"
done

print_warnings
