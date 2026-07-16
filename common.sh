#!/bin/bash

# Shared definitions and helpers for sync scripts.
# Source this file from the other scripts:
#   source "$(dirname "$0")/common.sh"

############################################################
# Repo arrays                                              #
############################################################

repos=(operator ebpf-agent flowlogs-pipeline console-plugin cli)
upstream_repos=("network-observability-operator" "netobserv-ebpf-agent" "flowlogs-pipeline" "netobserv-web-console" "netobserv-cli")
downstream_repos=("network-observability-operator" "network-observability-ebpf-agent" "network-observability-flowlogs-pipeline" "network-observability-console-plugin" "network-observability-cli")
tekton_all_cpnt=("network-observability-operator" "netobserv-ebpf-agent" "flowlogs-pipeline" "network-observability-console-plugin" "network-observability-cli")
cp_variants=(pf4 pf5)

############################################################
# SED detection (macOS compatibility)                      #
############################################################

if command -v gsed &>/dev/null; then
  SED=gsed
else
  SED=sed
fi

############################################################
# Helpers                                                  #
############################################################

confirm() {
  local prompt=${1:-"Continue?"}
  if [[ $yes_mode != 1 ]]; then
    read -p "${prompt} [yN] " yn
    echo
    if [[ ! $yn =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi
  return 0
}

warnings=()

print_warnings() {
  for warning in "${warnings[@]}"; do
    echo "WARNING: $warning"
  done
}

get_dockerfile_args_path() {
  local repo=$1
  if [[ "$repo" == "flowlogs-pipeline" ]]; then
    echo "./contrib/docker/Dockerfile-args.downstream"
  else
    echo "./Dockerfile-args.downstream"
  fi
}

############################################################
# Push or create PR                                        #
############################################################

push_or_pr() {
  local downstream_repo=$1
  local target_branch=$2
  local commit_title=$3

  if [[ $pr_mode == 1 ]]; then
    local pr_branch="${commit_title}-${target_branch}"
    pr_branch=$(echo "$pr_branch" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    local gh_user=$(gh api user --jq '.login')
    # Add fork remote if not present
    if ! git remote | grep -q "^fork$"; then
      local fork_name=""
      if gh api "repos/${gh_user}/${downstream_repo}" &>/dev/null; then
        fork_name="${downstream_repo}"
      fi
      if [[ -z "$fork_name" ]]; then
        local source_repo=$(gh api "repos/openshift/${downstream_repo}" --jq '.source.full_name // empty' 2>/dev/null)
        if [[ -n "$source_repo" ]]; then
          local source_name=$(basename "$source_repo")
          if gh api "repos/${gh_user}/${source_name}" &>/dev/null; then
            fork_name="${source_name}"
          fi
        fi
      fi
      if [[ -z "$fork_name" ]]; then
        echo "  No fork found. Forking openshift/${downstream_repo}..."
        gh repo fork "openshift/${downstream_repo}" --clone=false
        fork_name="${downstream_repo}"
      fi
      local fork_url="git@github.com:${gh_user}/${fork_name}.git"
      echo "  Using fork: ${gh_user}/${fork_name}"
      git remote add fork "${fork_url}"
    fi
    echo "  Pushing to fork branch ${pr_branch}..."
    git push fork HEAD:${pr_branch} -f
    echo "  Creating PR against openshift/${downstream_repo}:${target_branch}..."
    gh pr create --repo "openshift/${downstream_repo}" --base "${target_branch}" --head "${gh_user}:${pr_branch}" --title "${commit_title}" --body "${commit_title}"
  else
    git push downstream HEAD:${target_branch}
  fi
}

############################################################
# Sanity checks                                            #
############################################################

sanity_check_repos() {
  local branch=$1
  for repo in "${repos[@]}"; do
    echo -e "\n\033[1mSanity check on $repo\033[0m"
    pushd $repo
    git fetch downstream
    git ls-remote --exit-code --heads downstream refs/heads/$branch
    if [[ "$?" != "0" ]]; then
      echo "Branch downstream/$branch not found. Stopping here."
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
        git ls-remote --exit-code --heads downstream refs/heads/$branch-$variant
        if [[ "$?" != "0" ]]; then
          echo "Branch downstream/$branch-$variant not found. Stopping here."
          exit 1
        fi
      done
    fi
    popd
  done
}
