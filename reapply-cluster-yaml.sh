#!/bin/bash
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
START_TIME=$(date +%Y-%m-%d--%H%M%S)
SCRIPT_NAME="gen-clusterRegistrationToken-yamls.sh"
# Login token good for 1 minute
TOKEN_TTL=60000

function helpmenu() {
    echo "Usage: ${SCRIPT_NAME}
"
    exit 1
}
#TODO
#Add confirmation logic for docker run command
#Add restore task
while getopts "hyu:" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    y) # process option y: auto install dependencies
        INSTALL_MISSING_DEPENDENCIES=yes
        ;;
    u) # process option u: set username
        USERNAME=${OPTARG}
        ;;
    p) # process option p: set username
        PASSWORD=${OPTARG}
        ;;
    s) # process option s: set CATTLE_SERVER
        CATTLE_SERVER=${OPTARG}
        ;;
    c) # process option c: set CLUSTERID
        CLUSTERID=${OPTARG}
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done
function yesno() {
    shopt -s nocasematch
    response=''
    i=0
    while [[ ${response} != 'y' ]] && [[ ${response} != 'n' ]]; do
        i=$((i + 1))
        if [ $i -gt 10 ]; then
            echo "Script is destined to loop forever, aborting!  Make sure your docker run command has -ti then try again."
            exit 1
        fi
        printf '(y/n): '
        read -n1 response
        echo
    done
    shopt -u nocasematch
}
function checkpipecmd() {
    RC=("${PIPESTATUS[@]}")
    if [[ "$2" != "" ]]; then
        PIPEINDEX=$2
    else
        PIPEINDEX=0
    fi
    if [ "${RC[${PIPEINDEX}]}" != "0" ]; then
        echo "${green}$1${reset}"
        exit 1
    fi
}
if ! hash curl 2>/dev/null && [ ${INSTALL_MISSING_DEPENDENCIES} == "yes" ]; then
    if [[ -f /etc/redhat-release ]]; then
        OS=redhat
        echo "${green}You are using Red Hat based linux, installing curl with yum since you passed -y${reset}"
        yum install -y curl
    elif [[ -f /etc/lsb_release ]]; then
        OS=ubuntu
        echo "${green}You are using Debian/Ubuntu based linux, installing curl with apt since you passed -y${reset}"
        apt update && apt install -y curl
    else
        echo '!!!curl was not found!!!'
        echo 'Please install curl if you want to automatically install missing dependencies'
        exit 1
    fi
fi
if ! hash kubectl 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
        chmod +x ./kubectl
        mv ./kubectl /bin/kubectl
    else
        echo "!!!kubectl was not found!!!"
        echo "!!!download and install with:"
        echo "Linux users (Run script with option -y to install automatically):"
        echo "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
        echo "chmod +x ./kubectl"
        echo "mv ./kubectl /bin/kubectl"
        echo "!!!"
        echo "Mac users:"
        echo "brew install kubernetes-cli"
        exit 1
    fi
fi
if ! hash jq 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        curl -L -O https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
        chmod +x jq-linux64
        mv jq-linux64 /bin/jq
    else
        echo '!!!jq was not found!!!'
        echo "!!!download and install with:"
        echo "Linux users (Run script with option -y to install automatically):"
        echo "curl -L -O https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
        echo "chmod +x jq-linux64"
        echo "mv jq-linux64 /bin/jq"
        echo "!!!"
        echo "Mac users:"
        echo "brew install jq"
        echo "brew link jq"
        exit 1
    fi
fi
if ! hash sed 2>/dev/null; then
    echo '!!!sed was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash cut 2>/dev/null; then
    echo '!!!cut was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash grep 2>/dev/null; then
    echo '!!!grep was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash ip 2>/dev/null; then
    echo '!!!ip was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
#Auto set USERNAME if none was specified
if [[ "${USERNAME}" == "" ]]; then
    USERNAME='admin'
fi

#Prompt for PASSWORD if none was specified
if [[ "${PASSWORD}" == "" ]]; then
    #PASSWORD='XeD9oSQwRSxe8auXPgfNP8ifMTkLeWZxpig'
    echo -n "${green}Password: ${reset}"
    read -s PASSWORD
    echo
fi
if [[ "${CATTLE_SERVER}" == "" ]]; then
    #get default route interface
    DEFAULT_ROUTE_IFACE=$(ip route | grep default | cut -d' ' -f5)
    #Get local IP for determining cluster ID
    DEFAULT_IP="$(ip a show ${DEFAULT_ROUTE_IFACE} | grep inet | grep -v inet6 | awk '{print $2}' | cut -f1 -d'/')"
    #get cattle node agent ID for docker inspect
    CATTLE_NODE_AGENT_ID=$(docker ps | grep -i k8s_agent_cattle-node-agent | cut -d' ' -f1)
    #get CATTLE_SERVER
    eval $(docker inspect ${CATTLE_NODE_AGENT_ID} --format '{{range $index, $value := .Config.Env}}{{println $value}}{{end}}' | grep CATTLE_SERVER=)
fi

#Get a temporary login token
LOGINTOKEN=$(curl -k -s ''${CATTLE_SERVER}'/v3-public/localProviders/local?action=login' -H 'content-type: application/json' --data-binary '{"username":'\"${USERNAME}\"',"password":'\"${PASSWORD}\"',"ttl":'${TOKEN_TTL}'}' | jq -r .token)

if [[ "${CATTLE_SERVER}" == "" ]]; then
    #store /v3/clusters output
    CLUSTERS=$(curl -k -s ''${CATTLE_SERVER}'/v3/clusters' -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}")
    #Store nodeId
    NODEID=$(jq -r '.data[]?.appliedSpec.rancherKubernetesEngineConfig.nodes[]? | select(.address == '\"${DEFAULT_IP}\"') | .nodeId' <<<${CLUSTERS})
    #Store CLUSTERID
    CLUSTERID=$(cut -d':' -f1 <<<${NODEID})
fi

#Store /v3/clusterregistration output
CLUSTERREGISTRATION=$(curl -k -s ''${CATTLE_SERVER}'/v3/clusterregistrationtoken?clusterId='${CLUSTERID}'' -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}")

#Store InsecureCommand
INSECURECOMMAND=$(jq -r '.data[0].insecureCommand' <<<${CLUSTERREGISTRATION})

##change /v3/clusters into space delimited list of node ips
#NODES=$(jq -r '.data[]?.appliedSpec.rancherKubernetesEngineConfig.nodes[]?.address' <<< ${CLUSTERS})
#
##put nodes of cluster into an array
#SAVEIFS=$IFS   # Save current IFS
#IFS=$'\n'      # Change IFS to new line
#NODES=($NODES) # split to array $NODES
#IFS=$SAVEIFS   # Restore IFS
#
#for (( i=0; i<${#NODES[@]}; i++ ))
#do
#    if [[ "${NODES[$i]}" == "${DEFAULT_IP}" ]]; then
#
#done
