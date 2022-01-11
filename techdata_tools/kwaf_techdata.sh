#!/bin/bash

#our defaults:
DEFAULT_NAMESPACE=kwaf
DEFAULT_HELM_RELEASE_NAME=waas

NAMESPACE=$DEFAULT_NAMESPACE
HELM_RELEASE_NAME=$DEFAULT_HELM_RELEASE_NAME
CTR=1

function print_delimiter {
  printf '\n=================================================>\n\n'
}

function print_help {
  printf '\nKWAF techdata dump script help.\n Flags:\n'
  printf '\t -n, --namespace \t\t The Namespace in which KWAF is installed. default: %s\n' "$DEFAULT_NAMESPACE"
  printf '\t -r, --releasename \t\t The Helm release name with which KWAF was installed. default: %s\n' "$DEFAULT_HELM_RELEASE_NAME"
}

CMDS_WITHOUT_ARGS=( 'whoami'
                    'command -v kubectl'
                    'command -v helm'
                    'kubectl version'
                    'helm version'
                    'kubectl config get-contexts'
                    'kubectl get crd'
                    'kubectl get validatingwebhookconfigurations'
                    'helm ls -A')

HELM_CMDS_REQUIRE_NS_AND_RELEASE=('helm get values -n %s %s'
                                  'helm get manifests -n %s %s')

KUBECTL_CMDS_REQUIRE_NS=( 'kubectl get deployments -n %s'
                          'kubectl get statefulsets -n %s'
                          'kubectl get -n %s secret'
                          'kubectl get -n %s cm')




## Functionality starts here:

#Parse the incoming args:
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"  #Read the provided NS arg
      shift # past argument
      shift # past value
      ;;
    -r|--releasename)
      HELM_RELEASE_NAME="$2"  #Read the provided releasename arg
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      ##help scenario.
      print_help
      exit 1
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

## args parsed. let's start running cmds:

printf "\n\n =====> KWAF techdata script start\n\n"
printf "NAMESPACE  = %s\n" "$NAMESPACE"
printf "HELM_RELEASE_NAME = %s\n" "$HELM_RELEASE_NAME"

## Execute all the cmds that don't require any args:
for str in "${CMDS_WITHOUT_ARGS[@]}"; do
  print_delimiter
  printf '%d) Executing %s:\n\n' "$CTR" "$str"
  #exec:
  eval "$str"
  ((CTR=CTR+1))
done

## Execute the Helm cmds that require 2 args:
for str in "${HELM_CMDS_REQUIRE_NS_AND_RELEASE[@]}"; do
  cmd_to_exec=$(printf "$str" "$NAMESPACE" "$HELM_RELEASE_NAME") ##create the command dynamically
  str=$cmd_to_exec
  print_delimiter
  printf '%d) Executing %s:\n\n' "$CTR" "$str"
  #exec:
  eval "$str"
  ((CTR=CTR+1))
done

## Execute kubectl cmds that require 1 arg:
for str in "${KUBECTL_CMDS_REQUIRE_NS[@]}"; do
  cmd_to_exec=$(printf "$str" "$NAMESPACE") ##create the command dynamically
  str=$cmd_to_exec
  print_delimiter
  printf '%d) Executing %s:\n\n' "$CTR" "$str"
  #exec:
  eval "$str"
  ((CTR=CTR+1))
done

printf "\n\n =====> KWAF techdata script end\n\n"
