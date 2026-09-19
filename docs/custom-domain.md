# Dominio personalizado de desarrollo

El entorno `dev` habilita los dominios `aditsystem-dev.ervic.pro` (frontend) y `api.aditsystem-dev.ervic.pro` (API). La zona pública `ervic.pro` debe existir en la misma cuenta AWS antes de aplicar Terraform.

## Arquitectura

- Route53 valida certificados ACM mediante registros DNS y publica alias A.
- CloudFront sirve el frontend S3 con HTTPS; su certificado ACM se crea en `us-east-1` por requisito de CloudFront.
- Un ALB regional termina TLS para la API y redirige HTTP a HTTPS. La EC2 sólo admite el puerto 8000 desde el security group del ALB.

## Costos incrementales

Esta configuración deja de ser la alternativa mínima de desarrollo. Añade cargos variables por:

- ALB: horas aprovisionadas y LCU (conexiones, reglas, bytes y solicitudes).
- CloudFront: solicitudes y transferencia de datos a Internet.
- Route53: zona hospedada y consultas DNS.

Los certificados públicos ACM usados por ALB/CloudFront no tienen cargo adicional. La estimación final depende de tráfico y región; revisar AWS Pricing Calculator antes de aplicar y configurar AWS Budgets/alertas. `enable_waf` permanece `false` para no sumar cargos hasta que exista una política WAF aprobada.

## Operación

Los certificados se renuevan mientras los registros de validación DNS permanezcan bajo Terraform. No crear registros/certificados manualmente. Si `ervic.pro` vive en otra cuenta, delegar el subdominio o pasar el ID de zona como cambio Terraform antes de aplicar.
