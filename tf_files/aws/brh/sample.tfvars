create_table = true
name = "bmh-workspace-table"
hash_key = "user_id"
range_key = "bmh_workspace_id"
billing_mode = "PAY_PER_REQUEST"
attributes = [
    {name = "user_id", type="S"},
    {name = "bmh_workspace_id", type="S"}
]
server_side_encryption_enabled = true


api_lambda_source_path = "/home/ubuntu/BMH-admin-portal/bmh_admin_portal_backend/lambda/workspaces_api_resource/workspaces_api_resource_handler.py"
infra_lambda_source_path = "/home/ubuntu/BMH-admin-portal/bmh_admin_portal_backend/lambda/deploy_brh_infra/deploy_brh_infra.py"
portal_source_dir = "/home/ubuntu/BMH-admin-portal/bmh_admin_portal_ui/"
domain_name = "brh.planx-pla.net"
aws_acm_certificate = "arn:aws:acm:us-east-1:xxx:certificate/59e2d070-52f9-44e4-92a7-25029c03eb2d"
