#!/bin/bash

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Set the z-stream version after a release. Switch tekton from ystream to zstream if necessary."
   echo
   echo "Syntax: set-z.sh [-h|-y] VERSION"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo
   echo "Arguments:"
   echo "  VERSION    Version to set for the next z-stream."
   echo
   echo "Example:"
   echo "  ./set-z.sh 2.0.1"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
yes_mode=0
repos=(operator ebpf-agent flowlogs-pipeline console-plugin cli)
tekton_all_cpnt=("network-observability-operator" "netobserv-ebpf-agent" "flowlogs-pipeline" "network-observability-console-plugin" "network-observability-cli")
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

# Sanity checks
for repo in "${repos[@]}"; do
  echo -e "\n\033[1mSanity check on $repo\033[0m"
  pushd $repo
  git fetch downstream
  git ls-remote --exit-code --heads downstream refs/heads/$target
  if [[ "$?" != "0" ]]; then
    echo "Branch downstream/$target not found. Stopping here."
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
      git ls-remote --exit-code --heads downstream refs/heads/$target-$variant
      if [[ "$?" != "0" ]]; then
        echo "Branch downstream/$target-$variant not found. Stopping here."
        exit 1
      fi
    done
  fi
  popd
done

echo ""
echo "Bumping branches \"downstream/$target\" to $x.$y.$z"

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

check_tekton_file_names() {
  local tekton_y=$1
  local tekton_z=$2
  if [[ -f ${tekton_y} ]]; then
    if [[ -f ${tekton_z} ]]; then
      echo "  WARNING: both ystream and zstream tekton files found; deleting ystream."
      rm ${tekton_y}
    else
      echo "  Moving tekton ystream to stream."
      mv ${tekton_y} ${tekton_z}
    fi
  fi
}

bump_and_push() {
  local repo=$1
  local target_branch=$2
  local tekton_component=$3
  local tmp_branch="tmp-$target_branch"

  git checkout -B $tmp_branch downstream/$target_branch
  if [[ "$?" != "0" ]]; then
    echo "Could not check out, please make sure all repos are in a clean state without uncommited changes. Stopping here."
    exit 1
  fi
  git reset --hard downstream/$target_branch

  local dockerfile_args_path="./Dockerfile-args.downstream"
  if [[ "$repo" == "flowlogs-pipeline" ]]; then
    dockerfile_args_path="./contrib/docker/Dockerfile-args.downstream"
  fi

  old=`cat ${dockerfile_args_path} | grep "BUILDVERSION=" | sed -r 's/BUILDVERSION=(.+)/\1/'`
  oldx=`echo ${old} | cut -d . -f1`
  oldy=`echo ${old} | cut -d . -f2`
  oldz=`echo ${old} | cut -d . -f3`
  nextz="$((oldz+1))"
  if [[ "$oldx" != "$x" || "$oldy" != "$y" || "$nextz" != "$z" ]]; then
    warnings+=("Skipping ${repo}: it doesn't look like a z-stream bump (old version: ${old}, new version: ${version}). Please check manually.")
    return
  fi

  echo "  Updating ${dockerfile_args_path}..."
  sed -i -r "s/^BUILDVERSION=.+/BUILDVERSION=${x}.${y}.${z}/" ${dockerfile_args_path}

  echo "  Targeting zstream in ./tekton files..."
  find .tekton -type f -exec sed -i -e "s/ystream/zstream/g" {} \;
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

  if [[ $yes_mode != 1 ]]; then
    read -p "Looks good to you, and proceed to commit and push ${target_branch}? (you can bring manual changes before answering) [yN] " yn
    echo
    if [[ ! $yn =~ ^[Yy]$ ]] ; then
      exit 1
    fi
  fi

  echo "  Commiting and pushing to ${target_branch}..."
  git commit --allow-empty -m "Prepare ${x}.${y}.${z}"
  git push downstream HEAD:${target_branch}
}

i_cpnt=0
for repo in "${repos[@]}"; do
  echo -e "\n\033[1mProcessing $repo\033[0m"
  pushd $repo
  tekton_cpnt=${tekton_all_cpnt[$i_cpnt]}
  bump_and_push $repo $target $tekton_cpnt
  if [[ "$repo" == "console-plugin" ]]; then
    for variant in "${cp_variants[@]}"; do
      echo -e "\n\033[1mVariant: $variant\033[0m"
      bump_and_push $repo $target-$variant $tekton_cpnt-$variant
    done
  fi
  popd
  i_cpnt="$((i_cpnt+1))"
done

print_warnings
