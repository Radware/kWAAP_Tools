#! /bin/bash

# Help\Usage message
usage() {
  echo '''
  This script will backup or restore waas configuration objects
  '''
  echo "Usage:"
  echo "    $(basename "$0") [options]"
  echo "Backup:"
  echo "    $(basename "$0") --backup"
  echo "Restore:"
  echo "    $(basename "$0") -r -n waas_backup.tgz"
  echo '''
Options:
    -h|--help               Print usage
    -b|--backup             Generate backup archive
    -r|--restore            Perform restore operation, use [-i or --input] to provide input archive 
    -n|--name               Change default input\output filename
  '''
}

invalid() {
  echo "[ERROR] Unrecognized argument: $1" >&2
  usage
  exit 1
}
# Parse options
END_OF_OPT=
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "${END_OF_OPT}${1}" in
    -h|--help)      usage; exit 0 ;;
    -n|--name)      shift;BACKUP_TAR="$1";;
    -b|--backup)    BACKUP=1;;
    -r|--restore)   RESTORE=1;;
    --)             END_OF_OPT=1 ;;
    *)              POSITIONAL+=("$1") ;;
  esac
  shift
done

EXTRACT_DIR="tmp_restore_dir"
AWK_DIR="tmp_awk_dir"
ERRORS=()
TMP_ERROR=""

#List of CRDs to backup
CRD_TYPES=('apispecs' 'decodingbehaviors' 'mappings' 'openapis' 'profiles' 'segments' 'sourcegroups' 'unblockrequests')

#List of ConfigMaps to backup
CONFIG_MAPS_NAMES=('waas-activity-tracker-config' 'waas-ca-config' 'waas-custom-rules-configmap' 'waas-elasticsearch-ilm-options-config' 'waas-elasticsearch-jvm-options-config' 'waas-identity-auth-config' 'waas-licenses-configmap' 'waas-logstash-jvm-options-config' 'waas-logstash-pipeline-config' 'waas-logstash-templates-config' 'waas-prometheus-config' 'waas-redis-init-config' 'waas-request-data-configmap')

#Kubectl patch parameters for removing fields
PATCH_STRING="{\"op\": \"remove\", \"path\": \"/metadata/uid\"}, \
{\"op\": \"remove\", \"path\": \"/metadata/resourceVersion\"}, \
{\"op\": \"remove\", \"path\": \"/metadata/selfLink\"}, \
{\"op\": \"remove\", \"path\": \"/metadata/creationTimestamp\"}"

#Make sure ConfigMap output file is empty
function cm_backup {
    cm_backup_data=""
    for CM_NAME in "${CONFIG_MAPS_NAMES[@]}"; do
        for CM in $(kubectl get cm --all-namespaces --ignore-not-found --field-selector metadata.name=$CM_NAME -o jsonpath='{range .items[*]}{@.metadata.name}{";;"}{@.metadata.namespace}{"\n"}{end}'); do
            #Extract CRD name - the string up to ";;"
            NAME=${CM%;;*}
            
            #Extract CRD name - the string after ";;"
            NS=${CM#*;;}
            
            #Get full configmap definition 
            OBJ="$(kubectl get cm --ignore-not-found --namespace $NS $NAME -o json)"
        
            #Check if CRD has "status" field
            LAST_CONFIG=$(kubectl get cm --ignore-not-found --namespace $NS $NAME -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}')
            TMP_PATCH_STRING=$PATCH_STRING
            if [[ ! -z $LAST_CONFIG ]]; then
                #In case last-applied-configuration annotation is found - add it to removal
                TMP_PATCH_STRING="$TMP_PATCH_STRING, {\"op\": \"replace\", \"path\": \"/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration\", \"value\": \"\"}"
            fi
        
            #Remove fields based on the parameter value above
            cm_backup_data+="$(echo "$OBJ" | kubectl patch -f - --dry-run=client --type=json --patch="[$TMP_PATCH_STRING]" -o yaml)"

            #Add delimiter to output file
            cm_backup_data+="\\n---\\n"
        done
    done
    # in case configmaps were collected write to file
    if [[ ! -z $cm_backup_data ]]; then
        echo -e "$cm_backup_data" > cm_backup.yml
        CLEANUP_LIST+=('cm_backup.yml')
    fi
}

function crd_backup {
    for CRD_TYPE in "${CRD_TYPES[@]}"; do
        crd_backup_data=""
        #get all CRD names and namespaces, delimited by ";;"
        for CRD in $(kubectl get $CRD_TYPE --all-namespaces --ignore-not-found -o jsonpath='{range .items[*]}{@.metadata.name}{";;"}{@.metadata.namespace}{"\n"}{end}'); do
            #Extract CRD name - the string up to ";;"
            NAME=${CRD%;;*}
            
            #Extract CRD namespace - the string after ";;"
            NS=${CRD#*;;}
            
            #Get full CRD definition 
            OBJ="$(kubectl get $CRD_TYPE --ignore-not-found --namespace $NS $NAME -o json)"
            
            #Check if CRD has "status" or "metadata/annotations/kubectl.kubernetes.io\last-applied-configuration" fields
            STATUS=$(kubectl get $CRD_TYPE --ignore-not-found --namespace $NS $NAME -o jsonpath='{.status}')
            LAST_APPLIED_ANNO=$(kubectl get $CRD_TYPE --ignore-not-found --namespace $NS $NAME -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}')

            TMP_PATCH_STRING=$PATCH_STRING
            
            if [[ ! -z $STATUS ]]; then
                #In case status field found - add removal of "status" field
                TMP_PATCH_STRING="$TMP_PATCH_STRING, {\"op\": \"remove\", \"path\": \"/status\"}"
            fi
            if [[ ! -z $LAST_APPLIED_ANNO ]]; then
                #In case last-applied-configuration annotation is found - add it to removal
                TMP_PATCH_STRING="$TMP_PATCH_STRING, {\"op\": \"replace\", \"path\": \"/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration\", \"value\": \"\"}"
            fi
            crd_backup_data+="$(echo "$OBJ" | kubectl patch -f - --dry-run=client --type=json --patch="[$TMP_PATCH_STRING]" -o yaml)"
            
            #Add delimiter to output file
            crd_backup_data+="\\n---\\n"
        done
        if [[ ! -z $crd_backup_data ]]; then
            echo -e "$crd_backup_data" > "${CRD_TYPE}_backup.yml"
            CLEANUP_LIST+=("${CRD_TYPE}_backup.yml")
        fi
    done
}

function recover_backup {
	mkdir ./$EXTRACT_DIR
	tar -xzf $BACKUP_TAR -C $EXTRACT_DIR

	FILES=($(ls $EXTRACT_DIR))
	mkdir ./$EXTRACT_DIR/$AWK_DIR

	#Iterate over the backup files
	for backup_file in "${FILES[@]}"
	do
		#Get the kind of resource from the backup file
		BACKUP_KIND=$(echo $backup_file | grep -Po '.+(?=_backup\.yml)')

		#Split the backup file into a number of files each containing a single resource - split by the delimiter \n---\n
		#Created files are name file1.yml, file2.yml ...
		cd $EXTRACT_DIR/$AWK_DIR
		awk '{print $0 > "file" NR ".yml"}' RS="\n---\n" ../$backup_file
		cd ../..

		#Iterate over the single resource files of the same type
		TYPE_FILES=($(ls $EXTRACT_DIR/$AWK_DIR))
		for file in "${TYPE_FILES[@]}"
		do
			FILE_PATH=$EXTRACT_DIR/$AWK_DIR/$file

			#The last file created by the awk command will be empty beacause the original backup files all end with the delimiter \n---\n
			#So we want to delete it and move on - there is nothing to config here
			if [[ -z $FILE_PATH ]] || [[ $(cat $FILE_PATH) == "" ]]; then
				rm $FILE_PATH
				continue
			fi

			#Get the resource name from the backup
			BACKUP_NAME=$(sed -n "/^metadata:$/ {
					:loop
					n
					/^ */! {
						b break
					}
					/^ *name:/ {
						P
						b break
					}
					b loop
					:break
				}" $FILE_PATH | grep -Po "name: \K.*")

			#Get the resource namespace from the backup
			BACKUP_NS=$(sed -n "/^metadata:$/ {
					:loop
					n
					/^ */! {
						b break
					}
					/^ *namespace:/ {
						P
						b break
					}
					b loop
					:break
				}" $FILE_PATH | grep -Po "namespace: \K.*")

			#If such a resource already exist - get the resource version
			RESOURCE=$(kubectl get $BACKUP_KIND --ignore-not-found --namespace $BACKUP_NS $BACKUP_NAME --no-headers)

			#If the element exists - add the current resource version to the backup yml so the apply will pass
			if [[ -n $RESOURCE ]]; then
			    TMP_ERROR=$(kubectl replace  -f $FILE_PATH 2>&1 > /dev/null | sed "/patched automatically/d")
			else
                #Get stderr from apply, while ignoring any line containing "patched automatically" message
                TMP_ERROR=$(kubectl apply  -f $FILE_PATH 2>&1 > /dev/null | sed "/patched automatically/d")
            fi

			if [[ $TMP_ERROR != "" ]];
			then
				ERRORS+=("$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND failed to apply: $TMP_ERROR")
				TMP_ERROR=""
			else
				echo "$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND applied successfully"
			fi

			rm $FILE_PATH
		done
	done

	rm -rf $EXTRACT_DIR

	if [[ ${#ERRORS[@]} != 0 ]];
	then
		for err in "${ERRORS[@]}"
		do
			echo -e "\n$err\n"
		done
		exit 1
	else
		echo -e "\nRecovery finished successfully\n"
		exit 0
	fi
}

if [[ ! -z $RESTORE ]]; then
    #Make sure input file was provided
    if [[ -z $BACKUP_TAR ]]; then
        echo "[ERROR] no backup archive provided!"
        echo "use [-n or --name] to provide input archive"
        exit 2
    fi
    #Run recover function 
    recover_backup
fi

if [[ ! -z $BACKUP ]]; then
    #Run Backup functions
    CLEANUP_LIST=()
    cm_backup
    crd_backup

    #In case filename was provided use it, otherwise set default output filename
    if [[ -z $BACKUP_TAR ]]; then
        BACKUP_TAR="waas_backup_$(date "+%d-%m-%y").tgz"
    fi

    #Archive all backup YAML files 
    tar -czf $BACKUP_TAR *.yml

    #If archive was successful - print output filename and cleanup
    if [ $? -eq 0 ]; then
        echo "Backup completed successfully, result filename is $BACKUP_TAR"
	    for backup_file in "${CLEANUP_LIST[@]}"; do
            rm $backup_file
        done
    fi
fi
