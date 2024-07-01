#! /bin/bash

# /*
#  * ******************************************************************************
#  *  * Copyright © 2019-2022, Radware Ltd., all rights reserved.
#  *  * The programs and information contained herein are licensed only and not sold.
#  *  * The applicable license terms are posted at https://www.radware.com/documents/eula/ and they are also available directly from Radware Ltd.
#  *  *****************************************************************************
#  */

source tools_utils.sh

set -f

#our defaults:
DEFAULT_HELM_RELEASE_NAME="waas"

NAMESPACE=$DEFAULT_NAMESPACE
HELM_RELEASE_NAME=$DEFAULT_HELM_RELEASE_NAME

CONFIG_MAPS_FILENAME="config_maps"
CRDs_FILENAME="crds"
MANIFEST_FILENAME="manifest.yaml"
DEPLOYMENTS_FILENAME="deployments.yaml"
STATEFULSETS_FILENAME="statefulsets.yaml"
DESCRIBES_FILENAME="describes.yaml"

CTR=1

#Backup original IFS (word separator)
OLD_IFS="$IFS"
#Define separator to NewLine only
IFS=$'\n'

print_delimiter() {
	print_msg '\n=================================================>\n\n'
}

print_help() {
	printf '\nKWAAP techdata dump script help.\n Flags:\n'
	printf '\t -n, --crd_only \t\t Skip Config Maps.'
	printf '\t -n, --cm_only \t\t Skip Custom Resources.'
	printf '\t -n, --all_cm \t\t Collect all kWAAP related ConfigMaps.'
	printf '\t -n, --namespace \t\t The Namespace in which KWAAP is installed. default: %s\n' "$DEFAULT_NAMESPACE"
	printf '\t -r, --releasename \t\t The Helm release name with which KWAAP was installed. default: %s\n' "$DEFAULT_HELM_RELEASE_NAME"
	printf '\t -mcu, --memory-cpu-usage \t\t Collect memory and CPU usage for nodes, pods, and containers.'
	printf '\t\t\t Note: the metrics-server will be installed if it has not been installed previously.'
	printf '\t -h, --help \t\t Print help message and exit\n'
}

while test $# -gt 0; do
	case "$1" in
	--crd_only | CRD_ONLY)
		CRD_ONLY=1
		;;
	--cm_only | CM_ONLY)
		CM_ONLY=1
		;;
	--all_config_maps)
		ALL_CM=1
		;;
	-d | --dir)
		OUTPUT_REDIR_NAME="$2" # Read the output dir name
		shift
		;;
	-n | --namespace)
		NAMESPACE="$2" #Read the provided NS arg
		shift
		;;
	-r | --releasename)
		HELM_RELEASE_NAME="$2" #Read the provided releasename arg
		shift
		;;
	-mcu | --memory-cpu-usage)
		MEMORY_CPU_USAGE=1
		;;
	-h | --help)
		##help scenario.
		print_help
		exit 1
		;;
	*)
		break
		;;
	esac
	shift
done

#Revert to original separator
IFS=$OLD_IFS

techdata_by_params() {
	local namespace=$1    # arg1 - Namespace
	local release_name=$2 # arg2 - Helm release name
	shift
	shift
	local cmd_array=("$@") # arg3 - List of commands

	array_length=${#cmd_array[@]}
	for ((i = 0; i < array_length; i += 3)); do
		local cmd_to_exec=""
		local filename="${cmd_array[i + 1]}"
		local title="${cmd_array[i + 2]}"

		if [ -z "$namespace" ]; then
			cmd_to_exec=$(printf "${cmd_array[i]}")
		elif [ -z "$release_name" ]; then
			cmd_to_exec=$(printf "${cmd_array[i]}" "$NAMESPACE")
		else
			cmd_to_exec=$(printf "${cmd_array[i]}" "$namespace" "$release_name")
		fi

		if [ -z "$title" ]; then
			print_msg "\n$CTR) Executing '$cmd_to_exec':\n\n"
		else
			print_msg "\n$CTR) $title:\n\n"
		fi
		#exec:
		handle_cmd_and_output "$filename" "$cmd_to_exec"
		((CTR = CTR + 1))
	done
}

techdata() {
	## Defining the list of commands to run.
	## Generally, it makes sense to create the commands with placeholders for common arguments (like NS) and later do a search-and-replace logic to swap
	## the placeholders with the incoming args. Feel free to rise to the challenge and make sure it's independent of any external tools that might no be installed
	## on the client's machine.
	## ******************==> Add your new commands here:
	CMDS_WITHOUT_ARGS=("whoami" "" ""
		"command -v kubectl" "" ""
		"command -v helm" "" ""
		"kubectl version --output=yaml" "" ""
		"helm version" "" ""
		"kubectl config get-contexts" "" ""
		"kubectl get crd" "" ""
		"kubectl get validatingwebhookconfigurations" "" ""
		"helm ls -A" "" ""
	)

	HELM_CMDS_REQUIRE_NS_AND_RELEASE=("helm get values -n %s %s" "" ""
		"helm get manifest -n %s %s" "$MANIFEST_FILENAME" ""
	)

	KUBECTL_CMDS_REQUIRE_NS=(
		"kubectl get deployments -n %s -o wide" "" ""
		"kubectl get deployments -n %s -o yaml" "$DEPLOYMENTS_FILENAME" ""
		"kubectl get statefulsets -n %s -o wide" "" ""
		"kubectl get statefulsets -n %s -o yaml" "$STATEFULSETS_FILENAME" ""
		"kubectl describe pods -n %s" "$DESCRIBES_FILENAME" ""
		"kubectl get pods -n %s -o wide" "" ""
		"kubectl get svc -n %s" "" ""
		"kubectl get -n %s secret" "" ""
		"kubectl get -n %s cm" "" ""
		"kubectl get deployments,statefulsets,daemonsets -n %s -o=jsonpath='{range .items[*]}{.metadata.namespace}{\"\\\\t\"}{.kind}{\"\\\\t\"}{.metadata.name}{\"\\\\t\"}{.spec.template.spec.containers[*].image}{\"\\\\n\"}{end}'" "" "List of used images"
	)
	if [[ "$MEMORY_CPU_USAGE" -eq 1 ]]; then
		metrics_server_install_and_validate
		if [[ $? -eq 1 ]]; then
			CMDS_WITHOUT_ARGS+=("kubectl top nodes" "" "")
			KUBECTL_CMDS_REQUIRE_NS+=("kubectl top pods -n %s" "" "")
			KUBECTL_CMDS_REQUIRE_NS+=("kubectl top pods --containers -n %s" "" "")
		fi
	fi

	print_msg "\n\n =====> kWAAP techdata script start\n\n"
	print_msg "NAMESPACE='$NAMESPACE"
	print_msg "HELM_RELEASE_NAME='$HELM_RELEASE_NAME'"

	## Execute all the cmds that don't require any args:
	techdata_by_params "" "" "${CMDS_WITHOUT_ARGS[@]}"

	## Execute the Helm cmds that require 2 args:
	techdata_by_params "$NAMESPACE" "$HELM_RELEASE_NAME" "${HELM_CMDS_REQUIRE_NS_AND_RELEASE[@]}"

	## Execute kubectl cmds that require 1 arg:
	techdata_by_params "$NAMESPACE" "" "${KUBECTL_CMDS_REQUIRE_NS[@]}"

	metrics_server_delete
}

collect_cm() {
	# Get list of ConfigMaps to backup
	# In case ALL_CM arg or techdata mode was used get all CMs based on app.kubernetes.io/name="WAAS" label
	# Otherwise backup only the CustomRules CM based on kwaf-configmap-type="custom-rules" label
	local ns=""
	local cm=""
	local config_maps_cmd=""
	local config_map=()

	if [[ -n "$ALL_CM" ]]; then
		config_maps_cmd="kubectl get configmap --selector app.kubernetes.io/name=\"WAAS\" --output jsonpath='{range .items[*]}{\"--namespace=\"}{.metadata.namespace}{\" \"}{.metadata.name}{\"\n\"}{end}' --all-namespaces"
	else
		config_maps_cmd="kubectl get configmap --selector kwaf-configmap-type=\"custom-rules\" --output jsonpath='{range .items[*]}{\"--namespace=\"}{.metadata.namespace}{\" \"}{.metadata.name}{\"\n\"}{end}' --all-namespaces"
	fi
	handle_cmd $config_maps_cmd
	config_map="${STDOUT_OUTPUT[@]}"
	for ns_cm in ${config_map[@]}; do
		if [[ -z $ns ]]; then
			ns="$ns_cm"
			continue
		else
			cm="$ns_cm"
		fi
		handle_cmd_and_output "$CONFIG_MAPS_FILENAME" "kubectl get configmap --ignore-not-found $ns $cm --output=yaml"
	done
}

collect_crd() {
	local ns=""
	local crd=""
	local crd_type=""
	local crd_types=()
	local crds=()

	#Get List of CRDs to backup (based on "waas.radware.com" group)
	handle_cmd "kubectl api-resources --api-group=waas.radware.com --output=name"
	crd_types="${STDOUT_OUTPUT[@]}"

	for crd_type in ${crd_types[@]}; do
		# Get all CRD names and namespaces
		handle_cmd "kubectl get $crd_type --all-namespaces --ignore-not-found --output jsonpath='{range .items[*]}{\"--namespace=\"}{.metadata.namespace}{\" \"}{.metadata.name}{\"\n\"}{end}'"
		crds="${STDOUT_OUTPUT[@]}"
		for ns_crd in ${crds[@]}; do
			if [[ -z $ns ]]; then
				ns="$ns_crd"
				continue
			else
				crd="$ns_crd"
			fi
			handle_cmd_and_output "$CRDs_FILENAME" "kubectl get $crd_type --ignore-not-found $ns $crd --output=yaml"
			ns=""
		done
	done
}

collect_crs() {
	local ns=$NAMESPACE
	local crs
	print_msg "\nCollecting CRS from namespace:'$ns'. -"
	crs="$(kubectl get crs -n "$ns" --no-headers -o custom-columns=:metadata.name)"

	for cr in $crs; do
		echo -e "\nCollecting $cr"
		cmd="kubectl get  cr -n $ns $cr -o yaml "
		handle_cmd_and_output "crs_ns_$ns.yaml" "$cmd"
	done
}

## actual run
set_new_output_dir_and_stdout_stderr_files

techdata

print_delimiter
print_msg "\n$CTR) collecting custom resources:\n\n"
((CTR = CTR + 1))

collect_crd
collect_crs
print_delimiter
print_msg "\n$CTR) collecting config maps:\n\n"
((CTR = CTR + 1))
collect_cm

print_msg "\n\n =====> KWAAP techdata script end\n\n"
