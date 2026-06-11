#!/bin/bash

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

if [[ $yes_mode != 1 ]]; then
  read -p "Continue? [yN] " yn
  echo
  if [[ ! $yn =~ ^[Yy]$ ]] ; then
    exit 1
  fi
fi

git clone -o upstream git@github.com:netobserv/network-observability-operator.git operator
pushd operator
git remote add downstream git@github.com:openshift/network-observability-operator.git
git fetch upstream
git fetch downstream
popd

git clone -o upstream git@github.com:netobserv/netobserv-ebpf-agent.git ebpf-agent
pushd ebpf-agent
git remote add downstream git@github.com:openshift/network-observability-ebpf-agent.git
git fetch upstream
git fetch downstream
popd

git clone -o upstream git@github.com:netobserv/flowlogs-pipeline.git flowlogs-pipeline
pushd flowlogs-pipeline
git remote add downstream git@github.com:openshift/network-observability-flowlogs-pipeline.git
git fetch upstream
git fetch downstream
popd

git clone -o upstream git@github.com:netobserv/netobserv-web-console.git console-plugin
pushd console-plugin
git remote add downstream git@github.com:openshift/network-observability-console-plugin.git
git fetch upstream
git fetch downstream
popd

git clone -o upstream git@github.com:netobserv/netobserv-cli.git cli
pushd cli
git remote add downstream git@github.com:openshift/network-observability-cli.git
git fetch upstream
git fetch downstream
popd
