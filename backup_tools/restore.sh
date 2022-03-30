#! /bin/bash

ERRORS=()
TMP_ERROR=""

OLD_IFS="$IFS"
IFS=$'\n'

if [ -n "$1" ]; then
    if [[ -f "$1" ]]; then 
        INPUT="$(cat $1)"
    else
        INPUT="$1"
    fi
else
    INPUT="$(cat)"
fi

i=0
INPUT_ARRAY=()
for item in $INPUT; do
    if [[ $item == "---" ]]; then 
        i+=1
        continue
    fi
    INPUT_ARRAY[$i]+="$item\\n"
done

function recover_backup {
	#Iterate over the backup files
	for object in "${INPUT_ARRAY[@]}"; do
        # echo -e "$object"
        BACKUP_NAME=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.name}')
        BACKUP_NS=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.namespace}') 
        BACKUP_KIND=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.kind}') 
        
        if [[ -z $(kubectl get namespace $BACKUP_NS --ignore-not-found ) ]]; then 
            kubectl create namespace $BACKUP_NS
        fi


        #If such a resource already exist - get the resource version
        RESOURCE=$(kubectl get $BACKUP_KIND --ignore-not-found --namespace $BACKUP_NS $BACKUP_NAME --no-headers)
        #If the element exists - add the current resource version to the backup yml so the apply will pass

        if [[ -n $RESOURCE ]]; then
            TMP_ERROR=$(echo -e "$object" | kubectl replace -f - 2>&1 > /dev/null | sed "/patched automatically/d")
        else
            #Get stderr from apply, while ignoring any line containing "patched automatically" message
            TMP_ERROR=$(echo -e "$object" | kubectl apply -f - 2>&1 > /dev/null | sed "/patched automatically/d")
        fi

        if [[ $TMP_ERROR != "" ]]; then
            ERRORS+=("$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND failed to apply: $TMP_ERROR")
            TMP_ERROR=""
        else
            echo "$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND applied successfully"
        fi
	done

	if [[ ${#ERRORS[@]} != 0 ]]; then
		for err in "${ERRORS[@]}"; do
			echo -e "\n$err\n"
		done
		exit 1
	else
		echo -e "\nRecovery finished successfully\n"
		exit 0
	fi
}

IFS=$OLD_IFS
recover_backup