# Backup-Restore

## Table Of Contents ###
- [Description](#description )
- [Requirements](#requiremnts )
- [Usage](#usage )
  * [Backup](#backup )
  * [Restore](#restore)

## Description ##
Following script is used to backup and restore kWAF configuration.
All the configurations collected by the backup tool will be printed to `stdout` use CLI redirect (`>` or `>>`) or terminal logging for saving to a file.
while performing the restore operation, in case the utility encounters a configuration in a none-existing namespace it will attempt to create the namespace using `kubectl create namespace` command 

## Requirements ##
This utility requires:
 - Connectivity to the k8s cluster running kWAF
 - kubectl installed and configured with relevant permissions
 * Backup utility requires read pemissions to kWAF related objects (Custom-resources as well as relevant ConfigMaps) in all namespaces
 * Restore utility requires write pemissions on kWAF related objects (Custom-resources as well as relevant ConfigMaps) in relevant namespaces
 * Restore utility may require Namespace creation permission as well

## Usage ##
The utility is split into two parts, a script for the backup operation and a script for the restore.

### Backup ###
By default the backup utility will use `kubectl` for geting YAML config of all kWAF Custom Resources as well as the `waas-custom-rules-configmap` ConfigMap.


Following CLI arguments can be used to change default backup behavior
 - Use `--crd_only` or `CRD_ONLY` to skip Config Maps
 - Use `--cm_only` or `CM_ONLY` to skip Custom Resources
 - Use `--all_cm` or `ALL_CM` to backup all kWAF related ConfigMaps
 <sub> this option is not recomended in case of kWAF upgrades </sub>
 - Use `--raw` or `RAW` to skip dynamic fields stripping (such as creation timestamp, resourceVersion, etc..) 
 <sub> this option should be used for configuration gathering only, retoring "RAW" backup is not supported.</sub>

Usage Example: 
`user@server$ ./backup.sh --crd_only > /tmp/kwaf_backup.yaml`

### Restore ###
The restore utility can get the configuration either by provided filename (including path) in wich case it will read the file to get the config, or by reading the `stdin` in case the configuration was sent to the script dyrectly

Filename Example:
`user@server$ ./restore.sh /tmp/kwaf_backup.yaml`

Redirect example:
`user@server$ cat /tmp/kwaf_backup.yaml | restore.sh`
