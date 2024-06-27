#!/bin/bash

#Common global variables - used by most scripts:
DEFAULT_NAMESPACE="kwaf"
DEFAULT_HELM_RELEASE_NAME="waas"
OUTPUT_REDIR_NAME=""

NAMESPACE=$DEFAULT_NAMESPACE
HELM_RELEASE_NAME=$DEFAULT_HELM_RELEASE_NAME
# Arguments key-names in JSON arguments file-name:
JSON_FILE_NAMESPACE_ARG="namespace"             # instead of "--namespace"
JSON_FILE_CONTAINER_ARG="container"             # instead of "--container"
JSON_FILE_CONTAINERS_ARG="app_containers"       # instead of "--containers"
JSON_FILE_CONFIG_DUMP_FLAG_ARG="config_dump"    # instead of "--config-dump"
JSON_FILE_SEC_EVENTS_FLAG_ARG="security_events" # instead of "--security-events"
JSON_FILE_ACCEESS_LOGS_FLAG_ARG="access_logs"   # instead of "--access-logs"
JSON_FILE_REQUEST_DATA_FLAG_ARG="requst_data"   # instead of "--requst-data"
JSON_FILE_LOGS_FLAG_ARG="logs"                  # instead of "--logs"
JSON_FILE_PREV_LOGS_FLAG_ARG="previous_logs"    # instead of "--previous-logs"

JSON_FILE_ARG_RET_VALUE="" # - return value of extract_simple_arg_from_json_args_file() and extract_collected_data_flag_arg_from_json_args_file()

STDERR_FILE="" # - the name of the file to which the contents of stderr are copied
STDOUT_FILE="" # - the name of the file to which the contents of stdout will be redirected

STDOUT_OUTPUT="" # - stdout contents returned by handle_cmd()
EXIT_CODE=0      # - stdout cmd exit_code returned by handle_cmd() and handle_cmd_and_output()

# Separators that are used to define and parse the value of the "--containers" argument:
NAMESPACES_SEPARATOR=';'
NAMESPACE_PODS_SEPARATOR=':'
PODS_SEPARATOR=','
POD_CONTAINER_SEPARATOR='#'
RESULT_SEPARATOR='&'

METRICS_SERVER_DELETE=false
METRICS_SERVER_CONFIG_REMOTE="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
METRICS_SERVER_CONFIG_LOCAL="components.yaml"
METRICS_SERVER_CONFIG_USED=$METRICS_SERVER_CONFIG_REMOTE

# extract_containers_arg_from_json_args_file - extracts "--containers" arg value from JSON file
# @params: arg1: json file-name
#          arg2: "--containers" key-name
# @return: CONTAINERS_ARG_LIST in format as of "--containers" arg
#         For example, "ns1:pod1,pod2,pod3" or "ns1:pod1#con1,pod2#con1,pod3#con1"
extract_containers_arg_from_json_args_file() {
	local json_file=$1
	local containers_key=$2

	namespace_list=$(jq -r --arg key_var "$containers_key" '.[$key_var] | keys[]' "$json_file")
	output=""

	for namespace in $namespace_list; do
		pod_container_pairs=$(jq -r --arg namespace "$namespace" --arg separator_var "$POD_CONTAINER_SEPARATOR" '
            .app_containers[$namespace][] |
            (
                if (.pods | length > 0) then
                    .pods[] | . + $separator_var
                else
                    $separator_var
                end
            ) as $pod |
            (
                if (.containers | length > 0) then
                    .containers[] | "\($pod)\(.)"
                else
                    $pod + $separator_var
                end
            )
            ' "$json_file" | paste -sd "$PODS_SEPARATOR")

		output="${output}${namespace}:${pod_container_pairs%,};"
	done

	final_output="${output//[$'\t\r\n']/}" # Remove newlines, tabs, and carriage returns

	# Remove double $POD_CONTAINER_SEPARATOR:
	double="${POD_CONTAINER_SEPARATOR}${POD_CONTAINER_SEPARATOR}"
	single="${POD_CONTAINER_SEPARATOR}"
	CONTAINERS_ARGUMENT_LIST="${final_output//$double/$single}"
}

# extract_collected_data_flag_arg_from_json_args_file - extracts one of flags value from "collected_data" dict in JSON file
# @params: arg1: json file-name
#          arg2: key-name
# @return: JSON_FILE_ARG_RET_VALUE - true/false value
extract_collected_data_flag_arg_from_json_args_file() {
	local json_file=$1
	local flag_key=$2

	JSON_FILE_ARG_RET_VALUE=$(jq -r --arg key "$flag_key" '.collected_data[$key]' "$json_file")
}

# extract_simple_arg_from_json_args_file - extracts one of args value from JSON file
# @params: arg1: json file-name
#          arg2: key-name
# @return: JSON_FILE_ARG_RET_VALUE - true/false value
extract_simple_arg_from_json_args_file() {
	local json_file=$1
	local flag_key=$2

	JSON_FILE_ARG_RET_VALUE=$(jq -r --arg key "$flag_key" '.[$key]' "$json_file")
	if [ "$JSON_FILE_ARG_RET_VALUE" = "null" ]; then
		JSON_FILE_ARG_RET_VALUE=""
	fi
}

# json_file_to_cmd_args - parses the contents of a JSON file with techdata script arguments and
#    updates all relevant global variables that retain the values of the cmd arguments
#   NOTE: if any parameter is defined in both the json-params file and the cmd string arguments,
#         the cmd string argument will be preferred.
# @params: arg1: json file-name
json_file_to_cmd_args() {
	local json_file=$1

	# Check if jq is installed
	if ! command -v jq &>/dev/null; then
		print_error "jq is not installed. Please install jq."
		exit 1
	fi

	extract_simple_arg_from_json_args_file "$json_file" "$JSON_FILE_NAMESPACE_ARG"
	NAMESPACE="$JSON_FILE_ARG_RET_VALUE"
	extract_simple_arg_from_json_args_file "$json_file" "$JSON_FILE_CONTAINER_ARG"

	CONTAINER_NAME="$JSON_FILE_ARG_RET_VALUE"

	extract_containers_arg_from_json_args_file "$json_file" "$JSON_FILE_CONTAINERS_ARG"

	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_CONFIG_DUMP_FLAG_ARG"
	COLLECT_CONFIG_DUMP="$JSON_FILE_ARG_RET_VALUE"
	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_SEC_EVENTS_FLAG_ARG"
	COLLECT_SEC_EVENTS="$JSON_FILE_ARG_RET_VALUE"
	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_ACCEESS_LOGS_FLAG_ARG"
	COLLECT_ACCEESS_LOGS="$JSON_FILE_ARG_RET_VALUE"
	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_REQUEST_DATA_FLAG_ARG"
	COLLECT_REQUEST_DATA="$JSON_FILE_ARG_RET_VALUE"
	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_LOGS_FLAG_ARG"
	COLLECT_LOGS="$JSON_FILE_ARG_RET_VALUE"
	extract_collected_data_flag_arg_from_json_args_file "$json_file" "$JSON_FILE_PREV_LOGS_FLAG_ARG"
	COLLECT_PREV_LOGS="$JSON_FILE_ARG_RET_VALUE"
}

# set_new_output_dir_and_stdout_stderr_files - creates an output directory, if defined in "--dir"  arg, and not already exists;
#     & creates two files:
#        1. <dirname>_stderr.txt - to copy the contents of STDERR.
#        2. <dirname>_stdout.txt - to redirect the contents of STDOUT.
set_new_output_dir_and_stdout_stderr_files() {
	if [[ -z "$OUTPUT_REDIR_NAME" ]]; then
		return
	fi
	if [[ ! -d "$OUTPUT_REDIR_NAME" ]]; then
		handle_cmd "mkdir $OUTPUT_REDIR_NAME"
		if [[ $EXIT_CODE -ne 0 ]]; then
			exit $EXIT_CODE
		fi
		print_msg "\nSTDOUT will be coppied to the file '${STDOUT_FILE}'\n"
		print_msg "\nSTDERR will be coppied to the file '${STDERR_FILE}'\n"
	fi

	STDOUT_FILE="${OUTPUT_REDIR_NAME}/${OUTPUT_REDIR_NAME}_stdout.txt"
	STDERR_FILE="${OUTPUT_REDIR_NAME}/${OUTPUT_REDIR_NAME}_stderr.txt"

}

# print_error - prints an error message to STDERR and to $STDERR_FILE if one is defined.
print_error() {
	local error_msg=("$@")
	if [[ -z "$STDERR_FILE" ]]; then
		echo -e "${error_msg[*]}" >&2
	else
		{ echo -e "${error_msg[*]}" | tee -a "$STDOUT_FILE" "$STDERR_FILE" >&2; }
	fi
}

# print_msg - prints a message to STDOUT and to $STDOUT_FILE if one is defined.
print_msg() {
	local msg=("$@")

	# # redirect stdout to $stdout_file, if defined
	# echo -e "${msg[*]}" ${stdout_file:+>> "$stdout_file"}
	if [[ -z "$STDOUT_FILE" ]]; then
		echo -e "${msg[*]}"
	else
		{ echo -e "${msg[*]}" | tee -a "$STDOUT_FILE" >&1; }
	fi
}

# handle_cmd - executs cmd
# @params: arg1: cmd in string format
# @return: EXIT_CODE - cmd exit_code
#          STDOUT_OUTPUT - stdout contents
handle_cmd() {
	local lineno
	local caller_func
	local caller_script
	read lineno caller_func caller_script <<<$(caller 0)
	local cmd=("$@")
	print_msg "Executing-cmd [$caller_script[$lineno]:$caller_func()]: '${cmd[*]}'..."
	if [[ -z "$STDERR_FILE" ]]; then
		# Collect from stdout; and print stderr contents to the stderr
		STDOUT_OUTPUT=$(eval ${cmd[*]})
	else
		# Collect from stdout; and print stderr contents to the stderr and redirect to the file simultaneously:
		STDOUT_OUTPUT=$(eval ${cmd[*]} 2> >(tee -a "$STDOUT_FILE" "$STDERR_FILE" >&2))
	fi
	EXIT_CODE=$?
	if [[ $EXIT_CODE -ne 0 ]]; then
		print_error " - error exit-code=$EXIT_CODE"
	fi
}

# handle_cmd_and_output - executs cmd and redirects stdout contents to the file, if defined
# @params: arg1: filename for stdout contents redirection
#          arg2: cmd in string format
# @return: EXIT_CODE - cmd exit_code
handle_cmd_and_output() {
	local lineno
	local caller_func
	local caller_script
	read lineno caller_func caller_script <<<$(caller 0)
	local stdout_file=$1
	shift
	local cmd=("$@")

	print_msg "Executing-cmd [$caller_script[$lineno]:$caller_func()]: '${cmd[*]}'..."

	if [[ -z "$OUTPUT_REDIR_NAME" ]]; then
		stdout_file=""
	else
		if [[ ! -z "$stdout_file" ]]; then
			stdout_file="${OUTPUT_REDIR_NAME}/${stdout_file}"
			print_msg "Output redirected to file '$stdout_file'"
		elif [[ ! -z "$STDOUT_FILE" ]]; then
			stdout_file="$STDOUT_FILE"
			echo "Output redirected to file '$STDOUT_FILE'"
		fi
	fi

	if [[ -z "$OUTPUT_REDIR_NAME" ]]; then
		# redirect stdout if $stdout_file is defined
		eval "${cmd[*]}"
		echo -e "---\n"
	else
		# redirect stdout if $stdout_file is defined; and print stderr contents to the stderr and redirect to the file simultaneously:
		# eval "${cmd[*]}" ${stdout_file:+>> "$stdout_file"} 2> >(tee -a "$STDERR_FILE" >&2)
		eval "${cmd[*]}" ${stdout_file:+>> "$stdout_file"} 2> >(tee -a "$STDOUT_FILE" "$STDERR_FILE" >&2)
		eval "echo -e '---\n'" ${stdout_file:+>> "$stdout_file"}
	fi
	EXIT_CODE=$?
	if [[ $EXIT_CODE -ne 0 ]]; then
		print_error " - error exit-code=$EXIT_CODE"
	fi
}

# get_all_pods_per_ns_and_container - collects all pods in the given namespace; or all [pod:container] pairs for a particular container, if one is defined.
# @params: arg1: namespace
#           arg2: container name or empty
# @return: CONTAINERS_ARG_LIST in format as of "--containers" arg
#         For example, "ns1:pod1,pod2,pod3" or "ns1:pod1#con1,pod2#con1,pod3#con1"
get_all_pods_per_ns_and_container() {
	local ns=$1        # arg1 - Namespace
	local container=$2 # arg2 - Conatiner name

	if [[ -z "$container" ]]; then
		print_msg "\nSearching for all the pods in namespace '$ns'"
		cmd="kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}'"
		err_msg="Pods in the '$ns' namespace were not found"
	else
		print_msg "\nSearching for all the pods with container '$container' in namespace '$ns'"
		cmd="kubectl get pods -n $ns -o=jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{range .spec.containers[*]}{.name}{\"\\t\"}{end}{\"\\n\"}{end}' | grep $container | awk '{print \$1}'"
		err_msg="Pods with the '$container' container in the '$ns' namespace were not found"
	fi

	handle_cmd $cmd
	if [[ $EXIT_CODE -eq 0 ]]; then
		if [[ -z "$STDOUT_OUTPUT" ]]; then
			print_error "Error: $err_msg"
		else
			readarray -t pods_array <<<"$(echo "$STDOUT_OUTPUT" | awk -v RS="[ \n]" '{print}')"
			pods_and_containers_array=("${pods_array[@]/%/${POD_CONTAINER_SEPARATOR}${container}}")
			CONTAINERS_ARG_LIST="${ns}${NAMESPACE_PODS_SEPARATOR}"
			pods_list=$(printf "%s," "${pods_and_containers_array[@]}")
			pods_list=${pods_list%${PODS_SEPARATOR}}
			CONTAINERS_ARG_LIST+="${pods_list}"
		fi
	fi
}

# expand_empty_namespaces_in_containers_arg - expands empty namespaces -  ""<ns>:;" , defiled in "--containers" arg
# @params: arg1: string-value of "--containers" arg
# @return: CONTAINERS_ARG_LIST_WITH_EXPANDED_NANESPACES - "--containers" arg with expanded empty namespaces.
#         For example, value  "...;ns1:;..." of "--containers" arg will be converted to "...;ns1:pod1,pod2,pod3;..."
expand_empty_namespaces_in_containers_arg() {
	local received_containers_arg_list=("$@") # arg1 - List of namespaces-pods-containers name ("--containers" arg value)

	IFS="$NAMESPACES_SEPARATOR" read -ra received_pods_arg_array <<<"$received_containers_arg_list"

	CONTAINERS_ARG_LIST_WITH_EXPANDED_NANESPACES=""
	for ns_list in ${received_pods_arg_array[@]}; do
		IFS="$NAMESPACE_PODS_SEPARATOR" read -r ns pod_container_list <<<"$ns_list"
		if [[ -z "$ns" ]]; then
			ns=$NAMESPACE
		fi
		if [[ ! -z "$pod_container_list" ]]; then
			CONTAINERS_ARG_LIST_WITH_EXPANDED_NANESPACES+=$"${ns}${NAMESPACE_PODS_SEPARATOR}${pod_container_list}${NAMESPACES_SEPARATOR}"
		else
			get_all_pods_per_ns_and_container "$ns" ""
			if [[ ! -z "$CONTAINERS_ARG_LIST" ]]; then
				CONTAINERS_ARG_LIST_WITH_EXPANDED_NANESPACES+="${CONTAINERS_ARG_LIST[@]}${NAMESPACES_SEPARATOR}"
			fi
		fi
	done
}

# collect_all_containers_define_by_cmd_args - parses "--containers" arg, considering values of "--namespace" and "--container" args.
#    The format of the "--containers" argument is as follows:
#    "[<namespace>]:[[<pod-name1>]#[<container-name1>],[<pod-name1>]#[<container-name2>]...];..."
#    Special cases:
#    1. The default namespace or the value of the "--namesapce" argument (if defined) will be used for a module with an empty namespace.
#        For example, '--namespace radware --containers "...;:[<pods-contaters list>];..."' is the same as' --containers "...;radware:[<pods-contaters list>];..."'
#    2. If the container name is omitted, all pod containers will be processed.
#        For example, '--containers "radware:pod1,pod2#cont2"' is the same as' --containers "radware:pod1#cont1,pod1#cont2,pod2#cont2"', where pod1 has 2 contaners: cont1 and cont2.
#    3. If the pod-name is omitted, all pods containing the given container in the given namespace will be processed.
#        For example, '--containers "radware:pod1#cont1,#cont2"' is the same as' --containers "radware:pod1#cont1,pod2#cont2,pod3#cont2"', where pod2 and pod3 have contaner cont2
#    4. If the "--containers" arg is omitted, "--namespase" arg( of default namespace, not if defined) and "--container" arg  will be processed.
#        Two examples:
#         (1) '--namespace radware --container cont1' is the same as ' --containers "radware:#cont1"'
#         (2) '--namespace radware' is the same as ' --containers "radware:"'
# @params: arg1: namespace
#           arg2: container name or empty
#           arg3: string-value of "--containers" arg
# @return: CONTAINERS_ARGUMENT_ARRAY - the parsed "--containers" arg as an array in the following format:
#    ("<namespace>&<pod-name1>&<container-name1>" "<namespace>&<pod-name1>&<container-name2>" ...)
#    - according to all dependencies between namespaces, pods and containers defined in the "--containers" arg.
collect_all_containers_define_by_cmd_args() {
	local dflt_ns=$1        # arg1 - Namespace ("--namespace" arg value)
	local dflt_container=$2 # arg2 - Conaitner name ("--container" arg value)
	shift
	shift
	local received_containers_arg_list=("$@") # arg3 - List of namespaces-pods-containers name ("--containers" arg value)

	if [[ -z "$received_containers_arg_list" ]]; then
		print_msg "\n'--containers' arg is not defined.\nCreating '--containers' arg from '--namespace' and '--container' args ..."
		get_all_pods_per_ns_and_container "$dflt_ns" "$dflt_container"
		received_containers_arg_list="${CONTAINERS_ARG_LIST[@]}"
	else
		print_msg "\nExpanding empty namespaces of the '--containers' arg ..."
		expand_empty_namespaces_in_containers_arg ${received_containers_arg_list[@]}
		received_containers_arg_list="${CONTAINERS_ARG_LIST_WITH_EXPANDED_NANESPACES[@]}"
	fi

	print_msg "\nProcessing the '--containers' arg ..."
	IFS="$NAMESPACES_SEPARATOR" read -ra received_pods_arg_array <<<"$received_containers_arg_list"

	local parsed_containers_arg_array=()
	for ns_list in ${received_pods_arg_array[@]}; do
		IFS="$NAMESPACE_PODS_SEPARATOR" read -r ns pod_container_list <<<"$ns_list"
		IFS="$PODS_SEPARATOR" read -ra pod_container_array <<<"$pod_container_list"
		if [[ -z "$ns" ]]; then
			ns=$dflt_ns
		fi
		for pod_cont in "${pod_container_array[@]}"; do
			IFS="$POD_CONTAINER_SEPARATOR" read -r pod container <<<"$pod_cont"
			if [[ -z "$pod" ]]; then
				print_msg "\nCollecting all pods from namespace '$ns' having container '$container'..."
				cmd="kubectl get pods -n $ns -o=jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{range .spec.containers[*]}{.name}{\"\\t\"}{end}{\"\\n\"}{end}' | grep $container | awk '{print \$1}'"
				handle_cmd $cmd
				if [[ $EXIT_CODE -ne 0 ]]; then
					continue
				fi
				if [ -z "$STDOUT_OUTPUT" ]; then
					print_error "Error: there is no pods containing container '$container' in namespace '$ns'"
				else
					readarray -t PODS <<<"$(echo "$STDOUT_OUTPUT" | awk -v RS="[ \n]" '{print}')"
					PODS_ARRAY=("${PODS[@]/#/${ns}${RESULT_SEPARATOR}}")
					PODS_ARRAY=("${PODS_ARRAY[@]/%/${RESULT_SEPARATOR}${container}}")
					parsed_containers_arg_array+=("${PODS_ARRAY[@]}")
				fi
			elif [[ -z "$container" ]]; then
				print_msg "\nCollecting all containers of the pod '$pod' from namespace '$ns' ..."
				cmd="kubectl get pod -n $ns $pod -o jsonpath='{.spec.containers[*].name}'"
				handle_cmd $cmd
				if [[ $EXIT_CODE -ne 0 ]]; then
					continue
				fi
				if [ -z "$STDOUT_OUTPUT" ]; then
					print_error "Error: there is no containers on the pod '$pod'  in namespace '$ns'"
				else
					readarray -t CONTAINERS <<<"$(echo "$STDOUT_OUTPUT" | awk -v RS="[ \n]" '{print}')"
					CONTAINERS_ARRAY=("${CONTAINERS[@]/#/${ns}${RESULT_SEPARATOR}${pod}${RESULT_SEPARATOR}}")
					parsed_containers_arg_array+=("${CONTAINERS_ARRAY[@]}")
				fi
			else
				print_msg "Making sure the Pod '$pod' from namespase '$ns' has '$container' container. -"
				cmd="kubectl get pod -n $ns $pod -o=jsonpath='{.spec.containers[?(@.name == \"$container\")]}'"
				handle_cmd $cmd
				if [[ $EXIT_CODE -ne 0 ]]; then
					continue
				fi
				if [ -z "$STDOUT_OUTPUT" ]; then
					print_error "Error: pod '$pod' from namespace '$ns' does not contain container '$container'"
				else
					parsed_containers_arg_array+=("${ns}${RESULT_SEPARATOR}${pod}${RESULT_SEPARATOR}${container}")
				fi
			fi
		done
	done

	CONTAINERS_ARGUMENT_ARRAY=("${parsed_containers_arg_array[@]}")
	if [[ -z "$CONTAINERS_ARGUMENT_ARRAY" ]]; then
		print_error "Error: No pods were found for the given cmd arguments."
	fi
}

# metrics_server_is_installed_and_running - checks if the metric-server is installed and running
# @return: 0/1 -  false/true
metrics_server_is_installed_and_running() {
	print_msg "Verifying the Metrics-Server is installed and running...."
	cmd="kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}'"
	handle_cmd "$cmd"
	if [[ $EXIT_CODE -eq 0 ]] && [[ $STDOUT_OUTPUT -eq "1" ]]; then
		return 1
	fi
	return 0
}

# metrics_server_is_installed - checks if the metric-server is installed
# @return: 0/1 -  false/true
metrics_server_is_installed() {
	print_msg "Verifying the Metrics-Server is installed...."
	cmd="kubectl get deployment metrics-server -n kube-system"
	handle_cmd "$cmd"
	if [[ $EXIT_CODE -eq 0 ]]; then
		return 1
	fi
	return 0
}

metrics_server_delete() {
	if [ "$METRICS_SERVER_DELETE" = false ]; then
		return 0
	fi
	print_msg "Removing the Metrics-Server..."
	cmd="kubectl delete -f $METRICS_SERVER_CONFIG_USED"
	handle_cmd "$cmd"
}

# metrics_server_install_remote - installs the remote metric-server
# @return: 0/1 -  false/true
metrics_server_install_remote() {
	cmd="kubectl apply -f $METRICS_SERVER_CONFIG_REMOTE"
	handle_cmd_and_output "" "$cmd"
	if [[ $EXIT_CODE -ne 0 ]]; then
		return 0
	fi

	metrics_server_is_installed
	if [[ $? -eq 0 ]]; then
		return 0
	fi

	cmd="kubectl patch -n kube-system deployment metrics-server --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'"
	handle_cmd_and_output "" "$cmd"
	if [[ $EXIT_CODE -ne 0 ]]; then
		return 0
	fi

	return 1
}

# metrics_server_install_local - installs the local metric-server
# @return: 0/1 -  false/true
metrics_server_install_local() {
	cmd="kubectl apply -f $METRICS_SERVER_CONFIG_LOCAL"
	handle_cmd_and_output "" "$cmd"
	if [[ $EXIT_CODE -ne 0 ]]; then
		return 0
	fi

	metrics_server_is_installed
	if [[ $? -eq 0 ]]; then
		return 0
	fi

	cmd="kubectl patch -n kube-system deployment metrics-server --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'"
	handle_cmd_and_output "" "$cmd"
	if [[ $EXIT_CODE -ne 0 ]]; then
		return 0
	fi
}

# metrics_server_wait_until_ready - waiting for the Metrics-Server to be ready
# @return: 0/1 -  false/true
metrics_server_wait_until_ready() {
	metrics_server_is_installed_and_running
	while [[ $? -eq 0 ]]; do
		if ((iteration >= max_iterations)); then
			print_error "Metrics-Server installation timed out after $((max_iterations * 5)) seconds."
			return 0
		fi

		((iteration++))
		print_msg "Waiting for Metrics-Server to be ready (Attempt $iteration/$max_iterations)..."
		sleep 5

		metrics_server_is_installed_and_running
	done

	return 1
}

# metrics_server_install - installs the metric-server and verifies it
# @return: 0/1 -  false/true
metrics_server_install() {
	local max_iterations=20
	local iteration=0
	local use_local_metrics_server_config=true

	print_msg "Installing Metrics-Server ..."
	print_msg "Applying Metrics-Server using remote source..."
	METRICS_SERVER_CONFIG_USED=$METRICS_SERVER_CONFIG_REMOTE

	metrics_server_install_remote
	if [[ $? -eq 0 ]]; then
		metrics_server_delete
		METRICS_SERVER_CONFIG_USED=$METRICS_SERVER_CONFIG_LOCAL
		print_msg "Failed to apply Metrics-Server from a remote source. Applying from a local source...."
		metrics_server_install_local
		if [[ $? -eq 0 ]]; then
			print_error "Error: Failed to apply Metrics-Server"
			return 0
		fi
	fi

	print_msg "Waiting for the Metrics-Server to be ready..."

	metrics_server_wait_until_ready
	if [[ $? -eq 0 ]]; then
		return 0
	fi

	print_msg "Metrics Server is installed and running."
	return 1
}

# metrics_server_install_and_validate - checks if the metric-server is installed and running, and installs it if not
# @return: 0/1 -  false/true
metrics_server_install_and_validate() {
	# ZZZ return 0 # !!! TODO: remove this to enable MEMORY and CPU util collection.
	metrics_server_is_installed_and_running
	if [[ $? -eq 1 ]]; then
		print_msg "Metrics Server is already installed and running."
		return 1
	fi
	METRICS_SERVER_DELETE=true
	print_msg "Metrics Server is not installed."
	metrics_server_install
	return $?
}

# validate release version
validate_release() {
  local cluster_full_version
  cluster_full_version="$(helm ls -n "$NAMESPACE" --selector "name==$HELM_RELEASE_NAME" --no-headers | awk '{print $NF}')"
  major="$(echo "$cluster_full_version" | cut -d'.' -f1)"
  minor="$(echo "$cluster_full_version" | cut -d'.' -f2)"
  local cluster_version="$major.$minor"

  if [ -z "$cluster_full_version" ]; then
      print_error "\nCould not verify cluster version for namespace '$NAMESPACE' and release name '${HELM_RELEASE_NAME}'."
      print_msg "NOTE: Either namespace or helm release name cannot be resolved. Please check that --namespace and --release parameters are correct. Script will collect data anyway but may contain inconsistencies due to version incompatibility\n"
      return
  fi

  if [ "$cluster_version" != "$TOOL_VERSION" ]; then
  	print_error "Error: Your KWAAP version: ${cluster_version} is not supported by techdata tool version: ${TOOL_VERSION}"
  	print_error "You can download version ${cluster_version} from here https://github.com/Radware/kWAAP_Tools/releases/${cluster_full_version}"
    exit 1
  fi
}