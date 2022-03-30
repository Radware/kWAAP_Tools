#! /bin/bash

ERRORS=()
TMP_ERROR=""

#Backup original IFS (word seperator)
OLD_IFS="$IFS"
IFS=$'\n'

#Read input
if [ -n "$1" ]; then
    #Script wass triggered with argument, check if there is a file by that name
    if [[ -f "$1" ]]; then 
        # Found a file - read content into the INPUT param
        INPUT="$(cat $1)"
    else
        #No such file, read the argument as the actual input
        INPUT="$1"
    fi
else
    # No arguments provided, read STDIO
    INPUT="$(cat)"
fi

#Split the input to an array, each k8s object is an element
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
	#Iterate over the backup objects
	for object in "${INPUT_ARRAY[@]}"; do
        #Get object name, ns and kind
        BACKUP_NAME=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.name}')
        BACKUP_NS=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.namespace}') 
        BACKUP_KIND=$(echo -e "$object" | kubectl apply -f - --dry-run=client -o jsonpath='{.kind}') 
        
        #Verify object NS exists, if not - create it
        if [[ -z $(kubectl get namespace $BACKUP_NS --ignore-not-found ) ]]; then 
            kubectl create namespace $BACKUP_NS
        fi

        #Check if resource already exists
        RESOURCE=$(kubectl get $BACKUP_KIND --ignore-not-found --namespace $BACKUP_NS $BACKUP_NAME --no-headers)

        if [[ -n $RESOURCE ]]; then
            #Resource exists, use 'replace' to restore the object
            TMP_ERROR=$(echo -e "$object" | kubectl replace -f - 2>&1 > /dev/null | sed "/patched automatically/d")
        else
            #Resource doesn't exists, use 'apply' to restore the object
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