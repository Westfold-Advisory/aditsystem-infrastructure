# Stack mínimo de desarrollo

`environments/dev` compone el runtime mínimo para ADITSYSTEM:

```mermaid
flowchart LR
  GH[GitHub Actions backend\nEnvironment: development] -->|OIDC: push only| ECR[Private ECR]
  EC2[EC2 t3.micro x86_64\nDocker + SSM, no SSH] -->|pull| ECR
  EC2 -->|5432 only| RDS[(Private RDS PostgreSQL 16)]
  EC2 --> SM[Secrets Manager]
  EC2 --> CW[CloudWatch Logs: 7 days]
  EC2 --> MEDIA[Private encrypted S3 media]
  Internet -->|API :8000, temporary dev exposure| EC2
```

RDS es Single-AZ, cifrado con una CMK dedicada administrada por Terraform, sin acceso público y se distribuye en dos subredes privadas. El motor es PostgreSQL 16, compatible con el uso de PostGIS del backend. Tras crear la base, las migraciones deben habilitar `postgis` con el usuario administrador antes de aplicar el esquema que usa tipos geoespaciales.

No se crea NAT Gateway para desarrollo. La instancia está en una subred pública exclusivamente para obtener actualizaciones, ECR, SSM, Secrets Manager y CloudWatch a través del Internet Gateway; su grupo de seguridad no expone SSH y exige IMDSv2. RDS y S3 de medios no son públicos. El puerto 8000 queda expuesto temporalmente para el flujo público; antes de producción debe sustituirse por ALB/HTTPS y limitarse el origen.

## Entrega backend por GitHub Actions

Después de `terraform apply`, tomar estos outputs de `environments/dev` y definirlos como variables del GitHub Environment `development` en `Westfold-Advisory/aditsystem-backend`:

| Variable | Output |
|---|---|
| `AWS_REGION` | `backend_github_variables.AWS_REGION` |
| `AWS_ECR_REPOSITORY` | `backend_ecr_repository` |
| `AWS_DEPLOY_ROLE_ARN` | `backend_github_deploy_role_arn` |
| `AWS_EC2_INSTANCE_ID` | `backend_instance_id` |
| `AWS_RUNTIME_SECRET_ARN` | `backend_runtime_secret_arn` |
| `AWS_DB_SECRET_ARN` | `database_master_secret_arn` |
| `AWS_MEDIA_BUCKET_NAME` | `media_bucket_name` (presign de descarga TRA-152 → `DOCUMENTS_S3_BUCKET`) |

El trust policy exige exactamente `repo:Westfold-Advisory/aditsystem-backend:environment:development`. El rol sólo puede obtener un token ECR y subir capas/manifiestos al repositorio creado; no puede administrar EC2, secretos ni otros repositorios. No se usan access keys persistentes.

## Secretos y operación

RDS administra la contraseña maestra en Secrets Manager mediante `manage_master_user_password`; su ARN se entrega como output sensible. El secret `${project}-${environment}/backend-runtime` se crea vacío para que las claves JWT y la lista CORS se carguen fuera de Git y del estado Terraform. Nunca registrar su contenido en logs ni variables públicas del frontend.

La EC2 incluye Docker y un instance profile con SSM, lectura del secret runtime y de la contraseña RDS, lectura del ECR propio y escritura únicamente al log group del backend. En el bucket privado de medios puede leer objetos (`GetObject`), listar el bucket y escribir solo bajo `demo/faker/*` (seed QA) y `personas/*` (presign PUT TRA-155); no puede modificar otros prefijos. El bucket define CORS para `GET`/`HEAD`/`PUT` desde el origen del frontend (dominio custom, website S3 y `localhost:5173` en desarrollo local). El rol OIDC del backend puede publicar únicamente en ECR y ejecutar `AWS-RunShellScript` exclusivamente en esta EC2; no puede administrar EC2 ni leer secretos. El despliegue del contenedor y las migraciones se ejecutarán por SSM usando una etiqueta inmutable publicada por el pipeline backend; no se requiere ni se habilita SSH.

Las opciones `enable_alb`, `enable_cloudfront`, `enable_waf`, `enable_custom_dns` y `enable_multi_az` existen con valor `false` por defecto. No crean recursos adicionales hasta que se diseñen esos componentes.
