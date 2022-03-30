#! /bin/bash

#Get List of CRDs to backup (based on "waas.radware.com" group)
CRD_TYPES=($(kubectl get crd -o jsonpath='{.items[?(@.spec.group=="waas.radware.com")].metadata.name}'))

#Get list of ConfigMaps to backup (based on names starting with "waas-" not including the individual apps "waas-ca-config"s)
CONFIG_MAPS_NAMES=($(kubectl get cm --all-namespaces | grep -Po "waas-[^ ]*" | grep -v "waas-ca-config-.*"))

#Kubectl patch parameters for removing fields
PATCH_STRING=('{"op": "remove", "path": "/metadata/uid"}' '{"op": "remove", "path": "/metadata/resourceVersion"}' '{"op": "remove", "path": "/metadata/selfLink"}' '{"op": "remove", "path": "/metadata/creationTimestamp"}' '{"op": "replace", "path": "/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration", "value": ""}' '{"op": "remove", "path": "/status"}' '{"op": "remove", "path": "/metadata/generation"}' '{"op": "remove", "path": "/metadata/finalizers"}')
PATCH_FIELD=('.metadata.uid' '.metadata.resourceVersion' '.metadata.selfLink' '.metadata.creationTimestamp' '.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration' '.status' '.metadata.generation' '.metadata.finalizers')

#Make sure ConfigMap output file is empty
function cm_backup {
    for CM_NAME in "${CONFIG_MAPS_NAMES[@]}"; do
        for CM in $(kubectl get cm --all-namespaces --ignore-not-found --field-selector metadata.name=$CM_NAME -o jsonpath='{range .items[*]}{@.metadata.name}{";;"}{@.metadata.namespace}{"\n"}{end}'); do
            #Extract CM name - the string up to ";;"
            NAME=${CM%;;*}
            
            #Extract CM name - the string after ";;"
            NS=${CM#*;;}
            
            #Get full configmap definition 
            OBJ="$(kubectl get cm --ignore-not-found --namespace $NS $NAME -o json)"
        
            #Remove fields
            TMP_PATCH_STRING=""
            for (( i=0; i<${#PATCH_FIELD[@]}; i++)); do
                LAST_CONFIG=$(kubectl get cm --ignore-not-found --namespace $NS $NAME -o jsonpath={${PATCH_FIELD[$i]}})
                if [[ ! -z $LAST_CONFIG ]]; then TMP_PATCH_STRING+="${PATCH_STRING[$i]}"; fi
            done

            #Seprate patch fields with comma
            TMP_PATCH_STRING=${TMP_PATCH_STRING//\}\{/\}, \{}

            #Remove fields based on the parameter value above
            echo "$OBJ" | kubectl patch -f - --dry-run=client --type=json --patch="[$TMP_PATCH_STRING]" -o yaml

            #Add delimiter to output
            echo "---"
        done
    done
}

function crd_backup {
    for CRD_TYPE in "${CRD_TYPES[@]}"; do
        #get all CRD names and namespaces, delimited by ";;"
        for CRD in $(kubectl get $CRD_TYPE --all-namespaces --ignore-not-found -o jsonpath='{range .items[*]}{@.metadata.name}{";;"}{@.metadata.namespace}{"\n"}{end}'); do
            #Extract CRD name - the string up to ";;"
            NAME=${CRD%;;*}
            
            #Extract CRD namespace - the string after ";;"
            NS=${CRD#*;;}
            
            #Get full CRD definition 
            OBJ="$(kubectl get $CRD_TYPE --ignore-not-found --namespace $NS $NAME -o json)"
            
            TMP_PATCH_STRING=""
            for (( i=0; i<${#PATCH_FIELD[@]}; i++)); do
                LAST_CONFIG="$(kubectl get $CRD_TYPE --ignore-not-found --namespace $NS $NAME -o jsonpath={${PATCH_FIELD[$i]}})"
                if [[ ! -z $LAST_CONFIG ]]; then TMP_PATCH_STRING+="${PATCH_STRING[$i]}"; fi
            done

            #Seprate patch fields with comma
            TMP_PATCH_STRING=${TMP_PATCH_STRING//\}\{/\}, \{}

            #Remove fields based on the parameter value above
            echo "$OBJ" | kubectl patch -f - --dry-run=client --type=json --patch="[$TMP_PATCH_STRING]" -o yaml
            
            #Add delimiter to output
            echo "---"
        done
    done
}

cm_backup
crd_backup