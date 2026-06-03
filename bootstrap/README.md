# Bootstrap del remote state

Ejecutar **una sola vez** antes de usar el backend S3 en CI/CD.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Editar state_bucket_name (debe ser único globalmente)

terraform init
terraform plan
terraform apply
```

Copia los outputs a `config/backend-<env>.hcl` (desde los `.example`).
