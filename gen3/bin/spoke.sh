#
# Unified entrypoint for gitops and manifest related commands
#

source "${GEN3_HOME}/gen3/lib/utils.sh"
gen3_load "gen3/gen3setup"

gen3_spoke_help() {
  gen3 help spoke
  exit 1
}

gen3_spoke_terraform() {
  if [[ $# -lt 1 ]]; then
    gen3_log_err "use: gen3_spoke_terraform [profile]"
    return 1
  fi
  local profile=$1
  shift
  gen3 workon $profile "${profile}__spoke"
  gen3 cd
  ls
}

gen3_spoke_launch() {
  if [[ $# -lt 3 ]]; then
    gen3_log_err "use: gen3 spoke launch [name] [aws accountid] [aws role name]"
    return 1
  fi
  local name=$1
  shift
  local awsaccountid="$1"
  shift
  local awsrole="$1"
  shift
  local awsregion="${1:-us-east-1}"
  shift
  echo $awsregion
  if [[ ! $awsaccountid =~ ^[0-9]{12}$ ]]; then
    gen3_log_err "$awsaccountid is not a valid AWS account id. AWS account id is supposed to be 12 digits only"
  else
    gen3_log_info "$awsaccountid is a valid AWS account id (12 digits)"
  fi
  rolearn="arn:aws:iam::$awsaccountid:role/$awsrole"
  gen3_log_info "Trying to assume role $rolearn"
  if [[ $(aws sts assume-role --role-arn $rolearn --role-session-name $name)  ]]; then
    gen3_log_info "successfully assumed role $rolearn"
  else
    current_aws_account=$(aws sts get-caller-identity --query Account --output text)
    current_aws_info=$(aws sts get-caller-identity)
    gen3_log_err "Cannot assume role. Make sure the AWS account $current_aws_account has access to assume $rolearn: "
    gen3_log_err "$current_aws_info"
  fi
  if [[ -f ${WORKSPACE}/.aws/config ]]; then
    if [[ ! $(cat ${WORKSPACE}/.aws/config | grep "profile $name") ]]; then 
      gen3_log_info "AWS profile $name with role-arn $rolearn doesn't exist in aws config. Adding to ${WORKSPACE}/.aws/config"
      tee -a ${WORKSPACE}/.aws/config > /dev/null <<END

[profile $name]
output = json
region = $awsregion
role_session_name = gen3_spoke_$name
role_arn = $rolearn
source_profile = default
END
    fi
  fi

  gen3_spoke_terraform $name
  
}


gen3_spoke_main() {
  if [[ $# -lt 1 ]]; then
    help
  fi
  local command="$1"
  shift
  case "$command" in
  "launch")
    gen3_spoke_launch "$@"
    ;;
  *)
    gen3_log_err "invalid command: $command"
    gen3_spoke_help
    exit 1
    ;;
  esac
}

# main ---------------------------

if [[ -z "$GEN3_SOURCE_ONLY" ]]; then
  gen3_spoke_main "$@"
fi