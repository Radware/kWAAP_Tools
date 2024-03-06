#!/bin/bash

source tools_utils.sh

# Values of cmd arguments defining data collection options:
JSON_FILE_NAME=""
NAMESPACE=$DEFAULT_NAMESPACE
CONTAINER_NAME=""
CONTAINERS_ARGUMENT_LIST=()
COLLECT_DESCRIBES=true # - currently always collected
DESCRIBES_FILE_PREFIX="logs"
COLLECT_CONFIG_DUMP=false
CONFIG_DUMP_FILE_PREFIX="config_dump"
COLLECT_SEC_EVENTS=false
SEC_EVENTS_FILENAME="security.log"
COLLECT_ACCEESS_LOGS=false
ACCEESS_LOGS_FILENAME="access.log"
COLLECT_REQUEST_DATA=false
REQUEST_DATA_FILENAME="request_data.log"
COLLECT_LOGS=false
LOGS_FILE_PREFIX="logs"
COLLECT_PREV_LOGS=false
PREV_LOGS_K8S_CMD_OPT="--previous"
ARCHIVE=false 

IS_CMD_LINE_ARGS_USED=false

# Enforcer conection params
LOCALHOST="127.0.0.1"
ENFORCER_CONTAINER_PORT=19000 
ENFORCER_CONT_NAME="enforcer"

print_help() {
  printf '\nKWAAP techdata config-dump script help.\n Flags:\n'
  printf '\t -n, --namespace \t\t The Namespace in which KWAAP is installed. Default: %s\n' "$DEFAULT_NAMESPACE"
  printf '\t -c, --containers \t\t The list of pods and containers per namespaces for which data will be collected.\n\tFormat:"ns1:pod1*cont1,pod2;ns2:;ns3:*cont2". Default: The list of ALL pods and containers defined by "--namespace" and "--container" args\n' 
  printf '\t -af, --args-file \t\t The filename of JSON file that is used in place of the "--containers" , and other data collection arguments.\n' 
  printf '\t -cd, --config-dump \t\t The boolean determines whether config-dump should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -se, --security-events \t\t The boolean determines whether security-events should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -al, --access-logs \t\t The boolean determines whether access-logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -rd, --requst-data \t\t The boolean determines whether requst-data should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n' 
  printf '\t -l, --logs \t\t The boolean determines whether logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n' 
  printf '\t -pl, --previous-logs \t\t The boolean determines whether previous logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n' 
  printf '\t -d, --dir \t\t The Directory in which containers techdata will be collected. Default: None\n' 
  printf '\t --container \t\t The name of the container for which data will be collected from all pods in a specified namespace, in the case where "--containers" is not defined. Default: all containers from all modules in the specified namespace.'
  printf '\t -h, --help \t\t Print help message and exit\n' 
}

display_usage() {
    print_msg 'Usage: $0 -n|--namespace <namespace_value> -c|--containers "ns1:pod1*cont1,pod2;ns2:;ns3:*cont2"'
}

while [[ "$1" =~ ^- ]]; do
	case $1 in
		-n | --namespace) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -n|--namespace parameter requires a namespace value."
				exit 1
			fi
			NAMESPACE="$2"
			shift
			shift
			;;
		--container) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The --container parameter requires a container name value."
				exit 1
			fi
			CONTAINER_NAME="$2"
			IS_CMD_LINE_ARGS_USED=true
			shift
			shift
			;;
		-c | --containers)
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -c|--containers parameter requires a list of values separated by commas."
				display_usage
				exit 1
			fi
			CONTAINERS_ARGUMENT_LIST="$2"
			IS_CMD_LINE_ARGS_USED=true
			shift
			shift
			;;
		-af | --args-from-file) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -pf | --args-from-file parameter requires a file-path value."
				exit 1
			fi
			JSON_FILE_NAME="$2"
			shift
			shift
			;;
		-cd | --config-dump)
			COLLECT_CONFIG_DUMP=true
			IS_CMD_LINE_ARGS_USED=true
			shift
			;;
		-se | --security-events)
			COLLECT_SEC_EVENTS=true
			IS_CMD_LINE_ARGS_USED=true
			shift
			;;
		-l | --logs)
			COLLECT_LOGS=true
			IS_CMD_LINE_ARGS_USED=true
			shift
			;;
		-pl | --previous-logs)
			COLLECT_PREV_LOGS=true
			IS_CMD_LINE_ARGS_USED=true
			shift
			;;
		-d | --dir) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -d|--dir parameter requires a directory value."
				exit 1
			fi
			OUTPUT_REDIR_NAME="$2"
			shift
			shift
			;;
		-h | --help)
			##help scenario.
			print_help
			exit 1
			;;
		*)
			print_error "Error: Invalid option -$1"
			exit 1
			;;
	esac
done


if [ "$IS_CMD_LINE_ARGS_USED" = true ] && [ ! -z "$JSON_FILE_NAME" ]; then
	print_error "Error: if -af | --args-from-file is defined, the arguments - '-c|--container', '-p|--containers', '-cd|--config-dump', '-se|--security-events', '-l|--logs' and '-pl|--previous-logs' can be defined in '$JSON_FILE_NAME' only"
	exit 1
fi

if [ ! -z "$JSON_FILE_NAME" ]; then
	json_file_to_cmd_args "$JSON_FILE_NAME"
fi

if [ ! -z "$CONTAINER_NAME" ] && [ ! -z "$CONTAINERS_ARGUMENT_LIST" ]; then
	print_error "Error: only one of "--containers" and "--container" can be defined"
	exit 1
fi

if [[ (! -z "$CONTAINER_NAME" || ! -z "$CONTAINERS_ARGUMENT_LIST") && "$COLLECT_CONFIG_DUMP" = false && "$COLLECT_SEC_EVENTS" = false && "$COLLECT_LOGS" = false && "$COLLECT_PREV_LOGS" = false ]]; then
	print_msg "\nNote that none of the options for collecting data from the defined containers are specified!\nThe following parameters determine the data that can be collected from the specified containers: '-cd', '-se', '-al', '-l' and '-pl' "
	exit 0
fi

config_dump() {
	local ns=$1 # arg1 - Namespace
	local pod=$2 # arg2 - Pod name
	
	print_msg "\nGetting CONFIG-DUMP from namespace:'$ns', pod:'$pod', container:'$ENFORCER_CONT_NAME'. -"
	cmd="kubectl exec $pod -n $ns -c $ENFORCER_CONT_NAME -- wget -q -O - $LOCALHOST:$ENFORCER_CONTAINER_PORT/config_dump"
	handle_cmd_and_output "${CONFIG_DUMP_FILE_PREFIX}_$pod" "$cmd"
}

get_enforcer_log_stuff(){
	local ns=$1 # arg1 - Namespace
	local pod=$2 # arg2 - Pod name
	local filename=$3 # arg3 - log file-name, that placed in "log/" dir on enfotcer container
	local file_prefix="${filename%.*}"
	
	print_msg "\nGetting '$filename' from namespace:'$ns', pod:'$pod', container:'$ENFORCER_CONT_NAME'. -"
	if [ -d "$OUTPUT_REDIR_NAME" ]; then
		cmd="kubectl cp $ns/$pod:logs/${filename} ${OUTPUT_REDIR_NAME}/"${file_prefix}_$pod" -c $ENFORCER_CONT_NAME"
	else
		cmd="kubectl exec $pod -n $ns -c $ENFORCER_CONT_NAME -- cat logs/${filename}"
	fi
	handle_cmd_and_output "${file_prefix}_$pod" "$cmd"
}

security_events() {
	get_enforcer_log_stuff "$1" "$2" "$SEC_EVENTS_FILENAME"
}

access_logs() {
	get_enforcer_log_stuff "$1" "$2" "$ACCEESS_LOGS_FILENAME"
}

request_data() {
	get_enforcer_log_stuff "$1" "$2" "$REQUEST_DATA_FILENAME"
}

logs() {
	local ns=$1 # arg1 - Namespace
	local pod=$2 # arg2 - Pod name
	local container=$3 # arg3 - Container name
	local prev=$4 # arg4 - "kubectl logs" cmd flag to print the container's previous logs
	
	print_msg "\nGetting LOGS${prev^^} from namespace:'$ns', pod:'$pod', container:'$container'. -"
	cmd="kubectl logs $pod -n $ns -c $container $prev"
	handle_cmd_and_output "${LOGS_FILE_PREFIX}${prev}_$pod" "$cmd"
}

collect_containers_techdata() {
	local parsed_containers_arg_array=("$@")
	
	for item in ${parsed_containers_arg_array[@]}; do	
		IFS='&' read -r ns pod container <<< "$item"
		if [ "$container" == "$ENFORCER_CONT_NAME" ]; then
			if [ "$COLLECT_CONFIG_DUMP" = true ]; then
				config_dump "$ns" "$pod"
			fi
			if [ "$COLLECT_SEC_EVENTS" = true ]; then
				security_events "$ns" "$pod"
			fi
			if [ "$COLLECT_ACCEESS_LOGS" = true ]; then
				access_logs "$ns" "$pod"
			fi
			if [ "$COLLECT_REQUEST_DATA" = true ]; then
				request_data "$ns" "$pod"
			fi
		fi
		
		if [ "$COLLECT_LOGS" = true ]; then
			logs "$ns" "$pod" "$container" 
		fi
		if [ "$COLLECT_PREV_LOGS" = true ]; then
			logs "$ns" "$pod" "$container" "$PREV_LOGS_K8S_CMD_OPT"
		fi
	done
}

## actual run

set_new_output_dir_and_stdout_stderr_files

collect_all_containers_define_by_cmd_args "$NAMESPACE" "$CONTAINER_NAME" "${CONTAINERS_ARGUMENT_LIST[@]}"
# echo -e "\n\nPARSED NAMESPACES/PODS/CONATINERS list:\n\t${CONTAINERS_ARGUMENT_ARRAY[@]}\n\n"

collect_containers_techdata ${CONTAINERS_ARGUMENT_ARRAY[@]}


