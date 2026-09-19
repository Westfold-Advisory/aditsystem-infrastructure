# Dominio personalizado de desarrollo

El entorno `dev` habilita los dominios `aditsystem-dev.ervic.pro` (frontend) y `api.aditsystem-dev.ervic.pro` (API) mediante **delegación de subdominio**: sólo se crea una hosted zone de Route53 para `aditsystem-dev.ervic.pro`, sin migrar la zona raíz `ervic.pro`. Esto permite mantener `ervic.pro` en el proveedor DNS actual sin interrupciones.

## Arquitectura

- Route53 administra exclusivamente el subdominio `aditsystem-dev.ervic.pro` y sus registros descendientes (`api.aditsystem-dev.ervic.pro`).
- CloudFront sirve el frontend S3 con HTTPS; su certificado ACM se crea en `us-east-1` por requisito de CloudFront.
- Un ALB regional termina TLS para la API y redirige HTTP a HTTPS. La EC2 sólo admite el puerto 8000 desde el security group del ALB.
- ACM valida los certificados mediante registros DNS dentro de la misma hosted zone.

## Prerequisito: crear la hosted zone en Route53

Antes del primer `terraform apply`, crea **una** hosted zone pública para `aditsystem-dev.ervic.pro` en la cuenta AWS `810626480386`:

1. AWS Console → Route 53 → **Hosted zones** → **Create hosted zone**.
2. Domain name: `aditsystem-dev.ervic.pro`; Type: **Public hosted zone**.
3. Al crearla, Route 53 asignará cuatro registros NS (p. ej. `ns-123.awsdns-45.com`). Cópialos.

## Prerequisito: delegar el subdominio en tu proveedor DNS actual

En el proveedor donde administras `ervic.pro`, agrega cuatro registros NS para el subdominio `aditsystem-dev`:

| Tipo | Nombre         | Valor                        | TTL  |
|------|----------------|------------------------------|------|
| NS   | aditsystem-dev | ns-xxx.awsdns-xx.com.        | 300  |
| NS   | aditsystem-dev | ns-xxx.awsdns-xx.net.        | 300  |
| NS   | aditsystem-dev | ns-xxx.awsdns-xx.org.        | 300  |
| NS   | aditsystem-dev | ns-xxx.awsdns-xx.co.uk.      | 300  |

Sustituye los valores con los NS que Route53 asignó en el paso anterior. No toques ningún otro registro de `ervic.pro`.

Después de esta delegación, Terraform puede crear `aditsystem-dev.ervic.pro` y `api.aditsystem-dev.ervic.pro` automáticamente dentro de esa hosted zone.

## Costos incrementales

Esta configuración añade cargos variables por:

- ALB: horas aprovisionadas y LCU (conexiones, reglas, bytes y solicitudes).
- CloudFront: solicitudes y transferencia de datos a Internet.
- Route53: zona hospedada (~$0.50/mes) y consultas DNS.

Los certificados públicos ACM usados por ALB/CloudFront no tienen cargo adicional. `enable_waf` permanece `false` para no sumar cargos hasta que exista una política WAF aprobada.

## Operación

Los certificados se renuevan automáticamente mientras los registros de validación DNS permanezcan bajo Terraform. No crear registros/certificados manualmente en la consola de Route53.
