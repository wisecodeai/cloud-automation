source "${GEN3_HOME}/gen3/lib/utils.sh"
gen3_load "gen3/lib/kube-setup-init"

g3kubectl apply -f "${GEN3_HOME}/kube/services/stata/stata-deploy.yaml"
g3kubectl apply -f "${GEN3_HOME}/kube/services/stata/stata-service.yaml"
