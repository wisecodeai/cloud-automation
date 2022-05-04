# Inject credentials via the AWS_PROFILE environment variable and shared credentials file
# and/or EC2 metadata service
terraform {
  backend "s3" {
    encrypt = "true"
  }
  required_providers {
    aws = "<= 3.37.0"
  }
}

locals {
    account_id = data.aws_caller_identity.current.account_id
    region     = data.aws_region.current.name
}

# The Cost and Usage report
resource "aws_cur_report_definition" "kubecost-cur" {
  report_name                = "${var.vpc_name}-cur"
  s3_prefix                  = var.vpc_name
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur-bucket.id
  s3_region                  = "us-east-1"
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
  depends_on                 = [aws_s3_bucket_policy.cur-bucket-policy]
}

# The bucket used by the Cost and Usage report
resource "aws_s3_bucket" "cur-bucket" {
  bucket = "${var.vpc_name}-cur-bucket"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "${var.vpc_name}-cur-bucket"
    Environment = var.vpc_name
    Purpose     = "Cost and Usage report bucket for use by Kubecost"
  }

}


# The Policy attached to the Cost and Usage report
resource "aws_s3_bucket_policy" "cur-bucket-policy" {
  bucket = aws_s3_bucket.cur-bucket.id
  policy =jsonencode({
    Version = "2008-10-17"
    Id = "Policy1335892530063"
    Statement = [
      {
        Sid = "Stmt1335892150622"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = ["s3:GetBucketAcl","s3:GetBucketPolicy"]
        Resource = "arn:aws:s3:::${aws_s3_bucket.cur-bucket.id}"
        Condition = {
        StringEquals = {
          "aws:SourceArn" = "arn:aws:cur:us-east-1:${local.account_id}:definition/*"
          "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid = "Stmt1335892526596"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "arn:aws:s3:::${aws_s3_bucket.cur-bucket.id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cur:us-east-1:${local.account_id}:definition/*"
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# An IAM user used to connect kubecost to CUR/Glue/Athena
resource "aws_iam_user" "kubecost-user" {
  name = "${var.vpc_name}-kubecost-user"

  tags = {
    Environment = var.vpc_name
    Purpose     = "Kubecost user with access to Cost and Usage report"
  }
}

# Access Key for the user
resource "aws_iam_access_key" "kubecost-user-key" {
  user = aws_iam_user.kubecost-user.name
}

# Policy to attach to the user
resource "aws_iam_policy" "kubecost-user-policy" {
  name        = "${var.vpc_name}-Kubecost-CUR-policy"
  path        = "/"
  description = "Policy for Kubecost to access CUR report and resources associated with it."

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
          Sid = "AthenaAccess"
          Effect = "Allow"
          Action = ["athena:*"]
          Resource = ["*"]
      },
      {
        Sid = "ReadAccessToAthenaCurDataViaGlue"
        Effect = "Allow"
        Action = ["glue:GetDatabase*","glue:GetTable*","glue:GetPartition*","glue:GetUserDefinedFunction","glue:BatchGetPartition"]
        Resource = ["arn:aws:glue:*:*:catalog","arn:aws:glue:*:*:database/athenacurcfn*","arn:aws:glue:*:*:table/athenacurcfn*/*"]
      },
      {
        Sid = "AthenaQueryResultsOutput"
        Effect = "Allow"
        Action = ["s3:GetBucketLocation","s3:GetObject","s3:ListBucket","s3:ListBucketMultipartUploads","s3:ListMultipartUploadParts","s3:AbortMultipartUpload","s3:CreateBucket","s3:PutObject"]
        Resource = ["arn:aws:s3:::aws-athena-query-results-*"]
      },
      {
        Sid = "S3ReadAccessToAwsBillingData"
        Effect = "Allow"
        Action = ["s3:Get*","s3:List*"]
        Resource = ["arn:aws:s3:::${aws_s3_bucket.cur-bucket.id}*"]
      }
    ]
  })
}

# Policy attachment of the kubecost user policy to the kubecost user
resource "aws_iam_user_policy_attachment" "kubecost-user-policy-attachment" {
  user       = aws_iam_user.kubecost-user.name
  policy_arn = aws_iam_policy.kubecost-user-policy.arn
}





# Role for the glue crawler
resource "aws_iam_role" "glue-crawler-role" {
  name = "AWSCURCrawlerComponentFunction-${var.vpc_name}"
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
            Service = "glue.amazonaws.com"
          }
      }
    ]
  })

  inline_policy {
    name = "AWSCURCrawlerComponentFunction"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
          Effect = "Allow"
        },
        {
          Action = ["glue:UpdateDatabase","glue:UpdatePartition","glue:CreateTable","glue:UpdateTable","glue:ImportCatalogToGlue"]
          Resource = "*"
          Effect = "Allow"
        },
        {
          Action = ["s3:GetObject","s3:PutObject"]
          Resource = "arn:aws:s3:::${aws_s3_bucket.cur-bucket.id}/${var.vpc_name}/${var.vpc_name}-cur/test-cur*"
          Effect = "Allow"
        }
      ]
    })
  }      

  inline_policy {
    name = "AWSCURKMSDecryption"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = ["kms:Decrypt"]
          Resource = "*"
          Effect = "Allow"
        }
      ]
    })
  }
}


# Role for the cur initializer lambda
resource "aws_iam_role" "cur-initializer-lambda-role" {
  name = "AWSCURCrawlerLambdaExecutor-${var.vpc_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        } 
      }
    ]
  })

  inline_policy {
    name = "AWSCURCrawlerLambdaExecutor"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
          Effect = "Allow"
        },
        {
          Action = ["glue:StartCrawler"]
          Resource = "*"
          Effect = "Allow"
        }
      ]
    })     
  }
}

# Role for the s3 notification lambda
resource "aws_iam_role" "cur-s3-notification-lambda-role" {
  name = "AWSS3CURLambdaExecutor-${var.vpc_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        } 
      }
    ]
  })

  inline_policy {
    name = "AWSS3CURLambdaExecutor"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
          Effect = "Allow"
        },
        {
          Action = ["s3:PutBucketNotification"]
          Resource = "arn:aws:s3:::${aws_s3_bucket.cur-bucket.id}"
          Effect = "Allow"
        }
      ]
    })
  }
}


# Glue database
resource "aws_glue_catalog_database" "cur-glue-database" {
  name          = "athenacurcfn_${var.vpc_name}"
}

# Glue crawler
resource "aws_glue_crawler" "cur-glue-crawler" {
  database_name = aws_glue_catalog_database.cur-glue-database.name
  name          = "${var.vpc_name}-AWSCURCrawler"
  description   = "A recurring crawler that keeps your CUR table in Athena up-to-date."
  role          = aws_iam_role.glue-crawler-role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.cur-bucket.id}/${var.vpc_name}/${var.vpc_name}-cur/test-cur"
    exclusions = ["**.json","**.yml","**.sql","**.csv","**.gz","**.zip"]
  }
}

# Glue catalog table
resource "aws_glue_catalog_table" "cur-glue-catalog" {
  database_name = aws_glue_catalog_database.cur-glue-database.name
  name          = "${var.vpc_name}-cur"
  table_type    = "EXTERNAL_TABLE"


  storage_descriptor {
    location      = "s3://${aws_s3_bucket.cur-bucket.id}/${var.vpc_name}/${var.vpc_name}-cur/test-cur"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "status"
      type = "string"
    }
  }
}

# Lambdas for the CUR to run
resource "aws_lambda_function" "cur-initializer-lambda" {
  filename         = "${path.module}/AWSCURInitializer.zip"
  function_name    = "${var.vpc_name}-AWSCURInitializer"
  role             = aws_iam_role.cur-initializer-lambda-role.arn
  handler          = "index.handler"
  timeout          = "30"
  source_code_hash = filebase64sha256("${path.module}/AWSCURInitializer.zip")
  runtime          = "nodejs12.x"
}

resource "aws_lambda_permission" "cur-initializer-lambda-permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cur-initializer-lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.cur-bucket.arn
}

resource "aws_lambda_function" "cur-s3-notification-lambda" {
  filename         = "${path.module}/AWSS3CURNotification.zip"
  function_name    = "${var.vpc_name}-AWSS3CURNotification"
  role             = aws_iam_role.cur-s3-notification-lambda-role.arn
  handler          = "index.handler"
  timeout          = "30"
  source_code_hash = filebase64sha256("${path.module}/AWSS3CURNotification.zip")
  runtime          = "nodejs12.x"

  environment {
    variables = {
      crawlerName = aws_glue_crawler.cur-glue-crawler.name
    }
  }
}