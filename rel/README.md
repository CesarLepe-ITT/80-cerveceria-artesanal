# Release y despliegue

Este documento explica cómo construir, ejecutar y operar el release de
`p80_cerveceria_artesanal`.

## 1. Construir el release

```bash
rebar3 compile
rebar3 eunit
rebar3 release
```

La salida queda en:

```
_build/default/rel/p80_cerveceria_artesanal/
```

La configuración de relx está en `rebar.config`:

- Release: `p80_cerveceria_artesanal` versión `0.1.0`.
- Aplicaciones incluidas: la aplicación propia, `sasl` y `recon`; relx agrega las
  dependencias transitivas (`cowboy`, `ranch`, `cowlib`, `jsx`, etc.).
- `sys.config`: `config/sys.config`.
- `vm.args`: `config/vm.args`.
- Modo `prod`.

## 2. Ejecutar manualmente

```bash
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal foreground
```

Comandos útiles del script de release:

```bash
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal foreground
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal start
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal stop
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal status
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal console
```

Verificación:

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:8080/api/metricas
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/
```

## 3. Instalación con systemd

Se incluye una unidad de ejemplo:

```bash
deploy/cerveceria-artesanal.service
```

Pasos sugeridos en el servidor:

```bash
# 1. Crear el usuario de servicio.
sudo useradd --system \
  --home /opt/cerveceria-artesanal \
  --shell /usr/sbin/nologin \
  cerveceria

# 2. Copiar el release ya construido.
sudo mkdir -p /opt/cerveceria-artesanal
sudo cp -a _build/default/rel/p80_cerveceria_artesanal/. /opt/cerveceria-artesanal/
sudo chown -R cerveceria:cerveceria /opt/cerveceria-artesanal

# 3. Instalar la unidad.
sudo cp deploy/cerveceria-artesanal.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cerveceria-artesanal

# 4. Revisar estado y logs.
sudo systemctl status cerveceria-artesanal
sudo journalctl -u cerveceria-artesanal -f
```

La unidad está preparada para:

- `Type=simple` con el comando `foreground`.
- Reinicio automático en fallo.
- Límite alto de descriptores.
- `ProtectSystem=full`, `ProtectHome=true` y `PrivateTmp=true`.
- Escritura permitida solo bajo `/opt/cerveceria-artesanal`.

Ajusta `User`, `Group`, `WorkingDirectory`, `ExecStart` y las rutas si instalas en
otro directorio.

## 4. Configuración de producción

### Puerto y tiempos

Edita `config/sys.config` **antes** de construir el release, o modifica el
`sys.config` copiado dentro del release:

```
releases/0.1.0/sys.config
```

Variables relevantes:

```erlang
{p80_cerveceria_artesanal, [
    {http_port, 8080},
    {control_temperatura_ms, 5000},
    {sse_heartbeat_ms, 15000},
    {max_eventos, 500},
    {tolerancia_temperatura, 1.0}
]}.
```

Para pruebas HTTP con puerto efímero se usa `http_port = 0`.

### Nodo y cookie

Revisa `config/vm.args`:

```
-name p80_cerveceria_artesanal@127.0.0.1
-setcookie cambiar_en_produccion
```

Cambia la cookie antes de exponer el nodo. Si usas un nombre DNS o una IP fija,
ajusta el nombre del nodo.

## 5. Operación

- El panel y la API escuchan en `http_port` (8080 por defecto).
- No hay autenticación: publica el puerto solo en la red interna o colócalo detrás
  de un proxy con autenticación.
- El estado vive en ETS y se pierde al reiniciar el nodo.
- Los eventos también viven en memoria y se recortan a `max_eventos`.
- No hay respaldo persistente; si se necesita, habría que agregar una base de datos
  o snapshots a disco.

## 6. Actualización

Para desplegar una versión nueva:

```bash
rebar3 release
sudo systemctl stop cerveceria-artesanal
sudo cp -a _build/default/rel/p80_cerveceria_artesanal/. /opt/cerveceria-artesanal/
sudo chown -R cerveceria:cerveceria /opt/cerveceria-artesanal
sudo systemctl start cerveceria-artesanal
```

Al reiniciar se pierde el estado en memoria. Si se requiere conservar datos, hay
que implementar persistencia antes de usar el sistema en producción real.

## 7. Diagnóstico

- Salud y uptime: `GET /health`.
- Diagnóstico con memoria y procesos: `GET /api/diagnostico`.
- Métricas Prometheus: `GET /metrics`.
- Bitácora: `GET /api/eventos?limite=100`.
- SSE: `GET /api/eventos/sse` con `curl -N`.
- Logs del servicio: `journalctl -u cerveceria-artesanal -f`.

Si el release no arranca:

1. Revisa que el puerto no esté ocupado: `ss -ltnp | grep 8080`.
2. Verifica la cookie y el nombre del nodo en `vm.args`.
3. Comprueba permisos del usuario `cerveceria` sobre el directorio del release.
4. Ejecuta en primer plano para ver el error:
   `/opt/cerveceria-artesanal/bin/p80_cerveceria_artesanal foreground`.
