#! /bin/bash

# /*
#  * ******************************************************************************
#  *  * Copyright © 2019-2022, Radware Ltd., all rights reserved.
#  *  * The programs and information contained herein are licensed only and not sold.
#  *  * The applicable license terms are posted at https://www.radware.com/documents/eula/ and they are also available directly from Radware Ltd.
#  *  *****************************************************************************
#  */



TDATA_PARAMS=""
COLLECT_DATA_PARAMS=""
BKP_PARAMS=""
VERSION="1.17.0"
ARCHIVE=false

function print_help {
  printf '\nKWAAP techdata dump script help.\n Flags:\n'
  printf '\t -v, --version \t\t display current version.'
  printf '\t -n, --techdata \t\t Collect technical data infromation.'
  printf '\t -n, --backup \t\t Perform the backup operation.'
  printf '\t -n, --restore \t\t Perform the restore  operation.'
  printf '\t -n, --crd_only \t\t Skip Config Maps.'
  printf '\t -n, --cm_only \t\t Skip Custom Resources.'
  printf '\t -n, --all_cm \t\t Backup/Collect all kWAAP related ConfigMaps.'
  printf '\t -n, --raw_output \t\t Do not skip removal of dynamic fields (resourceVersion, uid, etc..).'
  printf '\t -n, --namespace \t\t The Namespace in which KWAAP is installed. default: %s\n' "$DEFAULT_NAMESPACE"
  printf '\t -r, --releasename \t\t The Helm release name with which KWAAP was installed. default: %s\n' "$DEFAULT_HELM_RELEASE_NAME"
  printf '\t -d, --dir \t\t The Directory in which pods techdata will be collected. Default: None\n' 
  printf '\t -a, --archive \t\t The boolean determines whether the techdata directory should be archived. Default: false\n'
  printf '\t -c, --containers \t\t The list of pods and containers per namespaces for which data will be collected.\n\tFormat:"ns1:pod1#cont1,pod2;ns2:;ns3:#cont2". Default: The list of ALL pods and containers defined by "--namespace" and "--container" args\n' 
  printf '\t -af, --args-file \t\t The filename of JSON file that is used in place of the "--containers" , and other data collection arguments.\n' 
  printf '\t -cd, --config-dump \t\t The boolean determines whether config-dump should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -lc, --latency-control \t\t The boolean determines whether latency-control should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -pm, --pmap \t\t The boolean determines whether pmap should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -se, --security-events \t\t The boolean determines whether security-events should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -al, --access-logs \t\t The boolean determines whether access-logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -rd, --request-data \t\t The boolean determines whether request-data should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n'
  printf '\t -l, --logs \t\t The boolean determines whether logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n' 
  printf '\t -pl, --previous-logs \t\t The boolean determines whether previous logs should be collected from the pods:containers defined by the "--namespace" and one of "--container" or "--containers" arguments. Default: false\n' 
  printf '\t --container \t\t The name of the container for which data will be collected from all pods in a specified namespace, in the case where "--containers" is not defined. Default: all containers from all modules in the specified namespace.'
  rintf '\t -mcu, --memory-cpu-usage \t\t Collect memory and CPU usage for nodes, pods, and containers.'
  printf '\t\t\t Note: the metrics-server will be installed if it has not been installed previously.'
  printf '\t -h, --help \t\t Print help message and exit\n' 
}
# execute single commands and exit
if [ "$1" == -v ] || [ "$1" == --version ] ; then
    printf "%s\n" $VERSION
    exit
fi


# commands for collecting data
source tools_utils.sh
while [[ $# -gt 0 ]]; do
	case $1 in
   --techdata|TECHDATA)
        TDATA=1
			  shift
   ;;
    --backup|BACKUP)
			BKP=1
            BKP_PARAMS+=" --backup"
			shift
			;;
    --restore|RESTORE)
                        if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
                                print_error "Error: --restore|RESTORE requires an additional parameter which is the file from which to restore from."
                                exit 1
                        fi
                        BKP_PARAMS+=" --restore $2"
			RSTR=1
                        shift
                        shift
                        ;;
    --crd_only|CRD_ONLY)
            BKP_PARAMS+=" --crd_only"
			TDATA_PARAMS+=" --crd_only"
			shift
			;;
    --cm_only|CM_ONLY)
            BKP_PARAMS+=" --cm_only"
			TDATA_PARAMS+=" --cm_only"
			shift
			;;
    --raw_output)
            BKP_PARAMS+=" --raw_output"
			TDATA_PARAMS+=" --raw_output"
			shift
			;;
    --all_config_maps)
            BKP_PARAMS+=" --all_config_maps"
			TDATA_PARAMS+=" --all_config_maps"
			shift
			;;
		-r|--releasename)
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -r|--releasename) parameter requires a releasename value."
				exit 1
			fi
			BKP_PARAMS+=" -r $2"
			TDATA_PARAMS+=" -r $2"
            shift
			shift
			;;
		-n | --namespace) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -n|--namespace parameter requires a namespace value."
				exit 1
			fi
			TDATA_PARAMS+=" -n $2"
			COLLECT_DATA_PARAMS+=" -n $2"
			BKP_PARAMS+=" -n $2"
			shift
			shift
			;;
		--container) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The --container parameter requires a container name value."
				exit 1
			fi
			COLLECT_DATA_PARAMS+=" --container $2"
			shift
			shift
			;;
		-c | --containers)
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -c|--containers parameter requires a list of values separated by commas."
				display_usage
				exit 1
			fi
			COLLECT_DATA_PARAMS+=" -c $2"
			shift
			shift
			;;
		-af | --args-from-file) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -pf | --args-from-file parameter requires a file-path value."
				exit 1
			fi
			COLLECT_DATA_PARAMS+=" -af $2"
			shift
			shift
			;;
	  -cd | --config-dump)
			COLLECT_DATA_PARAMS+=" -cd"
			shift
			;;
	  -pm | --pmap)
			COLLECT_DATA_PARAMS+=" -pm"
			shift
			;;
	  -lc | --latency-control)
			COLLECT_DATA_PARAMS+=" -lc"
			shift
			;;
		-se | --security-events)
			COLLECT_DATA_PARAMS+=" -se"
			shift
			;;
		-l | --logs)
			COLLECT_DATA_PARAMS+=" -l"
			shift
			;;
		-pl | --previous-logs)
			COLLECT_DATA_PARAMS+=" -pl"
			shift
			;;
		-d | --dir) 
			if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
				print_error "Error: The -d|--dir parameter requires a directory value."
				exit 1
			fi
			OUTPUT_REDIR_NAME="$2"
			COLLECT_DATA_PARAMS+=" -d $2"
			TDATA_PARAMS+=" -d $2"
			shift
			shift
			;;
		-a | --archive)
			ARCHIVE=true
			shift
			;;
		-mcu | --memory-cpu-usage)
			TDATA_PARAMS+=" --memory-cpu-usage"
			shift
			;;
		-h | --help)
			##help scenario.
			print_help
			exit 1
			;;
		*)
			echo "Error: Invalid option -$1"
			exit 1
			;;
	esac
done

if [ $((TDATA + BKP + RSTR)) -ne 1 ]; then
	print_error "Error: one and only one of ('--techdata|TECHDATA', '--backup|BACKUP', '--restore|RESTORE') flag-arguments can be set"
	exit 1
fi

if [ "$ARCHIVE" = true ] && [[ -z "$OUTPUT_REDIR_NAME" ]]; then
	print_error "Error: -a | --archive flag can't be set if directory is not defined"
	exit 1
fi

# set_output_dir_and_stdout_stderr_files - creates an output directory, if defined in "--dir" arg;
#     and two files:
#        1. <dirname>_stderr.txt - to copy the contents of STDERR.
#        2. <dirname>_stdout.txt - to redirect the contents of STDOUT.
set_output_dir_and_stdout_stderr_files(){
	if [[ -z "$OUTPUT_REDIR_NAME" ]]; then 
		return
	fi
		
	if [ -d "$OUTPUT_REDIR_NAME" ]; then
		rm -rf $OUTPUT_REDIR_NAME
	fi
	handle_cmd "mkdir $OUTPUT_REDIR_NAME"
	if [[ $EXIT_CODE -ne 0 ]]; then
		exit $EXIT_CODE
	fi
	
	STDOUT_FILE="${OUTPUT_REDIR_NAME}/${OUTPUT_REDIR_NAME}_stdout.txt"
	STDERR_FILE="${OUTPUT_REDIR_NAME}/${OUTPUT_REDIR_NAME}_stderr.txt"
	print_msg "\nSTDOUT will be coppied to the file '${STDOUT_FILE}'\n"
	print_msg "\nSTDERR will be coppied to the file '${STDERR_FILE}'\n"
}

# archive_techdata_dir - Create the archive using tar with the same name as the directory $OUTPUT_REDIR_NAME
archive_techdata_dir() {
	if [ "$ARCHIVE" = false ] || [ ! -d "$OUTPUT_REDIR_NAME" ]; then
		return
	fi
	
	# Extract the directory name from the path
	BASE_NAME=$(basename "$OUTPUT_REDIR_NAME")

	# Create the archive using tar with the same name as the directory
	handle_cmd "tar -czf ${BASE_NAME}.tar.gz $OUTPUT_REDIR_NAME"
	rm -rf $OUTPUT_REDIR_NAME
}

## actual run

if [[ -n "$TDATA" ]]; then 

	set_output_dir_and_stdout_stderr_files
	
	echo "Executing-script: './tools_collect_data.sh ${COLLECT_DATA_PARAMS[*]}'"
	./tools_collect_data.sh ${COLLECT_DATA_PARAMS[@]}
	EXIT_CODE=$?
	if [[ $EXIT_CODE -ne 0 ]]; then
		echo "ERROR: 'tools_collect_data.sh' failed with EXIT-CODE=$EXIT_CODE"
		exit $EXIT_CODE
	fi
	
	echo "Executing-script: './tools_techdata.sh ${TDATA_PARAMS[*]}'"
	./tools_techdata.sh ${TDATA_PARAMS[@]}
	EXIT_CODE=$?
	if [[ $EXIT_CODE -ne 0 ]]; then
		echo "ERROR: 'tools_techdata.sh' failed with EXIT-CODE=$EXIT_CODE"
		exit $EXIT_CODE
	fi
	
	archive_techdata_dir
fi

if [[ -n "$BKP" || -n "$RSTR" ]]; then 
	echo "Executing-script: './tools_bachup.sh ${BKP_PARAMS[*]}'" >&2
	./tools_backup.sh ${BKP_PARAMS[@]}
	EXIT_CODE=$?
	if [[ $EXIT_CODE -ne 0 ]]; then
		echo "ERROR: 'tools_bachup.sh' failed with EXIT-CODE=$EXIT_CODE"
		exit $EXIT_CODE
	fi
fi

