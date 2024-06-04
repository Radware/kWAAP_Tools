#! /bin/bash

# /*
#  * ******************************************************************************
#  *  * Copyright © 2019-2022, Radware Ltd., all rights reserved.
#  *  * The programs and information contained herein are licensed only and not sold.
#  *  * The applicable license terms are posted at https://www.radware.com/documents/eula/ and they are also available directly from Radware Ltd.
#  *  *****************************************************************************
#  */
set -f

#our defaults:
DEFAULT_NAMESPACE="kwaf"
DEFAULT_HELM_RELEASE_NAME="waas"

ERRORS=()
TMP_ERROR=""
OBJECT=""
OBJECT_DELIMITER="radwareRestoreDelimiter"

NAMESPACE=$DEFAULT_NAMESPACE
HELM_RELEASE_NAME=$DEFAULT_HELM_RELEASE_NAME
CTR=1

#Backup original IFS (word separator) 
OLD_IFS="$IFS"
#Define separator to NewLine only
IFS=$'\n'

function print_delimiter {
  printf '\n=================================================>\n\n'
}

function print_help {
  printf '\nKWAAP techdata dump script help.\n Flags:\n'
  printf '\t -n, --backup \t\t Perform the backup operation.'
  printf '\t -n, --restore \t\t Perform the restore  operation.'
  printf '\t -n, --crd_only \t\t Skip Config Maps.'
  printf '\t -n, --cm_only \t\t Skip Custom Resources.'
  printf '\t -n, --all_cm \t\t Backup all kWAAP related ConfigMaps.'
  printf '\t -n, --raw_output \t\t Do not skip removal of dynamic fields (resourceVersion, uid, etc..).'
  printf '\t -n, --namespace \t\t The Namespace in which KWAAP is installed. default: %s\n' "$DEFAULT_NAMESPACE"
  printf '\t -r, --releasename \t\t The Helm release name with which KWAAP was installed. default: %s\n' "$DEFAULT_HELM_RELEASE_NAME"
  printf '\t -h, --help \t\t Print help message and exit\n' 
}

while test $# -gt 0; do
    case "$1" in
        --backup|BACKUP) 
            BKP=1;;
        --restore|RESTORE) 
            RSTR=1;;
        --crd_only|CRD_ONLY) 
            CRD_ONLY=1;;
        --cm_only|CM_ONLY) 
            CM_ONLY=1;;
        --raw_output) 
            RAW=1;;
        --all_config_maps) 
            ALL_CM=1;;
        -n|--namespace)
            NAMESPACE="$2"  #Read the provided NS arg
            shift
            ;;
        -r|--releasename)
            HELM_RELEASE_NAME="$2"  #Read the provided releasename arg
            shift
            ;;
        -h|--help)
            ##help scenario.
            print_help
            exit 1
            ;;
        *)
            break
    esac
    shift
done


if [[ -n "$BKP" ]]; then
    #Get List of CRDs to backup (based on "waas.radware.com" group)
    CRD_TYPES=($(kubectl api-resources --api-group=waas.radware.com --output=name))

    #Kubectl patch parameters for removing fields
    PATCH_STRING=('{"op": "remove", "path": "/metadata/uid"}' '{"op": "remove", "path": "/metadata/resourceVersion"}' '{"op": "remove", "path": "/metadata/selfLink"}' '{"op": "remove", "path": "/metadata/creationTimestamp"}' '{"op": "replace", "path": "/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration", "value": ""}' '{"op": "remove", "path": "/status"}' '{"op": "remove", "path": "/metadata/generation"}')
    PATCH_FIELD=('.metadata.uid' '.metadata.resourceVersion' '.metadata.selfLink' '.metadata.creationTimestamp' '.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration' '.status' '.metadata.generation')
fi

#Revert to original separator
IFS=$OLD_IFS

function patch_and_echo {
    #If raw argument provided - echo object w\o performing field removal (in YAML format)
    if [[ $RAW == 1 ]]; then
        echo "$OBJ" | kubectl apply -f - --dry-run=client --output=yaml
        echo "---"
        return
    fi

    #Generate patch string based on object fields
    TMP_PATCH_STRING=""
    for (( i=0; i<${#PATCH_FIELD[@]}; i++)); do
        if [[ ! -z $($OBJ_STR --output jsonpath={${PATCH_FIELD[$i]}}) ]]; then 
            TMP_PATCH_STRING+="${PATCH_STRING[$i]}"
        fi
    done

    #Seprate patch fields with comma
    TMP_PATCH_STRING=${TMP_PATCH_STRING//\}\{/\}, \{}

    #Remove fields based on the parameter value above
    echo "$OBJ" | kubectl patch -f - --dry-run=client --type=json --patch="[$TMP_PATCH_STRING]" --output=yaml

    #Add delimiter to output
    echo "---"
}

function cm_backup {
    #Get list of ConfigMaps to backup 
    # In case ALL_CM arg or techdata mode was used get all CMs based on app.kubernetes.io/name="WAAS" label
    # Otherwise backup only the CustomRules CM based on kwaf-configmap-type="custom-rules" label
    IFS=$'\n'
    if [[ -n "$ALL_CM" ]]; then
        CONFIG_MAPS=($(kubectl get configmap --selector app.kubernetes.io/name="WAAS" --output jsonpath='{range .items[*]}{"--namespace="}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' --all-namespaces))
    else 
        CONFIG_MAPS=($(kubectl get configmap --selector kwaf-configmap-type="custom-rules" --output jsonpath='{range .items[*]}{"--namespace="}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' --all-namespaces))
    fi
    IFS=$OLD_IFS

    for CM in "${CONFIG_MAPS[@]}"; do
        #Get full configmap definition 
        OBJ="$(kubectl get configmap --ignore-not-found $CM --output=json)"

        #Define the string for interaction with kubernetes
        OBJ_STR="kubectl get configmap --ignore-not-found $CM"

        #Remove fields and echo the result
        patch_and_echo

        #Print progress to stderr
        echo "$CM backedup successfully" >&2
    done
}

function crd_backup {
    for CRD_TYPE in "${CRD_TYPES[@]}"; do
        #Define separator to NewLine only
        IFS=$'\n'
        #get all CRD names and namespaces, delimited by ";;"
        for CRD in $(kubectl get $CRD_TYPE --all-namespaces --ignore-not-found --output jsonpath='{range .items[*]}{"--namespace="}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'); do
            #Revert to original separator
            IFS=$OLD_IFS

            #Get full CRD definition 
            OBJ="$(kubectl get $CRD_TYPE --ignore-not-found $CRD --output=json)"

            #Define the string for interaction with kubernetes
            OBJ_STR="kubectl get $CRD_TYPE --ignore-not-found $CRD"

            #Remove fields and echo the result
            patch_and_echo

            #Print progress to stderr
            echo "$CRD backedup successfully" >&2
        done
    done
}

function recover_backup {
    OBJECT="${OBJECT//restoreNewLine\\n/$'\n'}"

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

## actual run

if [[ -n "$BKP" ]]; then 
    if [[ -z "$CRD_ONLY" ]]; then cm_backup; fi
    if [[ -z "$CM_ONLY" ]]; then crd_backup; fi
fi

if [[ -n "$RSTR" ]]; then 
    #Define separator to NewLine only
    IFS=$'\n'

    #Read input (left after argument parsing)
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

    INPUT="${INPUT//$'---\n'/radwareRestoreDelimiter$'\n'}"
    INPUT="${INPUT//$'\n'/restoreNewLine\\n}"

    # In case input containes more than one objcet (Delimiter-separated)
    # Iterate over each object performing the "recover_backup" function
    # Otherwise perform the operation on the entire input
    while [[ "$INPUT" == *"$OBJECT_DELIMITER"* ]]; do
        OBJECT="${INPUT%%"$OBJECT_DELIMITER"*}"
        recover_backup
        INPUT=${INPUT#*"$OBJECT_DELIMITER"}
    done

    if [[ $INPUT == *"\\n"* ]]; then
        OBJECT=$INPUT
        recover_backup
    fi

    # Print errors if such exsist
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

fi
