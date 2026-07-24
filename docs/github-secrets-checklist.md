# Checklist — Secrets y variables de GitHub Actions

Repo: `Westfold-Advisory/aditsystem-infrastructure`

Marca cada ítem cuando esté configurado en **Settings → Secrets and variables → Actions**.

## Secrets (repository o por environment)

| Secret | ¿Requerido? | Descripción |
|--------|-------------|-------------|
| `AWS_ROLE_ARN` | Sí (para plan/apply con AWS) | ARN del rol IAM con trust OIDC hacia este repo |
| `TF_VAR_db_password` | No (evitar si es posible) | Solo si no usas Secrets Manager; preferir SSM/Secrets Manager |

## Variables (repository)

| Variable | Ejemplo | Descripción |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | Región por defecto |
| `TF_REMOTE_STATE_ENABLED` | `true` | Activa plan con backend S3 en CI |
| `TF_STATE_BUCKET` | `aditsystem-tf-state-...` | Referencia documental (opcional) |
| `TF_STATE_LOCK_TABLE` | `aditsystem-tf-locks` | Requerida por CI/CD remoto |

## Variables por environment (opcional)

Repite `AWS_ROLE_ARN` por environment si usas roles distintos:

| Environment | Rol sugerido |
|-------------|--------------|
| `development` | Rol con permisos amplios en cuenta dev |
| `production` | Rol mínimo + aprobación manual |

## Environments a crear

- [ ] `development`
- [ ] `production` (con protection rules: reviewers, solo `main`)

## Verificación

1. Abre un PR de prueba → workflow **Terraform CI** en verde (`fmt`, `validate`, `plan-local`).
2. Con OIDC configurado y `TF_REMOTE_STATE_ENABLED=true` → job `plan-remote` en verde.
3. En **Actions → Terraform Apply → Run workflow** → elige `dev` y confirma en environment `development`.

## Variables/secrets que salen de Terraform para el repo frontend

Después de aplicar `environments/prod`, publica estos valores en el repo `Westfold-Advisory/ADITSYSTEM`:

| Tipo | Nombre | Sale de Terraform |
|------|--------|-------------------|
| Secret | `AWS_ROLE_ARN` | output `frontend_deploy_role_arn` |
| Variable | `AWS_REGION` | output `frontend_github_variables.AWS_REGION` |
| Variable | `S3_BUCKET` | output `frontend_github_variables.S3_BUCKET` |
| Variable | `CLOUDFRONT_DISTRIBUTION_ID` | output `frontend_github_variables.CLOUDFRONT_DISTRIBUTION_ID` |
