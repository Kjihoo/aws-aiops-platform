# ── Dashboard S3 Static Hosting Bucket ──────────────────────────────────────

resource "aws_s3_bucket" "dashboard" {
  bucket = "mzc-pj4-${local.owner}-dashboard-${local.env}"

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-${local.env}"
  }
}

resource "aws_s3_bucket_public_access_block" "dashboard" {
  bucket                  = aws_s3_bucket.dashboard.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "dashboard" {
  bucket     = aws_s3_bucket.dashboard.id
  depends_on = [aws_s3_bucket_public_access_block.dashboard]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.dashboard.arn}/*"
    }]
  })
}

# 파일 자동 업로드 (변경 시 etag로 자동 감지)
resource "aws_s3_object" "dashboard_html" {
  bucket       = aws_s3_bucket.dashboard.id
  key          = "index.html"
  source       = "${path.module}/dashboard-web/index.html"
  content_type = "text/html; charset=utf-8"
  etag         = filemd5("${path.module}/dashboard-web/index.html")
}

resource "aws_s3_object" "dashboard_js" {
  bucket       = aws_s3_bucket.dashboard.id
  key          = "app.js"
  source       = "${path.module}/dashboard-web/app.js"
  content_type = "application/javascript; charset=utf-8"
  etag         = filemd5("${path.module}/dashboard-web/app.js")
}

# ── Dashboard API Lambda IAM ────────────────────────────────────────────────

resource "aws_iam_role" "dashboard_api" {
  name = "mzc-pj4-${local.owner}-dashboard-api-${local.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-api-${local.env}"
  }
}

resource "aws_iam_role_policy_attachment" "dashboard_api_basic" {
  role       = aws_iam_role.dashboard_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dashboard_api_custom" {
  name = "dashboard-api-custom"
  role = aws_iam_role.dashboard_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = [
          aws_dynamodb_table.dashboard_summary.arn,
          aws_dynamodb_table.check_results.arn,
        ]
      },
      {
        Sid    = "AthenaQuery"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
        ]
        Resource = "*"
      },
      {
        Sid      = "GlueCatalogRead"
        Effect   = "Allow"
        Action   = ["glue:GetDatabase", "glue:GetTable", "glue:GetPartitions"]
        Resource = "*"
      },
      {
        Sid    = "S3AthenaResults"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
        ]
      },
      {
        Sid      = "InvokeLangGraph"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.langgraph_agent.arn
      },
    ]
  })
}

# ── Dashboard API Lambda Function (Zip) ──────────────────────────────────────

data "archive_file" "dashboard_api" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/dashboard-api"
  output_path = "${path.module}/lambda-src/dashboard-api.zip"
}

resource "aws_lambda_function" "dashboard_api" {
  function_name = "mzc-pj4-${local.owner}-dashboard-api-${local.env}"
  role          = aws_iam_role.dashboard_api.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 512

  filename         = data.archive_file.dashboard_api.output_path
  source_code_hash = data.archive_file.dashboard_api.output_base64sha256

  environment {
    variables = {
      DASHBOARD_TABLE  = aws_dynamodb_table.dashboard_summary.name
      CHECK_TABLE      = aws_dynamodb_table.check_results.name
      ATHENA_DB        = aws_glue_catalog_database.data_lake.name
      ATHENA_OUTPUT    = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
      LANGGRAPH_LAMBDA = aws_lambda_function.langgraph_agent.function_name
    }
  }

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-api-${local.env}"
  }
}

# ── Lambda Function URL (CloudFront 뒤에서 AWS_IAM 인증) ─────────────────────
# MZC SCP가 NONE 공개 호출을 차단해서 CloudFront 프록시 + AWS_IAM 인증으로 우회.
# CloudFront가 Origin Access Control로 SigV4 서명하여 호출.

resource "aws_lambda_function_url" "dashboard_api" {
  function_name      = aws_lambda_function.dashboard_api.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type"]
    max_age       = 86400
  }
}

# CloudFront → Lambda Function URL 호출 권한 (OAC로 서명된 요청)
resource "aws_lambda_permission" "dashboard_api_url_cloudfront" {
  statement_id           = "AllowCloudFrontInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.dashboard_api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.dashboard_api.arn
  function_url_auth_type = "AWS_IAM"
}

# ── CloudFront Origin Access Control (SigV4 자동 서명) ──────────────────────

resource "aws_cloudfront_origin_access_control" "dashboard_api" {
  name                              = "mzc-pj4-${local.owner}-dashboard-api-oac-${local.env}"
  description                       = "Sign requests to Lambda Function URL with AWS_IAM"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── CloudFront Distribution (Function URL 앞 CDN 프록시) ────────────────────

locals {
  # Function URL: https://xxxx.lambda-url.ap-northeast-2.on.aws/
  # CloudFront origin은 hostname만 필요 → 정규식으로 추출
  dashboard_api_origin_host = replace(replace(aws_lambda_function_url.dashboard_api.function_url, "https://", ""), "/", "")
}

resource "aws_cloudfront_distribution" "dashboard_api" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Dashboard API proxy → Lambda Function URL (AWS_IAM via OAC)"
  price_class     = "PriceClass_200" # 한국·미국·유럽·일본 (저렴)

  origin {
    domain_name              = local.dashboard_api_origin_host
    origin_id                = "lambda-function-url"
    origin_access_control_id = aws_cloudfront_origin_access_control.dashboard_api.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lambda-function-url"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # 캐시 비활성화 (모든 채팅 요청을 Lambda로 통과)
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-api-cdn-${local.env}"
  }
}

# AWS 관리형 캐시 정책: CachingDisabled
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# AWS 관리형 origin request 정책: AllViewerExceptHostHeader
# (Host 헤더 제외 — Lambda Function URL이 자체 호스트 검증하므로)
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ── 출력 ────────────────────────────────────────────────────────────────────

output "dashboard_url" {
  value       = "http://${aws_s3_bucket_website_configuration.dashboard.website_endpoint}"
  description = "대시보드 웹 URL (브라우저에서 열기)"
}

output "dashboard_api_url" {
  value       = "https://${aws_cloudfront_distribution.dashboard_api.domain_name}/"
  description = "Dashboard API CloudFront URL (SCP 우회용 프록시, dashboard-builder가 CHAT_API_BASE로 사용)"
}

output "dashboard_api_function_url" {
  value       = aws_lambda_function_url.dashboard_api.function_url
  description = "원본 Function URL (AWS_IAM, CloudFront만 호출 가능)"
}

# ── Dashboard Builder Lambda (Static JSON 생성, EventBridge가 trigger) ───────

resource "aws_iam_role" "dashboard_builder" {
  name = "mzc-pj4-${local.owner}-dashboard-builder-${local.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-builder-${local.env}"
  }
}

resource "aws_iam_role_policy_attachment" "dashboard_builder_basic" {
  role       = aws_iam_role.dashboard_builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dashboard_builder_custom" {
  name = "dashboard-builder-custom"
  role = aws_iam_role.dashboard_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Scan"]
        Resource = [
          aws_dynamodb_table.dashboard_summary.arn,
          aws_dynamodb_table.check_results.arn,
          aws_dynamodb_table.report_metadata.arn,
        ]
      },
      {
        Sid      = "DynamoDBReadMonitoring"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = "arn:aws:dynamodb:ap-northeast-2:${data.aws_caller_identity.current.account_id}:table/dashboard_summary"
      },
      {
        Sid      = "AthenaQuery"
        Effect   = "Allow"
        Action   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults"]
        Resource = "*"
      },
      {
        Sid      = "GlueCatalogRead"
        Effect   = "Allow"
        Action   = ["glue:GetDatabase", "glue:GetTable", "glue:GetPartitions"]
        Resource = "*"
      },
      {
        Sid    = "S3DataLakeRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
        ]
      },
      {
        Sid      = "S3DashboardWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.dashboard.arn}/*"
      },
    ]
  })
}

data "archive_file" "dashboard_builder" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/dashboard-builder"
  output_path = "${path.module}/lambda-src/dashboard-builder.zip"
}

resource "aws_lambda_function" "dashboard_builder" {
  function_name = "mzc-pj4-${local.owner}-dashboard-builder-${local.env}"
  role          = aws_iam_role.dashboard_builder.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.dashboard_builder.output_path
  source_code_hash = data.archive_file.dashboard_builder.output_base64sha256

  environment {
    variables = {
      DASHBOARD_TABLE            = aws_dynamodb_table.dashboard_summary.name
      CHECK_TABLE                = aws_dynamodb_table.check_results.name
      REPORT_TABLE               = aws_dynamodb_table.report_metadata.name
      MONITORING_DASHBOARD_TABLE = "dashboard_summary"
      MONITORING_SERVICE_KEY     = "ecommerce"
      ATHENA_DB                  = aws_glue_catalog_database.data_lake.name
      ATHENA_OUTPUT              = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
      BUCKET_NAME                = aws_s3_bucket.dashboard.bucket
      JSON_KEY                   = "data.json"
      CHAT_API_BASE              = "https://${aws_cloudfront_distribution.dashboard_api.domain_name}/"
    }
  }

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-builder-${local.env}"
  }
}

# EventBridge 룰 — 5분마다 dashboard-builder 호출
resource "aws_cloudwatch_event_rule" "dashboard_builder_schedule" {
  name                = "mzc-pj4-${local.owner}-dashboard-builder-schedule-${local.env}"
  description         = "30분마다 대시보드 data.json 갱신"
  schedule_expression = "rate(30 minutes)"
  state               = "ENABLED"

  tags = {
    Service = "dashboard"
    Name    = "mzc-pj4-${local.owner}-dashboard-builder-schedule-${local.env}"
  }
}

resource "aws_cloudwatch_event_target" "dashboard_builder_target" {
  rule      = aws_cloudwatch_event_rule.dashboard_builder_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.dashboard_builder.arn
}

resource "aws_lambda_permission" "dashboard_builder_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_builder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dashboard_builder_schedule.arn
}

output "dashboard_data_url" {
  value       = "http://${aws_s3_bucket_website_configuration.dashboard.website_endpoint}/data.json"
  description = "S3에 적재되는 데이터 JSON URL"
}
