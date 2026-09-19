# Rendimiento y seguridad del CI de Terraform

## Línea base

Medición tomada el 2026-09-19 sobre ejecuciones exitosas recientes del workflow
`Terraform CI`, desde la hora de creación hasta la finalización:

| Evento | Runs | Duración observada | Referencia |
| --- | --- | --- | --- |
| PR | 35440485320, 35438877648, 35432975549, 35428057328, 35427727487 | 48–55 s (mediana: 52 s) | historial de Actions del repositorio |
| Push a `main` | 35438961856, 35433139768, 35422985152 | 54–56 s (mediana: 55 s) | historial de Actions del repositorio |

La línea base evidencia que el push posterior al merge repetía los planes ya
revisados en el PR. Una ejecución excepcional no se usa para esta referencia:
el run 35434183370 duró 7 min 08 s.

## Cambio y señal conservada

- En cada PR se conservan `fmt`, `validate` para `dev` y `prod`, y el plan
  remoto con AWS cuando está habilitado el estado remoto. El antiguo plan
  "local" se elimina: con un bloque `backend "s3"`, `init -backend=false`
  permite validar proveedores pero no inicializa un backend sobre el que
  `terraform plan` pueda operar. El pipeline previo ocultaba ese error al
  canalizar el comando por `tee` sin `pipefail`; por tanto no era una señal de
  aprobación válida y duplicaba el plan remoto autorizado.
- En `main` se conservan `fmt` y `validate`; se eliminan los planes duplicados.
  El apply sigue siendo manual, protegido por GitHub Environment, y siempre
  crea un plan nuevo para el SHA que se va a aplicar. Un plan de PR no se
  publica como artefacto ni se reutiliza.
- Los proveedores se cachean por sistema operativo, versión de Terraform,
  directorio de entorno y hash de su `.terraform.lock.hcl`. El caché contiene
  únicamente `TF_PLUGIN_CACHE_DIR`; no incluye `.terraform`, backend/state,
  `tfplan`, credenciales ni secretos.
- Las ejecuciones obsoletas del mismo PR se cancelan. Los applies se serializan
  por entorno y nunca se cancelan mientras están en curso.

Los planes ya no se copian a comentarios de PR. El job deja sólo un resultado
de cambios/sin cambios y Terraform conserva el enmascaramiento de valores
sensibles en sus logs. Esto evita exponer detalles del plan en comentarios
persistentes.

## Cómo medir la mejora

Después de mergear este cambio, comparar al menos cinco ejecuciones exitosas
de cada evento con la línea base usando GitHub Actions (tiempo desde
`created_at` hasta `updated_at`). Registrar mediana y rango. Se espera que los
pushes a `main` finalicen antes al omitir los planes duplicados; los PRs se
benefician del caché cuando el lockfile no cambie. No se promete un porcentaje fijo: la
descarga inicial del caché y la disponibilidad de runners afectan cada run.
