A Terraform module to add an OPTIONS method to allow Cross-Origin Resource Sharing (CORS) preflight requests.

## Usage

``` hcl
module "cors" {
  source = "../api-gateway-enable-cors"

  api_id          = "<api_id>"
  api_resource_id = "<api_resource_id>"
}
```
