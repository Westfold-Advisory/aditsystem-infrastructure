# Bootstrap del remote state + OIDC

Crea de una sola vez todo lo necesario para que el pipeline de CI/CD funcione:

| Recurso AWS | Para qué |
|-------------|----------|
| S3 bucket (versionado + cifrado) | Almacena el Terraform state |
| DynamoDB table | Locking del state (evita corrupción concurrente) |
| OIDC provider (GitHub) | Permite que GitHub Actions asuma roles IAM sin access keys |
| IAM role `aditsystem-terraform-github-actions` | Rol que asume el pipeline para ejecutar Terraform |

## Prerrequisitos

- AWS CLI configurado con credenciales de administrador (`aws sts get-caller-identity`)
- Terraform >= 1.5.0 instalado localmente

## Pasos

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars`:
- `state_bucket_name`: reemplaza `TU_ACCOUNT_ID` con tu AWS Account ID (`aws sts get-caller-identity --query Account --output text`)
- Ajusta `aws_region` si no usas `us-east-1`

```bash
terraform init
terraform plan   # revisa que solo crea lo esperado
terraform apply
```

## Outputs importantes

Tras el apply, copia los outputs para completar la configuración:

```
github_actions_role_arn = "arn:aws:iam::XXXX:role/aditsystem-terraform-github-actions"
backend_config_dev      = (contenido para config/backend-dev.hcl)
backend_config_prod     = (contenido para config/backend-prod.hcl)
```

### 1. Crear los archivos de backend por entorno

```bash
terraform output -raw backend_config_dev  > ../config/backend-dev.hcl
terraform output -raw backend_config_prod > ../config/backend-prod.hcl
```

### 2. Configurar el secret en GitHub

En **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Valor |
|--------|-------|
| `AWS_ROLE_ARN` | Valor del output `github_actions_role_arn` |

### 3. Configurar las variables en GitHub

En **Settings → Secrets and variables → Actions → Variables**:

| Variable | Valor |
|----------|-------|
| `AWS_REGION` | La región que usaste (ej. `us-east-1`) |
| `TF_REMOTE_STATE_ENABLED` | `true` (activa el job `plan-remote` en CI) |

### 4. Crear los GitHub Environments

En **Settings → Environments**:
- `development` — sin restrictions
- `production` — activar *Required reviewers* y limitar a branch `main`
