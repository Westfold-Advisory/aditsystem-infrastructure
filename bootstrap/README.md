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

### Preflight de credenciales locales

Antes de copiar variables o inicializar Terraform, valida la identidad AWS. El
bootstrap necesita una identidad administrativa de la cuenta destino, no el
rol OIDC de GitHub Actions:

```bash
# Si hay credenciales temporales expiradas en la terminal, elimínalas primero.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Para un perfil SSO, renueva la sesión y selecciónalo.
aws sso login --profile aditsystem-admin
export AWS_PROFILE=aditsystem-admin

aws sts get-caller-identity
```

El último comando debe mostrar la cuenta AWS esperada. Si responde
`InvalidClientTokenId`, no continúes con Terraform: renueva la sesión SSO o
configura un perfil válido con `aws configure --profile aditsystem-admin`.

## Pasos

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars`:
- `state_bucket_name`: reemplaza `TU_ACCOUNT_ID` con tu AWS Account ID (`aws sts get-caller-identity --query Account --output text`)
- Ajusta `aws_region` si no usas `mx-central-1`

```bash
terraform init
terraform plan   # revisa que solo crea lo esperado
terraform apply
```

Si el role ya existía y el pipeline falla por permisos AWS, vuelve a ejecutar este bootstrap para que Terraform actualice la policy adjunta al role antes de relanzar `Terraform Apply`.

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
| `AWS_REGION` | La región que usaste (ej. `mx-central-1`) |
| `TF_REMOTE_STATE_ENABLED` | `true` (activa el job `plan-remote` en CI) |
| `TF_BACKEND_REGION` | Región real del bucket de state (ej. `us-east-1`) |

### 4. Crear los GitHub Environments

En **Settings → Environments**:
- `development` — sin restrictions
- `production` — activar *Required reviewers* y limitar a branch `main`
