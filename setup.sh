#!/bin/bash

source "$(dirname "$0")/common.sh"

############################################################
# Help                                                     #
############################################################
show_help()
{
   echo "Setup netobserv upstream/downstream repositories for syncing"
   echo
   echo "Syntax: setup.sh [-h|-y]"
   echo "Options:"
   echo "  -h         Print this help."
   echo "  -y         Yes-mode (non-interactive: proceed without asking)."
   echo
   echo "Example:"
   echo "  ./setup.sh -y"
   echo
}

# Reset in case getopts has been used previously in the shell.
OPTIND=1
yes_mode=0

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

if [ "$#" != "0" ]; then
	echo "Too many arguments: $@"
	show_help
	exit 1
fi

echo "Cloning and setting up repositories in current directory."

confirm || exit 1

i=0
for repo in "${repos[@]}"; do
  upstream="${upstream_repos[$i]}"
  downstream="${downstream_repos[$i]}"
  git clone -o upstream "git@github.com:netobserv/${upstream}.git" "$repo"
  pushd "$repo"
  git remote add downstream "git@github.com:openshift/${downstream}.git"
  git fetch upstream
  git fetch downstream
  popd
  i="$((i+1))"
done
