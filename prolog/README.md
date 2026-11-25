# Gemelo Digital cervecero: Prolog + Janus

Extensión declarativa del sistema Erlang/OTP de Cervecería Artesanal. No sustituye
al núcleo OTP: consume instantáneas de la API HTTP existente, las proyecta como
hechos Prolog y deduce conocimiento que no está escrito explícitamente en los
JSON.

## ¿Por qué Prolog + Janus?

- El núcleo Erlang/OTP ya resuelve concurrencia, supervisión, HTTP, SSE y ETS.
  Reescribirlo para razonar sería un riesgo innecesario.
- Prolog expresa naturalmente restricciones de dominio (secuencia de etapas,
  exclusividad, capacidad, tolerancia térmica) y reglas de causa/efecto.
- Janus (`janus-swi`) permite embedding inverso: Python consulta Prolog como una
  biblioteca, sin servidores intermediarios ni formatos adicionales.
- Python solo transporta datos: `urllib` lee la API Erlang, normaliza `None` y
  booleanos, y llama a `cerveceria_gemelo:informe/1`.

## Archivos

| Archivo | Contenido |
|---|---|
| `cerveceria_gemelo.pl` | Base de conocimiento, hechos dinámicos y reglas de inferencia. |
| `gemelo_janus.py` | Cliente HTTP, snapshots `demo`/`caos`, puente Janus y CLI. |
| `test_gemelo_janus.py` | 10 pruebas `unittest`, 1 de integración opcional vía API. |
| `requirements.txt` | `janus-swi==1.5.3`. |

## Instalación

El entorno de trabajo usado tiene Python 3.13 y no permite `sudo` no
interactivo, por eso se instaló todo en un entorno Conda de usuario:

```bash
conda create -y -n p80-gemelo -c conda-forge python=3.13 swi-prolog c-compiler pip
conda run -n p80-gemelo swipl --version
conda run -n p80-gemelo python -m pip install -r prolog/requirements.txt
```

Verificado: `SWI-Prolog 10.0.0`, `Python 3.13.18`, `janus-swi 1.5.3`.

En una máquina con `sudo` también funciona la vía APT + venv:

```bash
sudo apt-get install -y swi-prolog build-essential python3-venv
python3 -m venv prolog/.venv
prolog/.venv/bin/pip install -r prolog/requirements.txt
```

`janus-swi` se compila desde fuente y necesita `swipl >= 9.1.12` en el `PATH`,
headers de SWI-Prolog y un compilador C. No necesita `requests`: el puente usa
solo la biblioteca estándar de Python.

## Estado sincronizado frente a conocimiento deducido

Hechos proyectados desde la API:

```prolog
lote(Id, Litros, Etapa, FermentadorIdHistorico, EnRiesgoAPI).
fermentador(Id, Capacidad, TempActual, TempObjetivo, Tolerancia).
fermentador_estado(Id, LoteId, Activo, EnAlerta).
asignacion(FermentadorId, LoteId).
control_temperatura_activo(true|false).
metrica_global(Clave, Valor).
metrica_etapa(Etapa, Cantidad).
evento(Tipo, Ts, Datos).
modo_twin(api|demo|caos).
```

`asignacion/2` se construye solo desde `fermentador.lote_id`. El campo
`lote.fermentador_id` se conserva como histórico porque Erlang no lo borra al
liberar en `envasado` (`src/p80_lote.erl:249-264`).

Reglas que deducen información nueva:

| Predicado | Conocimiento deducido |
|---|---|
| `puede_avanzar/3` | `permitido` o `bloqueado(Motivo)`: secuencia inválida, lote terminado, falta de fermentador, capacidad insuficiente, fermentador ocupado. |
| `candidatos/2` | Fermentadores libres con capacidad suficiente, ordenados por id como `p80_fermentadores:asignar_automatico/2`. |
| `motivo/2`, `motivos_dict/2` | Causa raíz: `desviacion_termica(FermentadorId, Grados)`, `caida_control_temperatura` o `estado_lote_riesgo` cuando el flag de Erlang no tiene causa observable. |
| `estado_normal/1` | Normalización: control activo, sin desviación y lote no marcado en riesgo. |
| `litros_producidos/1`, `litros_en_proceso/1` | Suma calculada desde lotes, no copiada de `/api/metricas`. |
| `comparar_metricas/1` | Contraste deducido vs reportado, incluido `lotes_por_etapa`. |
| `auditoria/1` | Asignación activa en etapa final, lote activo sin asignación, alerta térmica inconsistente, exclusividad violada. |
| `recomendaciones/1` | Enfriar/ajustar objetivo, reiniciar control, bloquear avance o asignar candidato. |
| `capacidad_disponible/1` | Capacidad ociosa sumando fermentadores sin asignación activa. |

Janus no convierte términos compuestos arbitrarios a Python. Por eso
`puede_avanzar/3` es la regla canónica en Prolog y `puede_avanzar_info/3`
devuelve el mismo resultado como dict (`estado`, `motivo`, `destino`) para el
puente y los reportes.

## Ejecución

Con el servidor Erlang apagado funcionan los modos autónomos:

```bash
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode demo
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode caos --fermentador 1 --grados 5.0
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode demo --drop-control
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode demo --json
```

Contra el sistema real:

```bash
rebar3 shell
%% Dentro de la shell:
p80_demo:escenario().
p80_demo:perder_frio(1, 5.0).
```

En otra terminal:

```bash
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode api
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode api --fallback-demo
conda run -n p80-gemelo python prolog/gemelo_janus.py --mode api --simular-frio --fermentador 1 --grados 5.0
```

`--mode api` lee `/health`, `/api/lotes`, `/api/fermentadores`, `/api/metricas`
y `/api/eventos`. Si `/health` responde 503, el cliente sigue parseando el JSON
para detectar `p80_control_temperatura.vivo == false`. `--simular-frio` y
`--drop-control` modifican solo la instantánea local del gemelo, nunca el
estado Erlang. `--fallback-demo` permite caer al escenario local si no hay
servidor.

Escenarios esperados:

- `demo`: 12 lotes, 2400 L producidos, 2850 L en proceso, sin riesgos, 6
  asignaciones activas y 0 L de capacidad disponible. L10/L11 están bloqueados
  por `sin_fermentador_disponible`.
- `caos --fermentador 1 --grados 5.0`: lote 4 en riesgo por
  `desviacion_termica(1, 5.0)` y recomendación de enfriamiento/ajuste.
- `demo --drop-control`: los 6 lotes asignados en riesgo por
  `caida_control_temperatura`, con recomendación de reiniciar el control.
- Si se mata `p80_control_temperatura` desde la shell OTP, `rest_for_one`
  conserva `p80_vigilante` y el modo `api` deduce el riesgo desde `/health`.

## Pruebas

```bash
conda run -n p80-gemelo python -m py_compile prolog/gemelo_janus.py prolog/test_gemelo_janus.py
conda run -n p80-gemelo python -m unittest discover -s prolog -p 'test_*.py' -v
P80_API_BASE=http://localhost:8080 conda run -n p80-gemelo python -m unittest discover -s prolog -p 'test_*.py' -v
```

La prueba de integración se omite automáticamente si no existe `P80_API_BASE`.

## Límites

- El estado de Erlang está en ETS: sobrevive a reinicios de procesos, no a un
  reinicio del nodo. El gemelo refleja la última sincronización.
- `alertas_temperatura`, `caidas_control_temperatura` e
  `inicios_control_temperatura` son contadores acumulativos de Erlang; no se
  comparan con reglas lógicas. Sí se comparan las magnitudes derivadas de
  instantáneas: etapas, riesgo, actividad, litros y desviaciones.
- El puente es de solo lectura sobre Erlang. Las simulaciones son locales y
  reproducibles; para fallar el sistema real usa `p80_demo:perder_frio/2` o el
  escenario de caos documentado en el README raíz.
