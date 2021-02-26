#!/bin/bash
#
# Runs daily COVID-19 AUGUR jobs
# Run as cron job in covid19@adminvm user account
#
# USER=<USER>
# S3_BUCKET=<S3_BUCKET>
# KUBECONFIG=path/to/kubeconfig
# 0   0   *   *   *    (if [ -f $HOME/cloud-automation/files/scripts/covid19-augur-job.sh ]; then bash $HOME/cloud-automation/files/scripts/covid19-augur-job.sh; else echo "no codiv19-augur-job.sh"; fi) > $HOME/covid19-augur-job.log 2>&1

# setup --------------------

export GEN3_HOME="${GEN3_HOME:-"$HOME/cloud-automation"}"

if ! [[ -d "$GEN3_HOME" ]]; then
  echo "ERROR: this does not look like a gen3 environment - check $GEN3_HOME and $KUBECONFIG"
  exit 1
fi

PATH="${PATH}:/usr/local/bin"

source "${GEN3_HOME}/gen3/gen3setup.sh"

# lib -------------------------

help() {
  cat - <<EOM
Use: bash ./covid19-augur-job.sh
EOM
}


# main -----------------------

if [[ -z "$USER" ]]; then
  gen3_log_err "\$USER variable required"
  help
  exit 1
fi

# S3 bucket is used to store the results of the augur jobs
if [[ -z "$S3_BUCKET" ]]; then
  gen3_log_err "\$S3_BUCKET variable required"
  help
  exit 1
fi

SAFE_JOB_NAME=${JOB_NAME//_/-} # `_` to `-`

# default token life is 3600 sec. some jobs need the token to last longer.
# also skip access-token cache since jobs need fresh tokens
EXP=86400 # 8 hours
ACCESS_TOKEN="$(gen3 api access-token $USER $EXP true)"

# temporary file for the job
tempFile="$(mktemp "$XDG_RUNTIME_DIR/covid19-augur-job.yaml_XXXXXX")"
echo $tempFile

gen3 gitops filter $HOME/cloud-automation/kube/services/jobs/covid19-augur-job.yaml ACCESS_TOKEN "$ACCESS_TOKEN" S3_BUCKET "$S3_BUCKET"  > "$tempFile"

gen3 job run "$tempFile"

# cleanup
rm "$tempFile"