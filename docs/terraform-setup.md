# Configuración de Terraform — ADITSYSTEM

Guía para bootstrap del **remote state** (S3 + DynamoDB), **OIDC con GitHub Actions** y activación del pipeline.

## 1. Bootstrap del backend (S3 + DynamoDB)

Requiere credenciales AWS con permisos para crear bucket S3 y tabla DynamoDB.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Editar: state_bucket_name = "aditsystem-tf-state-<ACCOUNT_ID>"
terraform init
terraform apply
```

Anota los outputs `state_bucket` y `dynamodb_table`.

## 2. Archivos de backend por entorno

Por cada entorno, copia el ejemplo y rellena valores reales (no versionar):

```bash
cp config/backend-dev.hcl.example config/backend-dev.hcl
cp config/backend-prod.hcl.example config/backend-prod.hcl
```

Ejemplo `config/backend-dev.hcl`:

```hcl
bucket         = "aditsystem-tf-state-123456789012"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "aditsystem-tf-locks"
encrypt        = true
```

Prueba local:

```bash
cd environments/dev
terraform init -backend-config=../../config/backend-dev.hcl
terraform plan
```

## 3. OIDC — GitHub Actions → AWS (recomendado)

Evita access keys estáticas en GitHub Secrets.

### 3.1 Proveedor OIDC en AWS

En IAM → Identity providers → Add provider:

- Provider type: OpenID Connect
- URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### 3.2 Rol IAM para Terraform

Crea un rol con trust policy (ajusta `ORG` y repo):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ervicperezdev/aditsystem-infrastructure:*"
        }
      }
    }
  ]
}
```

Adjunta políticas según lo que Terraform gestione (mínimo para empezar: permisos acotados por entorno; en MVP puedes usar `PowerUserAccess` solo en `dev` y restringir `prod`).

### 3.3 Secrets y variables en GitHub

Ver [github-secrets-checklist.md](./github-secrets-checklist.md).

Cuando estén configurados, activa en el repo:

**Settings → Secrets and variables → Actions → Variables**

| Variable | Valor |
|----------|-------|
| `TF_REMOTE_STATE_ENABLED` | `true` |

Esto habilita el job `plan-remote` en el workflow de CI.

## 4. GitHub Environments

Crea en el repo **Settings → Environments**:

| Environment | Uso |
|-------------|-----|
| `development` | Apply manual a `dev` |
| `production` | Apply a prod — activar *Required reviewers* |

El workflow `terraform-apply.yml` usa `workflow_dispatch` y el environment según el input elegido.

## 5. Pipelines

| Workflow | Disparador | Qué hace |
|----------|------------|----------|
| `terraform-ci.yml` | PR y push a `main` | `fmt`, `validate`, `plan` (local sin AWS; remoto si OIDC listo) |
| `terraform-apply.yml` | Manual | `plan` + `apply` con aprobación por environment |

**Regla:** en PR nunca hay `apply` automático.

## 6. Buenas prácticas

- Un **state key** por entorno (`dev/`, `prod/`).
- Bucket con **versionado** y **cifrado** habilitados (el bootstrap ya lo hace).
- **DynamoDB** para locking — evita corrupción de state concurrente.
- No commitear `*.tfvars`, `config/*.hcl` ni credenciales.
- Preferir **Secrets Manager / SSM** para secretos de aplicación; evitar `TF_VAR_*` de contraseñas en GitHub.
