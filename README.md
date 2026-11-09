# Cervecería Artesanal — Proyecto final Erlang/OTP

Sistema de administración de producción para una cervecería artesanal. Modela lotes,
fermentadores, etapas de producción, control de temperatura, alertas y métricas con
Erlang/OTP, Cowboy, ETS y una interfaz web en tiempo real mediante Server-Sent Events.

**Estado del proyecto:** `rebar3 compile` y `rebar3 eunit` en verde (24 pruebas).
El release de producción también fue probado (`rebar3 release`).

---

## 1. Dominio

Cada lote recorre las etapas:

```
molienda -> coccion -> fermentacion -> maduracion -> envasado -> terminado
```

Reglas principales:

- Un lote solo puede avanzar a la etapa inmediata siguiente.
- Al entrar a `fermentacion` se asigna un fermentador libre con capacidad suficiente.
  La asignación puede ser automática o explícita con `fermentador_id`.
- Un fermentador solo puede tener un lote asignado.
- Al entrar a `envasado` se libera el fermentador para el siguiente lote.
- Un lote queda `en_riesgo` si su fermentador sale de tolerancia o si cae el proceso
  de control de temperatura.
- Si la temperatura vuelve a la tolerancia, el lote se normaliza automáticamente.
- `litros_producidos` es la suma de litros de los lotes en `terminado`.

### Escenario de demostración

`p80_demo:escenario/0` crea:

- 5 recetas.
- 6 fermentadores con capacidades de 600 a 2 000 litros.
- 12 lotes distribuidos entre las seis etapas.
- 3 lotes terminados, 4 en fermentación, 2 en maduración, 2 en cocción y 1 en molienda.

`p80_demo:perder_frio/2` fuerza una desviación de temperatura para simular la falla
del escenario: “un fermentador pierde frío y sube 5 °C en una noche”.

---

## 2. Arranque rápido

Requisitos verificados en este entorno:

- Erlang/OTP 25 (ERTS 13.2)
- Rebar3 3.20.0
- Acceso a Hex para dependencias (`cowboy`, `jsx`, `recon`)

```bash
rebar3 compile
rebar3 eunit
rebar3 shell
```

Con la aplicación iniciada, abre:

- Panel web: <http://localhost:8080/>
- Salud: <http://localhost:8080/health>
- Métricas JSON: <http://localhost:8080/api/metricas>
- Métricas Prometheus: <http://localhost:8080/metrics>

Dentro de la shell de Erlang:

```erlang
%% Crear el escenario completo de demostración.
p80_demo:escenario().

%% Simular que el fermentador 1 pierde frío y sube 5 °C.
p80_demo:perder_frio(1, 5.0).

%% Consultar el estado de la planta.
p80_metricas:resumen().
p80_lotes:listar().
p80_fermentadores:listar().
p80_eventos:recientes(20).
```

> El registro vive en ETS y se conserva durante reinicios de procesos, pero **no
> sobrevive a reiniciar el nodo**. Si reinicias la aplicación se pierden lotes,
> fermentadores y eventos. Esto es intencional: el proyecto no usa base de datos.

---

## 3. Interfaz web

La interfaz se sirve desde `priv/static` y consume la API real:

- Resumen de métricas y distribución de lotes por etapa.
- Tarjetas de fermentadores con temperatura actual, objetivo, tolerancia y desviación.
- Acciones para ajustar el objetivo, registrar una lectura, normalizar la temperatura
  o simular una pérdida de frío de +5 °C.
- Listado de lotes con filtro por etapa, avance de etapa y detalle con historial.
- Bitácora de eventos en vivo por SSE (`/api/eventos/sse`).
- Actualización periódica de respaldo cada 8 segundos.
- Diseño responsivo para celular y escritorio.

El diseño y las decisiones visuales se documentan en [`design/DESIGN.md`](design/DESIGN.md).

---

## 4. Arquitectura OTP

### Árbol de supervisión

```
p80_cerveceria_artesanal_sup  (rest_for_one)
├── p80_registro              (gen_server + ETS + nombres via)
├── p80_eventos               (gen_server: bus y bitácora en memoria)
├── p80_metricas              (gen_server + contadores ETS)
├── p80_lote_sup              (supervisor one_for_one, dinámico)
│   └── p80_lote              (gen_statem, uno por lote)
├── p80_fermentador_sup       (supervisor one_for_one, dinámico)
│   └── p80_fermentador       (gen_server, uno por fermentador)
├── p80_http                  (Cowboy + tablero estático)
├── p80_vigilante             (monitorea al control de temperatura)
└── p80_control_temperatura   (gen_server periódico de simulación)
```

### Estrategia `rest_for_one`

El supervisor principal usa `rest_for_one` porque los hijos tienen dependencias de
arranque y de servicio:

- `p80_registro` debe existir antes que los procesos de dominio.
- `p80_eventos` y `p80_metricas` son usados por los supervisores dinámicos y por HTTP.
- `p80_http` debe arrancar después del dominio.
- `p80_vigilante` debe existir antes que `p80_control_temperatura` para observar su caída.

Consecuencia: si cae un proceso temprano, se reinician los posteriores. Si cae el
control de temperatura (último hijo), solo se reinicia él; el vigilante sobrevive.
Si cae el vigilante, también se reinicia el control.

### Persistencia y recuperación

`p80_registro` cumple dos funciones:

1. Implementa el módulo `via` para registrar dinámicamente lotes y fermentadores por ID.
2. Guarda en ETS un snapshot del último estado de cada proceso.

Cuando un `p80_lote` o `p80_fermentador` cae, su supervisor lo reinicia con los
argumentos originales. En `init/1` el proceso busca su snapshot en el registro y
recupera etapa, historial, temperatura, lote asignado, etc. Si el registro completo
cae, el árbol se reinicia y el estado se pierde.

### Procesos de dominio

| Proceso | Tipo | Responsabilidad |
|---|---|---|
| `p80_lote` | `gen_statem` | Etapas, transiciones, riesgo e historial del lote. |
| `p80_fermentador` | `gen_server` | Temperatura, tolerancia, alerta y lote asignado. |
| `p80_control_temperatura` | `gen_server` | Simula lecturas periódicas y deriva hacia el objetivo. |
| `p80_vigilante` | `gen_server` | Detecta la caída del control, marca lotes en riesgo y emite alertas. |
| `p80_eventos` | `gen_server` | Bus de eventos, buffer circular y suscripción SSE. |
| `p80_metricas` | `gen_server` | Contadores y resumen para JSON/Prometheus. |
| `p80_http` | `gen_server` | Arranque y puerto real del listener Cowboy. |

### Asignación de fermentadores

- Si el lote trae `fermentador_id` (al crearlo o al avanzar), se valida que exista,
  que tenga capacidad suficiente y que esté libre.
- Si no trae preferencia, `p80_fermentadores:asignar_automatico/2` elige el primer
  fermentador libre con capacidad suficiente.
- Si no hay ninguno, la transición devuelve `sin_fermentador_disponible` y el lote
  permanece en `coccion`.
- La liberación ocurre al pasar a `envasado`.

### Control de temperatura y riesgo

El control simula una lectura cada 5 segundos (configurable). Cada fermentador:

- Calcula `desviacion = abs(actual - objetivo)`.
- Entra en alerta si `desviacion > tolerancia`.
- Publica `alerta_temperatura` al entrar en alerta y `temperatura_normalizada` al salir.
- Notifica al lote asignado para marcarlo o normalizarlo.

Si el proceso de control cae, `p80_vigilante`:

1. Incrementa `caidas_control_temperatura`.
2. Publica `control_temperatura_caido`.
3. Marca en riesgo a todos los lotes con fermentador asignado.
4. Publica `riesgo_por_fallo_control`.
5. Sigue monitoreando; el supervisor levanta un nuevo control.

---

## 5. API HTTP

Todas las respuestas son JSON salvo `/metrics`, `/` y los archivos estáticos.

### Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/` | Panel web. |
| `GET` | `/health` | Estado, versión, uptime y procesos registrados. |
| `GET` | `/api/diagnostico` | Diagnóstico con memoria, procesos y `recon`. |
| `GET` | `/api/metricas` | Métricas de negocio en JSON. |
| `GET` | `/metrics` | Métricas en formato Prometheus. |
| `GET` | `/api/eventos?limite=N` | Eventos recientes (máximo 500). |
| `GET` | `/api/eventos/sse` | Stream SSE de eventos nuevos. |
| `GET` | `/api/lotes` | Lista de lotes. Acepta `?etapa=fermentacion`. |
| `POST` | `/api/lotes` | Crea un lote. |
| `GET` | `/api/lotes/:id` | Detalle con historial. |
| `POST` | `/api/lotes/:id/avanzar` | Avanza de etapa; acepta `fermentador_id`. |
| `GET` | `/api/fermentadores` | Lista de fermentadores. |
| `POST` | `/api/fermentadores` | Crea un fermentador. |
| `GET` | `/api/fermentadores/:id` | Detalle de un fermentador. |
| `PUT` | `/api/fermentadores/:id/temperatura` | Cambia la temperatura objetivo. |
| `PUT` | `/api/fermentadores/:id/temperatura-actual` | Registra una lectura actual. |

### Ejemplos

Crear un lote:

```bash
curl -s http://localhost:8080/api/lotes \
  -H 'content-type: application/json' \
  -d '{"nombre":"IPA 13","receta":"IPA Tijuana","litros":800}'
```

Crear un fermentador:

```bash
curl -s http://localhost:8080/api/fermentadores \
  -H 'content-type: application/json' \
  -d '{"nombre":"Fermentador G","capacidad_litros":1500,"temperatura_objetivo":18.0}'
```

Avanzar un lote:

```bash
curl -s -X POST http://localhost:8080/api/lotes/1/avanzar \
  -H 'content-type: application/json' \
  -d '{}'
```

Forzar una asignación explícita al entrar a fermentación:

```bash
curl -s -X POST http://localhost:8080/api/lotes/1/avanzar \
  -H 'content-type: application/json' \
  -d '{"fermentador_id":1}'
```

Cambiar el objetivo o registrar una lectura:

```bash
curl -s -X PUT http://localhost:8080/api/fermentadores/1/temperatura \
  -H 'content-type: application/json' \
  -d '{"temperatura_objetivo":17.5}'

curl -s -X PUT http://localhost:8080/api/fermentadores/1/temperatura-actual \
  -H 'content-type: application/json' \
  -d '{"temperatura_actual":24.0}'
```

Escuchar eventos en vivo:

```bash
curl -N http://localhost:8080/api/eventos/sse
```

### Formato de error

```json
{
  "error": {
    "codigo": "sin_fermentador_disponible",
    "mensaje": "no hay fermentadores libres con capacidad suficiente"
  }
}
```

Códigos usados:

- `solicitud_invalida` y `json_invalido` (400).
- `no_encontrado` y `fermentador_no_encontrado` (404).
- `metodo_no_permitido` (405).
- `transicion_invalida`, `lote_terminado`, `sin_fermentador_disponible`,
  `fermentador_ocupado`, `capacidad_insuficiente` y `lote_no_asignado` (409).
- `error_interno` (500).

### Eventos SSE

Cada evento tiene la forma:

```json
{
  "tipo": "alerta_temperatura",
  "ts": 1794200000000,
  "datos": {
    "fermentador_id": 1,
    "temperatura_actual": 25.0,
    "temperatura_objetivo": 18.0,
    "desviacion": 7.0,
    "tolerancia": 1.0,
    "lote_id": 4,
    "severidad": "alta"
  }
}
```

Tipos principales: `lote_creado`, `etapa_avanzada`, `lote_terminado`,
`alerta_lote`, `lote_normalizado`, `fermentador_creado`, `fermentador_asignado`,
`fermentador_liberado`, `lectura_temperatura`, `temperatura_objetivo_actualizada`,
`alerta_temperatura`, `temperatura_normalizada`, `control_temperatura_iniciado`,
`control_temperatura_caido`, `riesgo_por_fallo_control`, `lote_reiniciado`,
`fermentador_reiniciado`.

---

## 6. Métricas

`/api/metricas` entrega:

- `lotes_por_etapa`
- `total_lotes`
- `lotes_en_riesgo`
- `fermentadores_activos` y `fermentadores_totales`
- `desviaciones_temperatura`
- `litros_producidos` y `litros_en_proceso`
- `eventos_registrados`
- `alertas_temperatura`
- `caidas_control_temperatura`
- `inicios_control_temperatura`

`/metrics` expone las mismas cifras en formato Prometheus, por ejemplo:

```
cerveceria_lotes_por_etapa{etapa="fermentacion"} 4
cerveceria_lotes_en_riesgo 0
cerveceria_litros_producidos 2400
cerveceria_caidas_control_temperatura 1
```

---

## 7. Pruebas

```bash
rebar3 eunit
```

Cobertura de las 24 pruebas:

| Módulo | Qué verifica |
|---|---|
| `p80_lote_tests` | Creación, transiciones válidas, lote terminado, falta de fermentador, fermentador ocupado, preferencia explícita. |
| `p80_fermentador_tests` | Alta, cambio de objetivo, detección y normalización de desviaciones, asignación y liberación. |
| `p80_supervision_tests` | Recuperación de lote y fermentador tras `kill`, recuperación del control y supervivencia del vigilante. |
| `p80_api_tests` | Endpoints REST, métricas, salud, eventos, validaciones y códigos HTTP. |
| `p80_caos_tests` | Caída del control: nuevo control, vigilante vivo, lote en riesgo, métricas y eventos. |
| `p80_cerveceria_artesanal_tests` | Arranque de la aplicación, listener HTTP y módulos de dominio. |

Las pruebas HTTP usan `http_port = 0` para obtener un puerto efímero y evitar
conflictos con una instancia en el puerto 8080.

---

## 8. Prueba de caos

Desde `rebar3 shell`, con un escenario cargado:

```erlang
p80_demo:escenario().

VigilanteAntes = whereis(p80_vigilante).
ControlAntes = whereis(p80_control_temperatura).

exit(ControlAntes, kill).

timer:sleep(500).

whereis(p80_control_temperatura).   % debe ser un PID nuevo
whereis(p80_vigilante).             % debe seguir siendo VigilanteAntes
p80_metricas:resumen().             % caidas_control_temperatura > 0
p80_lotes:listar().                 % lotes con en_riesgo = true
p80_eventos:recientes(20).          % control_temperatura_caido y riesgo_por_fallo_control
```

Resultado esperado:

1. El supervisor principal reinicia únicamente `p80_control_temperatura`.
2. `p80_vigilante` no se reinicia.
3. Los lotes con fermentador asignado pasan a `en_riesgo = true`.
4. Se incrementa `caidas_control_temperatura`.
5. Se publican los eventos de caída y riesgo.
6. La API y el panel siguen respondiendo.

Esta secuencia está automatizada en `test/p80_caos_tests.erl`.

---

## 9. Release y operación

Construcción:

```bash
rebar3 release
```

Salida:

```
_build/default/rel/p80_cerveceria_artesanal/
```

Arranque manual:

```bash
_build/default/rel/p80_cerveceria_artesanal/bin/p80_cerveceria_artesanal foreground
```

Prueba de humo:

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:8080/api/metricas
```

Configuración:

- `config/sys.config`: puerto, intervalo de control, heartbeat SSE, máximo de eventos
  y tolerancia por defecto.
- `config/vm.args`: nombre del nodo, cookie y límites de Erlang.

Para producción se incluye una unidad systemd de ejemplo en
[`deploy/cerveceria-artesanal.service`](deploy/cerveceria-artesanal.service) y una
guía en [`rel/README.md`](rel/README.md).

Antes de desplegar:

- Cambia `-setcookie cambiar_en_produccion` en `config/vm.args`.
- Ajusta el usuario, el directorio y el nombre del nodo en la unidad systemd.
- Decide si el panel debe exponerse solo en red interna o detrás de un proxy.
- Recuerda que el estado es en memoria y se pierde al reiniciar el nodo.

---

## 10. Supuestos y cifras verificadas

Decisiones de alcance:

- Se modelan seis etapas agregadas (`molienda`, `coccion`, `fermentacion`,
  `maduracion`, `envasado`, `terminado`). Maceración, filtrado, enfriado,
  carbonatación y embotellado se agrupan o se representan dentro de esas etapas.
- El avance de etapa es **manual**: el operador confirma que la etapa terminó.
  No se modelan tiempos automáticos ni calendarios.
- La temperatura es simulada, no proviene de sensores reales.
- Un fermentador aloja un solo lote. No se implementa división de lote en dos
  fermentadores ni trazabilidad de insumos o densidad.
- La asignación de fermentador se libera al entrar a `envasado`, no al terminar.
- Persistencia en ETS con snapshots; sin base de datos, sin transacciones y sin
  recuperación tras reinicio total del nodo.

Cifras del enunciado usadas como referencia, no verificadas contra una fuente
externa en este repositorio:

- Lotes artesanales de 200 a 2 000 litros.
- 3 a 8 fermentadores por cervecería.
- Ales fermentadas entre 18 y 22 °C; lagers entre 8 y 12 °C.
- Maceración cercana a 65-68 °C durante aproximadamente 60 minutos; cocción de
  60 a 90 minutos.
- Estimación de alcohol: `(OG - FG) * 131.25`.
- Escenario: 5 recetas, 6 fermentadores y 12 lotes.

Mejoras posibles: densidad OG/FG, calendario de producción, división de lotes,
trazabilidad de insumos, limpieza/sanitización de fermentadores, persistencia real
y autenticación del panel.

---

## 11. Estructura del proyecto

```
.
├── config/
│   ├── sys.config
│   └── vm.args
├── deploy/
│   └── cerveceria-artesanal.service
├── design/
│   ├── DESIGN.md
│   └── PROMPT_STITCH.md
├── priv/static/
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── rel/
│   └── README.md
├── src/
│   ├── p80_*.erl
│   └── p80_cerveceria_artesanal.app.src
├── test/
│   └── p80_*_tests.erl
├── rebar.config
└── rebar.lock
```

---

## 12. Checklist de entrega

- [x] Dominio modelado con `gen_statem` y `gen_server`.
- [x] Supervisión OTP con estrategia y orden justificados.
- [x] API REST con Cowboy.
- [x] SSE para eventos en tiempo real.
- [x] Métricas JSON y Prometheus.
- [x] Diagnóstico con `recon`.
- [x] Interfaz web funcional y responsiva.
- [x] Escenario de demostración con 5 recetas, 6 fermentadores y 12 lotes.
- [x] Falla inyectada de pérdida de frío.
- [x] Prueba de caos automatizada.
- [x] `rebar3 compile` y `rebar3 eunit` en verde.
- [x] Release de producción y unidad systemd de ejemplo.
- [ ] Capturas de Stitch (el diseño se implementó directamente en HTML/CSS; ver
      `design/DESIGN.md`).
