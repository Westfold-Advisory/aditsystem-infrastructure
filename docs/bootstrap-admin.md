# Bootstrap del primer administrador de desarrollo

Terraform administra sólo el contenedor del secreto `aditsystem-dev/bootstrap-admin`.
No existe un recurso `aws_secretsmanager_secret_version`: la contraseña se genera
en la EC2 al ejecutar la operación SSM y, por tanto, no llega a Terraform state,
plans, outputs, GitHub Actions ni Git.

El secreto conserva la contraseña inicial exclusivamente como JSON:

```json
{"email":"eperez@ervic.pro","full_name":"Administrador","password":"...","role":"ADMIN"}
```

No consulte ni copie este valor a terminales, tickets o logs. El instance profile
de la EC2 es el único principal con `GetSecretValue` para este ARN. Sólo ese mismo
perfil puede añadir el valor inicial con `PutSecretValue`; los roles OIDC de GitHub
Actions y los buckets S3 no reciben permisos sobre el secreto.

## Operación única mediante SSM

Precondiciones:

- Se aplicó `environments/dev` y la imagen del backend ya está desplegada.
- La imagen contiene `scripts/create_superuser.py`. En el commit actual del
  backend ese script existe en el repositorio pero no se copia al Dockerfile;
  el cambio de backend correspondiente debe incorporar el script antes de
  ejecutar esta operación.
- El operador usa una sesión federada/SSO autorizada para `ssm:SendCommand`;
  no se usan access keys permanentes ni SSH.

Desde una estación autorizada, reemplace sólo el identificador público de la EC2
y ejecute una vez. El archivo de parámetros versionado contiene instrucciones,
nunca la contraseña; ésta se genera dentro de la instancia. El comando no
contiene ni imprime la contraseña:

```bash
aws ssm send-command \
  --region mx-central-1 \
  --instance-ids i-REPLACE_WITH_BACKEND_INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --comment 'Bootstrap one-time development ADMIN' \
  --parameters file://scripts/bootstrap-admin-ssm-parameters.json
```

La ejecución es idempotente respecto al secreto: si ya tiene valor, no genera ni
sobrescribe una contraseña. El script de backend aborta funcionalmente si el
usuario ya existe; revise el estado del comando SSM sin solicitar su salida si no
es necesaria, porque el secreto no debe propagarse a registros operativos.

La política solicitada impide que un operador lea este secreto. Por ello, antes
de ejecutar el bootstrap el Product Owner debe aprobar el mecanismo separado con
el que `eperez@ervic.pro` recibirá una credencial inicial o completará un reset de
contraseña. El backend actual no implementa entrega ni restablecimiento seguro;
no se ha añadido un acceso alternativo al secreto para eludir esa restricción.

Después de que el administrador haya iniciado sesión y cambiado la contraseña,
elimine o programe la eliminación del secreto bajo el procedimiento de cambios
aprobado. Terraform usa una ventana de recuperación de siete días para permitir
esa operación. Para rebootstrap controlado, recupere/elimine primero el secreto
y ejecute de nuevo la operación sólo con aprobación; no hay endpoint público.
