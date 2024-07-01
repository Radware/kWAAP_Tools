#!/bin/bash

source tools_utils.sh

PRINT_CONTAINERS=false
NAMESPACE=""

print_help() {
	printf '\nKWAAP techdata assit script help.\n Flags:\n'
	printf '\t -n, --namespace \t\t The Namespace in which KWAAP is installed. Default: all namespases\n'
	printf '\t -c, --containers \t\t Prints the list of pod-names and container-names per namespace. Default: Prints pod&conataine names from all namespaces\n'
}

display_usage_get_containers() {
	echo "Usage: $0 [-n|--namespace <namespace_value>] -c|--containers"
}

while [[ "$1" =~ ^- ]]; do
	case $1 in
	-n | --namespace)
		if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
			print_error "Error: The -n|--namespace parameter requires a namespace value."
			display_usage_get_containers
			exit 1
		fi
		NAMESPACE="$2"
		shift
		shift
		;;
	-c | --containers)
		PRINT_CONTAINERS=true
		shift
		;;
	-h | --help)
		##help scenario.
		print_help
		exit 1
		;;
	*)
		print_error "Error: Invalid option -$1"
		display_usage
		exit 1
		;;
	esac
done

get_pods_and_container_per_namespace() {
	local ns=$1 # arg1 - Namespace

	if [[ -z "$ns" ]]; then
		cmd="kubectl get pods --all-namespaces --output=custom-columns=NAMESPACE:.metadata.namespace,POD:.metadata.name,CONTAINERS:.spec.containers[*].name"
		namespace_msg="in namespace $ns"
	else
		cmd="kubectl get pods -n $ns --output=custom-columns=POD:.metadata.name,CONTAINERS:.spec.containers[*].name"
	fi
	handle_cmd $cmd
	if [[ $EXIT_CODE -eq 0 ]]; then
		if [[ -z "$STDOUT_OUTPUT" ]]; then
			echo "No pods found $namespace_msg"
		else
			echo "${STDOUT_OUTPUT[@]}"
		fi
	fi

}

if [ "$PRINT_CONTAINERS" = true ]; then
	get_pods_and_container_per_namespace $NAMESPACE
fi
