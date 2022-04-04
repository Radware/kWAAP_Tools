#! /bin/bash

#Backup original IFS (word separator) 
OLD_IFS="$IFS"
#Define separator to NewLine only
IFS=$'\n'

#Get List of CRDs to backup (based on "waas.radware.com" group)
CRD_TYPES=($(kubectl api-resources --api-group=waas.radware.com --output=name))

#Get list of ConfigMaps to backup (based on names starting with "waas-" not including the individual apps "waas-ca-config"s)
CONFIG_MAPS=($(kubectl get configmap --selector app.kubernetes.io/name="WAAS" --output jsonpath='{range .items[*]}{"--namespace="}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' --all-namespaces))

#Revert to original separator
IFS=$OLD_IFS

#Kubectl patch parameters for removing fields
PATCH_STRING=('{"op": "remove", "path": "/metadata/uid"}' '{"op": "remove", "path": "/metadata/resourceVersion"}' '{"op": "remove", "path": "/metadata/selfLink"}' '{"op": "remove", "path": "/metadata/creationTimestamp"}' '{"op": "replace", "path": "/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration", "value": ""}' '{"op": "remove", "path": "/status"}' '{"op": "remove", "path": "/metadata/generation"}' '{"op": "remove", "path": "/metadata/finalizers"}')
PATCH_FIELD=('.metadata.uid' '.metadata.resourceVersion' '.metadata.selfLink' '.metadata.creationTimestamp' '.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration' '.status' '.metadata.generation' '.metadata.finalizers')

function patch_and_echo {
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
    for CM in "${CONFIG_MAPS[@]}"; do
        #Get full configmap definition 
        OBJ="$(kubectl get configmap --ignore-not-found $CM --output=json)"
        
        #Define the string for interaction with kubernetes
        OBJ_STR="kubectl get configmap --ignore-not-found $CM"
        
        #Remove fields and echo the result
        patch_and_echo
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
        done
    done
}

if [[ $1 != "CRD_ONLY" ]]; then cm_backup; fi
if [[ $1 != "CM_ONLY" ]]; then crd_backup; fi

