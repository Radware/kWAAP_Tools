# kWAAP_Tools
KWAAP-related tools and scripts for internal / external usage.

## Table Of Contents ###
- [Description](#description )
- [Requirements](#requiremnts )
- [Usage](#usage )
  * [Techdata](#techdata )
  * [Backup](#backup )
  * [Restore](#restore)
  * [Assistance](#assistance)

## Description ##
Following script is used to collect technical information, backup and restore kWAAP configuration.
All the configurations collected by this tool wull be saves to directory defined by argument "--dir";
or will be printed to `stdout` use CLI redirect (`>` or `>>`) or terminal logging for saving to a file.
while performing the restore operation, in case the utility encounters a configuration in a none-existing namespace it will attempt to create the namespace using `kubectl create namespace` command 

## Requirements ##
This utility requires:
 - Connectivity to the k8s cluster running kWAAP
 - kubectl installed and configured with relevant permissions
 * Backup utility requires read pemissions to kWAAP related objects (Custom-resources as well as relevant ConfigMaps) in all namespaces
 * Restore utility requires write pemissions on kWAAP related objects (Custom-resources as well as relevant ConfigMaps) in relevant namespaces
 * Restore utility may require Namespace creation permission as well

## Usage ##
Use command line arguments to choose desired operation

| Argument | Description |
| --- | --- | 
| `--backup` | Perform the backup operation |
| `--restore` | Perform the restore operation |
| `--techdata` | Collect technical data infromation |
| `--crd_only` | Skip Config Maps |
| `--cm_only` | Skip Custom Resources |
| `--all_cm` | Backup/Collect all kWAAP related ConfigMaps.<br><sub>*Not recomended to use outside of techdata collection</sub> |
| `--raw_output` | Skip removal of dynamic fields (`resourceVersion`, `uid`, etc..).<br><sub>*Not recomended to use outside of techdata collection</sub> |
| `-n` or `--namespace` | The Namespace in which kWAAP is installed. default: `kwaf` |
| `-r` or `--releasename` | The Helm release name with which kWAAP was installed. default: `waas` |
| `-c` or `--containers` | The list of pods and containers per namespaces for which data will be collected. Format:"ns1:pod1#cont1,pod2;ns2:;ns3:#cont2". Default: The list of ALL pods and containers defined by the `--namespace` and `--container` arguments. |
| `-cd` or `--args-file` | The filename of JSON file that is used in place of the "--containers", and other data collection arguments |
| `-cd` or `--config-dump` | The boolean determines whether  config-dump should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `-se` or `--security-events` | The boolean determines whether security-events should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `-al` or `--access-logs` | The boolean determines whether access-logs should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `-rd` or `--requst-data` | The boolean determines whether requst-data should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `-l` or `--logs` | The boolean determines whether logs should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `-pl` or `--previous-logs` | The boolean determines whether previous logs should be collected from the pods:containers defined by the `--namespace` and one of `--container` or `--containers` arguments. Default: false |
| `--container` | The name of the container for which data will be collected from all pods in a specified namespace, in the case where `--containers` is not defined. Default: all containers from all modules in the specified namespace. |
| `-mcu` or `--memory-cpu-usage `| The boolean determines whether memory and CPU usage for nodes, pods, and containers will be collected. Note: the metrics-server will be installed if it has not been installed previously. |
| `-h` or `--help` | Print help message and exit |

### Techdata ###
The techdata utility collects relevant helm and k8s content; and data from specific containers.
The list of these containers can be defined either using a json file - the value of the `--args-file` argument,
or using arguments: 
    `--namespace`, 
    `--containers` or  `--container`, 
    and flags:  `--config-dump`, `--security-events`, `--access-logs`, `--requst-data`, `--logs` and `--previous-logs`.

An example file `--args-file` is found in `tools_collect_data_params_ex/` directory. <br><br>
The format of the "--containers" argument is as follows:<br>
	"[<namespace>]:[[<pod-name1>]#[<container-name1>],[<pod-name1>]#[<container-name2>]...];..."<br>
	Special cases:
- The default namespace or the value of the "--namesapce" argument (if defined) will be used for a module with an empty namespace.<br>
   For example, '--namespace radware --containers "...;:[<pods-contaters list>];..."' is the same as' --containers "...;radware:[<pods-contaters list>];..."'<br>
- If the container name is omitted, all pod containers will be processed.<br>
  For example, '--containers "radware:pod1,pod2#cont2"' is the same as' --containers "radware:pod1#cont1,pod1#cont2,pod2#cont2"', where pod1 has 2 contaners: cont1 and cont2.<br>
- If the pod-name is omitted, all pods containing the given container in the given namespace will be processed.<br>
  For example, '--containers "radware:pod1#cont1,#cont2"' is the same as' --containers "radware:pod1#cont1,pod2#cont2,pod3#cont2"', where pod2 and pod3 have contaner cont2<br>
- If the "--containers" arg is omitted, "--namespace" arg( of default namespace, not if defined) and "--container" arg  will be processed.<br>
  Two examples:<br>
     (1) '--namespace radware --container cont1' is the same as ' --containers "radware:#cont1"'<br>
     (2) '--namespace radware' is the same as ' --containers "radware:"'<br>

Usage Examples: <br>

`$ ./tools.sh --techdata  -d tdata_dir -n keaf --container controller -l -pl` <br>

`$ ./tools.sh --techdata -d tdata_dir -n kwaf -l -cd -c "cert_manager:;local-path-storage:;kwaf:waas-sample-app-httpbin-deployment-64f58df466-vqlz9#enforcer,waas-sample-app-httpbin-deployment-64f58df466-vqlz9#fluentbit,waas-gui-deployment-7d4f67b48-ld7gc#,waas-sample-app-grpcx-deployment-656d7956f9-8p5wg#logrotate,#controller,#elasticsearch;"` <br>

`$ ./tools.sh --techdata -d tdata_dir -n kwaf -af tools_collect_data_params_ex/params_exmpl1.json` <br>

`$ ./tools.sh --techdata -d tdata_dir -n kwaf --container enforcer -mcu` <br>

### Backup ###
By default the backup utility will use `kubectl` for geting YAML config of all kWAAP Custom Resources as well as the `waas-custom-rules-configmap` ConfigMap.

Following CLI arguments can be used to change default backup behavior
 - Use `--crd_only` or `CRD_ONLY` to skip Config Maps
 - Use `--cm_only` or `CM_ONLY` to skip Custom Resources
 - Use `--all_cm` or `ALL_CM` to backup all kWAAP related ConfigMaps <br>
 <sub> this option is not recommended in case of kWAAP upgrades </sub>
 - Use `--raw` or `RAW` to skip dynamic fields stripping (such as creation timestamp, resourceVersion, etc..) <br>
 <sub> this option should be used for configuration gathering only, retoring "RAW" backup is not supported.</sub>

Usage Example: 
`$ ./tools.sh --backup --crd_only > /tmp/kwaap_crd.yaml` <br>
`$ ./tools.sh --backup > /tmp/kwaap_backup.yaml`

### Restore ###
The restore utility can get the configuration either by provided filename (including path) in wich case it will read the file to get the config, or by reading the `stdin` in case the configuration was sent to the script dyrectly

Filename Example:
`$ ./tools.sh --restore  /tmp/kwaap_crd.yaml`

Redirect example:
`$ cat /tmp/kwaap_crd.yaml | ./tools.sh --restore`

### Assistance ###
Currently, the utility allows to get all containers for each pod in a specific namespace or in all existing namespaces.

Following CLI arguments can be used:
- Use `-n` or `--namespace` - the namespace 
- Use `-c` or `--containers` to print all containers for each pod in the namespace defined by `-n' or for all namespaces

Usage Example:<br>
`$ ./tools_assist.sh -n kwaf -c`