#!/bin/bash

# Declare Vars
MINIKUBE_VERSION='v1.20.15'
FALCO_VERSION='1.19.4'
FALCOSIDEKIK_VERSION='0.5.6'
KUBEPROMETHEUSSTACK_VERSION='36.2.1'
CLUSTER_NAME='falco'
TF_PATH='terraform/code'
VALUES_PATH='helm-values'
AUTIT_PATH='audit'

_help() {
	echo ""
	echo "Use: $0 -a (terraform|minikube|cloudtrail|k8s-audit|delete)"
 	echo ""
}

_minikube_ip() {
  	export MINIKUBE_IP=$(minikube ip -p ${CLUSTER_NAME})
}

_get_aws_credentials() {
  	echo "[INFO] Get AWS Credentials"
  	export AWS_ACCESS_ID=$(cat ${TF_PATH}/terraform.tfstate | jq -c '.resources[] | select(.type=="aws_iam_access_key") | .instances[].attributes.id')
  	export AWS_SECRET_ID=$(cat ${TF_PATH}/terraform.tfstate | jq -c '.resources[] | select(.type=="aws_iam_access_key") | .instances[].attributes.secret')
  
  	sed -i "s|AWS_ACCESS_ID|${AWS_ACCESS_ID}|g" ${VALUES_PATH}/falco-cloudtrail.yaml
  	sed -i "s|AWS_SECRET_ID|${AWS_SECRET_ID}|g" ${VALUES_PATH}/falco-cloudtrail.yaml
}

_terraform_apply() {
  	echo "[INFO] Deploy Terraform Code"
  	terraform -chdir=${TF_PATH} init
  	terraform -chdir=${TF_PATH} apply -auto-approve
}

_terraform_destroy() {
  	echo "[INFO] Deploy Terraform Code"
  	terraform -chdir=${TF_PATH} init
  	terraform -chdir=${TF_PATH} destroy -auto-approve
}

_minikube() {
  	echo "[INFO] Install Virtualbox"
  	sudo apt-get install virtualbox
	
  	echo "[INFO] Create Cluster on Minikube"
	minikube start -p ${CLUSTER_NAME}                                           	    \
   		--cpus 2                                                                    \
   		--memory 4096                                                               \
   		--kubernetes-version=${MINIKUBE_VERSION}                                    \
   		--driver virtualbox
	
  	echo "[INFO] Enable ingress on Minikube"
  	minikube addons enable ingress -p ${CLUSTER_NAME}
}

_falco_cloudtrail() {
  	_get_aws_credentials

	echo "[INFO] Install Falco - cloudtrail plugin"
	helm repo add falcosecurity https://falcosecurity.github.io/charts
	helm repo update
	helm upgrade --install falco-cloudtrail                                             \
    		falcosecurity/falco                                                         \
      		-f ${VALUES_PATH}/falco-cloudtrail.yaml                                     \
    		-n falco                                                                    \
    		--create-namespace                                                          \
      		--version ${FALCO_VERSION}                                                  \
      		--wait
}

_falco_k8s() {
  	echo "[INFO] Install Falco - k8s_audit plugin"
	helm upgrade --install falco-k8s-audit                                      	    \
    		falcosecurity/falco                                                         \
      		-f ${VALUES_PATH}/falco-k8s-audit.yaml                                      \
    		-n falco                                                                    \
    		--create-namespace                                                          \
      		--version ${FALCO_VERSION}                                                  \
      		--wait
}

_kube_prometheus_stack() {
  	_minikube_ip
  
  	echo "[INFO] Install kube-prometheus-stack"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install                                                              \
    		kube-prometheus-stack prometheus-community/kube-prometheus-stack            \
		-n kube-prometheus-stack                                                    \
    		--set grafana.enabled="false"                                               \
		--set alertmanager.ingress.enabled="true"                                   \
		--set alertmanager.ingress.hosts="{alertmanager.${MINIKUBE_IP}.nip.io}"     \
    		--create-namespace                                                          \
    		--version ${KUBEPROMETHEUSSTACK_VERSION}                                    \
    		--wait
}

_falco_sidekick() {
  	_minikube_ip

  	echo "[INFO] Install falcosidekick"
  	helm upgrade --install falcosidekick                                                \
    		falcosecurity/falcosidekick                                                 \
		-n falco -f ${VALUES_PATH}/sidekick.yaml                                    \
    		--set webui.enabled="true"                                                  \
		--set webui.ingress.enabled="true"                                          \
		--set webui.ingress.hosts[0].host="falcosidekick-ui.${MINIKUBE_IP}.nip.io"
}

_enable_audit() {
    	set -euo pipefail

    	APISERVER_HOST=$(minikube ip -p ${CLUSTER_NAME})
    	SSH_KEY=$(minikube ssh-key -p ${CLUSTER_NAME})

    	echo "[INFO] Copying API Server config patch"
    	minikube ssh -p ${CLUSTER_NAME} "sudo mkdir -p /var/lib/k8s_audit"
    	minikube cp ${AUTIT_PATH}/apiserver-config.patch.sh /var/lib/k8s_audit/apiserver-config.patch.sh -p ${CLUSTER_NAME}

    	echo "[INFO] Copying audit policy/webhook files to Minikube"
    	FALCO_SERVICE_CLUSTERIP=$(kubectl -n falco get service falco-k8s-audit -o=jsonpath={.spec.clusterIP}) envsubst < ${AUTIT_PATH}/webhook-config.yaml.in > ${AUTIT_PATH}/webhook-config.yaml
    	minikube cp ${AUTIT_PATH}/audit-policy.yaml /var/lib/k8s_audit/audit-policy.yaml -p ${CLUSTER_NAME}
    	minikube cp ${AUTIT_PATH}/webhook-config.yaml /var/lib/k8s_audit/webhook-config.yaml -p ${CLUSTER_NAME}

    	echo "[INFO] Modifying k8s apiserver config (will result in apiserver restarting)"

    	minikube ssh -p ${CLUSTER_NAME} "sudo bash /var/lib/k8s_audit/apiserver-config.patch.sh"

    	echo "[INFO] Done!"
}

_delete_environment() {
  	echo "[INFO] Delete environment"
	minikube delete -p ${CLUSTER_NAME}
}

# Args parsing
while getopts 'a:h' OPTION; do
  case "${OPTION}" in
    a)
      ACTION="${OPTARG}"
    ;;

    h|?|*)
      _help
      exit 1
    ;;

  esac
done

# MAIN
case ${ACTION} in
  'terraform')
    _terraform_apply
  ;;

  'minikube')
    _minikube
  ;;

  'cloudtrail')
    _falco_cloudtrail
    _kube_prometheus_stack
    _falco_sidekick
  ;;

  'k8s-audit')
    _falco_k8s
    _enable_audit
  ;;

  'delete')
    _delete_environment
    _terraform_destroy
  ;;

  *)
    echo "ERROR: Argument not valid, need some 'action'"
    _help
  ;;
esac
