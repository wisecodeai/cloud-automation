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


# dynamodb_table = dynamodb.Table(
#             self, "bmh-workspace-table",
#             partition_key=dynamodb.Attribute(name="user_id", type=dynamodb.AttributeType.STRING),
#             sort_key=dynamodb.Attribute(name="bmh_workspace_id", type=dynamodb.AttributeType.STRING),
#             billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
#             encryption=dynamodb.TableEncryption.AWS_MANAGED
#         )
