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

`bootstrap/` no tiene bloque `backend` intencionalmente: es el primer estado
y crea el bucket S3 que será el backend remoto de `environments/dev` y
`environments/prod`. Su estado queda inicialmente en
`bootstrap/terraform.tfstate`; consérvalo y no lo subas a Git.

El rol OIDC recibe políticas administradas separadas para la infraestructura
base y para dominios personalizados. Esta separación evita el límite de 6,144
caracteres que IAM aplica a cada documento de policy administrada.

Para la cuenta `810626480386`, la plantilla contiene los valores correctos:

```bash
git checkout main && git pull
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

El archivo copiado queda así; no se requieren `-var` ni secretos:

```hcl
aws_region        = "mx-central-1"
project_name      = "aditsystem"
state_bucket_name = "aditsystem-tf-state-810626480386"
github_org        = "Westfold-Advisory"
github_repo       = "aditsystem-infrastructure"
```

`state_bucket_name` debe ser globalmente único. Si AWS informa que ya existe,
no elijas otro nombre sin antes confirmar que no corresponde al state existente
del proyecto. Para un primer bootstrap de esta cuenta, el valor mostrado es el
nombre previsto. En ejecuciones posteriores vuelve a usar el mismo directorio
y su `terraform.tfstate` local: este state es distinto del de `dev`.

Si el role ya existía y el pipeline falla por permisos AWS, actualiza el
bootstrap desde `main` y ejecuta su `terraform apply` una vez para que
Terraform actualice la policy adjunta al role antes de relanzar `Terraform
Apply`. Por ejemplo, el uso de Route 53/ACM/ALB/CloudFront para dominios
personalizados necesita esta actualización previa. El bootstrap requiere una
identidad administrativa; no se puede reparar el permiso usando el mismo rol
OIDC que recibió el `AccessDenied`.

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

Configura estas variables de repositorio en GitHub con los outputs/valores del
bootstrap antes de ejecutar el workflow remoto:

| Variable | Valor |
|----------|-------|
| `AWS_REGION` | `mx-central-1` |
| `TF_STATE_BUCKET` | `aditsystem-tf-state-810626480386` |
| `TF_BACKEND_REGION` | `mx-central-1` |
| `TF_REMOTE_STATE_ENABLED` | `true` |

### 2. Configurar las variables en GitHub

En **Settings → Secrets and variables → Actions → Variables**:

| Variable | Valor |
|----------|-------|
| `AWS_REGION` | La región que usaste (ej. `mx-central-1`) |
| `TF_REMOTE_STATE_ENABLED` | `true` (activa el job `plan-remote` en CI) |
| `TF_BACKEND_REGION` | Región real del bucket de state (ej. `us-east-1`) |

El workflow de infraestructura declara el ARN del rol OIDC creado por el
bootstrap. No se necesita guardar ese ARN como secret; no contiene una
credencial. El output `github_actions_role_arn` sirve para auditar el valor.

### 3. Crear los GitHub Environments

En **Settings → Environments**:
- `development` — sin restrictions
- `production` — activar *Required reviewers* y limitar a branch `main`
