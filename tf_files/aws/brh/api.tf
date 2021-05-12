terraform {
  backend "s3" {
    encrypt = "true"
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
    index_name = "bmh-workspace-index-${var.index_id}"
    global_secondary_indexes = [
        {
            name               = local.index_name
            hash_key           = var.hash_key
            projection_type    = "KEYS_ONLY"
        }
    ]
}


data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "brh-api-lambda" {
  name                  = "brh-api-lambda"
  description           = "Role for the lambda function"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role" "brh-infra-lambda" {
  name                  = "brh-infra-lambda"
  description           = "Role for the lambda function"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "api" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.brh-api-lambda.name
}

resource "aws_iam_role_policy_attachment" "infra" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.brh-infra-lambda.name
}


module "brh-api-lambda" {
  source                       = "../modules/lambda-function/"
  lambda_function_file         = var.api_lambda_source_path
  lambda_function_name         = "brh-workspaces-resource-function"
  lambda_function_description  = ""
  lambda_function_runtime      = "python3.8"
  lambda_function_iam_role_arn = aws_iam_role.brh-api-lambda.arn
  lambda_function_env          = {
    "dynamodb_table_param_name" = var.dynamodb_table_param_name,
    "dynamodb_index_param_name": var.dynamodb_index_param_name,
    "api_usage_id_param_name": var.api_usage_id_param_name,
    #"brh_asset_bucket": brh_workspace_assets_bucket.bucket_name,
    "brh_portal_url": var.api_url_param_name,
    #"state_machine_arn": step_fn_workflow.state_machine_arn
  }
  lambda_function_handler      = "workspaces_api_resource_handler.handler"
}

module "brh-create-workspace-lambda" {
  source                       = "../modules/lambda-function/"
  lambda_function_file         = var.infra_lambda_source_path
  lambda_function_name         = "create-workspace-function"
  lambda_function_description  = "Function which deploys BRH specific infrastructure (cost and usage, etc.) to member accounts."
  lambda_function_runtime      = "python3.8"
  lambda_function_iam_role_arn = aws_iam_role.brh-infra-lambda.arn
  lambda_function_env          = {
    "dynamodb_table_param_name" = var.dynamodb_table_param_name,
    "dynamodb_index_param_name": var.dynamodb_index_param_name,
    #"brh_asset_bucket": brh_workspace_assets_bucket.bucket_name,
    "brh_portal_url": var.api_url_param_name,
  }
  lambda_function_handler      = "deploy_brh_infra.handler"
}

module "dynamodb" {
    source = "../modules/dynamodb"
    create_table = var.create_table
    name = var.name
    attributes = var.attributes
    hash_key = var.hash_key
    range_key = var.range_key
    billing_mode = var.billing_mode
    write_capacity = var.write_capacity
    read_capacity = var.read_capacity
    point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    ttl_enabled = var.ttl_enabled
    ttl_attribute_name = var.ttl_attribute_name
    global_secondary_indexes = local.global_secondary_indexes
    local_secondary_indexes = var.local_secondary_indexes
    replica_regions = var.replica_regions
    stream_enabled = var.stream_enabled
    stream_view_type = var.stream_view_type
    server_side_encryption_enabled = var.server_side_encryption_enabled
    server_side_encryption_kms_key_arn = var.server_side_encryption_kms_key_arn
    tags = var.tags
    timeouts = var.timeouts
    autoscaling_defaults = var.autoscaling_defaults
    autoscaling_read = var.autoscaling_read
    autoscaling_write = var.autoscaling_write
    autoscaling_indexes = var.autoscaling_indexes
}

resource "aws_ssm_parameter" "workspace-dynamodb-table-parameter" {
  name  = var.workspace-dynamodb-table-parameter
  description = "Dynamodb Table Name for Workspace Info"
  type  = "String"
  value = module.dynamodb.dynamodb_table_name
}

resource "aws_ssm_parameter" "workspace-dynamodb-gsi-parameter" {
  name  = var.workspace-dynamodb-gsi-parameter
  type  = "String"
  value = local.index_name
}




resource "aws_cloudwatch_log_group" "bmh-workspaces-api-loggroup" {
    name   = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.brh-workspaces-api.id}/api"
}
resource "aws_api_gateway_rest_api" "brh-workspaces-api" {
  name = "brh-workspaces-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
module "root_cors" {
  source = "../modules/api-gateway-enable-cors"
  api_id          = aws_api_gateway_rest_api.brh-workspaces-api.id
  api_resource_id = aws_api_gateway_rest_api.brh-workspaces-api.root_resource_id
}

resource "aws_ssm_parameter" "workspaces-api-url-parameter" {
  name  = var.api_url_param_name
  type  = "String"
  value = aws_api_gateway_stage.api.invoke_url
}
## /workspaces endpoint
resource "aws_api_gateway_resource" "workspaces" {
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  parent_id   = aws_api_gateway_rest_api.brh-workspaces-api.root_resource_id
  path_part   = "workspaces"
}
module "workspaces_cors" {
  source = "../modules/api-gateway-enable-cors"
  api_id          = aws_api_gateway_rest_api.brh-workspaces-api.id
  api_resource_id = aws_api_gateway_resource.workspaces.id
}

## /workspaces/{workspace_id}
resource "aws_api_gateway_resource" "workspace_id" {
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  parent_id   = aws_api_gateway_resource.workspaces.id
  path_part   = "{workspace_id}"
}
module "workspace_id_cors" {
  source = "../modules/api-gateway-enable-cors"
  api_id          = aws_api_gateway_rest_api.brh-workspaces-api.id
  api_resource_id = aws_api_gateway_resource.workspace_id.id
}

## /workspaces/{workspace_id}/limits
resource "aws_api_gateway_resource" "workspace_id_limits" {
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  parent_id   = aws_api_gateway_resource.workspace_id.id
  path_part   = "limits"
}
module "limits_cors" {
  source = "../modules/api-gateway-enable-cors"
  api_id          = aws_api_gateway_rest_api.brh-workspaces-api.id
  api_resource_id = aws_api_gateway_resource.workspace_id_limits.id
}

## /workspaces/{workspace_id}/total-usage
resource "aws_api_gateway_resource" "workspace_id_total_usage" {
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  parent_id   = aws_api_gateway_resource.workspace_id.id
  path_part   = "total-usage"
}
module "total_usage_cors" {
  source = "../modules/api-gateway-enable-cors"
  api_id          = aws_api_gateway_rest_api.brh-workspaces-api.id
  api_resource_id = aws_api_gateway_resource.workspace_id_total_usage.id
}


# GET /workspaces
resource "aws_api_gateway_method" "workspaces-get" {
  resource_id   = aws_api_gateway_resource.workspaces.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "GET"
  api_key_required  = true
}

resource "aws_api_gateway_integration" "workspaces-get" {
  http_method             = aws_api_gateway_method.workspaces-get.http_method
  resource_id             = aws_api_gateway_resource.workspaces.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  

  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn

}

# POST /workspaces
resource "aws_api_gateway_method" "workspaces-post" {
  resource_id   = aws_api_gateway_resource.workspaces.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "POST"
  api_key_required  = true
}

resource "aws_api_gateway_integration" "workspaces-post" {
  http_method             = aws_api_gateway_method.workspaces-post.http_method
  resource_id             = aws_api_gateway_resource.workspaces.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn
}

# GET /workspaces/{workspace_id}
resource "aws_api_gateway_method" "workspace_id-get" {
  resource_id   = aws_api_gateway_resource.workspace_id.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "GET"
  api_key_required  = true
}

resource "aws_api_gateway_integration" "workspace_id-get" {
  http_method             = aws_api_gateway_method.workspace_id-get.http_method
  resource_id             = aws_api_gateway_resource.workspace_id.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn
}

# POST /workspaces/{workspace_id}
resource "aws_api_gateway_method" "workspace_id-post" {
  resource_id   = aws_api_gateway_resource.workspace_id.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "POST"
  api_key_required  = true
}
resource "aws_api_gateway_integration" "workspace_id-post" {
  http_method             = aws_api_gateway_method.workspace_id-post.http_method
  resource_id             = aws_api_gateway_resource.workspace_id.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn
}

# PUT /workspaces/{workspace_id}/limits
resource "aws_api_gateway_method" "workspace_id_limits-put" {
  resource_id   = aws_api_gateway_resource.workspace_id_limits.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "PUT"
  api_key_required  = true
}

resource "aws_api_gateway_integration" "workspace_id_limits-put" {
  http_method             = aws_api_gateway_method.workspace_id_limits-put.http_method
  resource_id             = aws_api_gateway_resource.workspace_id_limits.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn
}

# PUT /workspaces/{workspace_id}/total-usage
resource "aws_api_gateway_method" "workspace_id_total_usage-put" {
  resource_id   = aws_api_gateway_resource.workspace_id_total_usage.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  authorization = "NONE"
  http_method   = "PUT"
  api_key_required  = true
}

resource "aws_api_gateway_integration" "workspace_id_total_usage-put" {
  http_method             = aws_api_gateway_method.workspace_id_total_usage-put.http_method
  resource_id             = aws_api_gateway_resource.workspace_id_total_usage.id
  rest_api_id             = aws_api_gateway_rest_api.brh-workspaces-api.id
  type                    = "AWS_PROXY"
  
  integration_http_method = "POST"
  uri                     = module.brh-api-lambda.function_invoke_arn
}

## 
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.workspaces.id,
      aws_api_gateway_method.workspaces-get.id,
      aws_api_gateway_integration.workspaces-get.id,
      aws_api_gateway_integration.workspaces-post.id,
      aws_api_gateway_integration.workspace_id-get.id,
      aws_api_gateway_integration.workspace_id-post.id,
      aws_api_gateway_integration.workspace_id_limits-put.id,
      aws_api_gateway_integration.workspace_id_total_usage-put.id,
      module.workspaces_cors.integration_arn,
      module.workspace_id_cors.integration_arn,
      module.limits_cors.integration_arn,
      module.total_usage_cors.integration_arn,
      module.root_cors.integration_arn,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api" {
  depends_on = [aws_cloudwatch_log_group.bmh-workspaces-api-loggroup]
  stage_name = "api"
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id = aws_api_gateway_rest_api.brh-workspaces-api.id
}


