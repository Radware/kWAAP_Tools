#! /bin/bash

ERRORS=()
TMP_ERROR=""
OBJECT=""
OBJECT_DELIMITER="---"

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

function recover_backup {
    #Get object name, ns and kind
    BACKUP_NAME=$(echo "$OBJECT" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.name}')
    BACKUP_NS=$(echo "$OBJECT" | kubectl apply -f - --dry-run=client -o jsonpath='{.metadata.namespace}') 
    BACKUP_KIND=$(echo "$OBJECT" | kubectl apply -f - --dry-run=client -o jsonpath='{.kind}') 

    #Verify object NS exists, if not - create it
    if [[ -z $(kubectl get namespace $BACKUP_NS --ignore-not-found ) ]]; then 
        kubectl create namespace $BACKUP_NS
    fi

    #Check if resource already exists
    RESOURCE=$(kubectl get $BACKUP_KIND --ignore-not-found --namespace $BACKUP_NS $BACKUP_NAME --no-headers)


    if [[ -n $RESOURCE ]]; then
        #Resource exists, use 'replace' to restore the object
        TMP_ERROR=$(echo "$OBJECT" | kubectl replace -f - 2>&1 > /dev/null | sed "/patched automatically/d")
    else
        #Resource doesn't exists, use 'apply' to restore the object
        TMP_ERROR=$(echo "$OBJECT" | kubectl apply -f - 2>&1 > /dev/null | sed "/patched automatically/d")
    fi

    if [[ $TMP_ERROR != "" ]]; then
        ERRORS+=("$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND failed to apply: $TMP_ERROR")
        TMP_ERROR=""
    else
        echo "$BACKUP_NAME in namespace $BACKUP_NS type $BACKUP_KIND applied successfully"
    fi
}

#In case input containes more than one objcet (Delimiter-separated)
#Iterate over each object performing the "recover_backup" function
#Otherwise perform the operation on the entire input
if [[ "$INPUT" == *"$OBJECT_DELIMITER"* ]]; then
     for item in $INPUT; do
        if [[ $item == "---" ]]; then 
            if [[ $OBJECT != $OBJECT_DELIMITER$IFS ]]; then
                recover_backup
            fi 
            OBJECT=""
        fi
        OBJECT+="$item$IFS"
    done
else
    OBJECT=$INPUT
    recover_backup
fi

if [[ ${#ERRORS[@]} != 0 ]]; then
    for err in "${ERRORS[@]}"; do
        echo -e "\n$err\n"
    done
    exit 1
else
    echo -e "\nRecovery finished successfully\n"
    exit 0
fi

IFS=$OLD_IFS