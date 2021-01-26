# TL;DR

A tool to copy objects in a bucket to multiple other buckets using aws batch. Users can run multiple jobs simultaneously. Each job will be run on a separated infrastructure that makes it easier to manage.

The tool will spin up a compute environment, a job queue, a job definition and a SQS. AWS Batch will manage the infrastructure, scaling up or down based on the number of jobs in queue. It also automatically bid on spot instances for you. The SQS is where the output computations are stored.

The tool can be used to any kind of task that requires batch operations. Users who use AWS batch need to write a job/service to submit jobs to the queue and to consume the SQS. The repos (https://github.com/uc-cdis/aws-batch-jobs) is where all the k8s jobs consuming SQS are stored.

## Use

### create

Launch a AWS batch operation job to copy objects from one bucket to multiple other buckets

```bash
  gen3 dcf-bucket-replicate create <source bucket> <manifest file (tsv)> <mapping file (json)>
```
manifest: a manifest (tsv) of files to replicate. Required colums: project_id, url
mapping: a json file that maps project_id to target bucket

Ex.
```
gen3 dcf-bucket-replicate create cdistest-public-test-bucket manifest.tsv mapping.json
```

### status
Checks the status of a job

```bash
  gen3 dcf-bucket-manifest status <job_id>
```

### list
List all aws batch jobs

```bash
  gen3 dcf-bucket-manifest list
```

### cleanup
Tear down the infrastructure of given job_id

```bash
  gen3 dcf-bucket-manifest cleanup <job_id>