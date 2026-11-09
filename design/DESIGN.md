# Diseño de interfaz — Cervecería Artesanal

Este documento describe el diseño implementado en `priv/static`. La interfaz se
construyó directamente con HTML, CSS y JavaScript sin dependencias externas, y
consume la API y el stream SSE del backend OTP.

El objetivo es que el operador de la planta pueda responder tres preguntas de un
vistazo:

1. ¿Cómo está la producción ahora mismo?
2. ¿Qué lote o fermentador requiere atención?
3. ¿Qué acaba de pasar en la planta?

---

## 1. Principios

- **Estado antes que decoración.** Los números, las etapas y las alertas ocupan el
  primer plano. El color se usa para comunicar estado, no solo estética.
- **Lectura en celular.** Una columna en pantallas pequeñas, dos o tres en
  escritorio, tipografía fluida y botones táctiles de al menos 42 px.
- **Tiempo real visible.** La barra superior indica si el stream SSE está conectado
  y la bitácora se actualiza sin recargar.
- **Acciones con confirmación.** Crear, avanzar y ajustar temperatura usan modales;
  los errores de negocio se muestran como notificaciones legibles.
- **Español de planta.** Etapas, mensajes y ayudas usan vocabulario del dominio
  cervecero, no términos técnicos de OTP.

---

## 2. Pantallas

### 2.1 Dashboard principal

- Cabecera fija con marca, navegación, estado de conexión, uptime y versión.
- Hero con el título “Control de lotes y fermentación” y acciones de actualización.
- Seis tarjetas de métricas: lotes totales, lotes en riesgo, fermentadores
  ocupados, litros producidos, litros en proceso y alertas de temperatura.
- Pipeline de seis etapas con el número de lotes y una barra proporcional.
- Sección de lotes con filtro por etapa y botón “Nuevo lote”.
- Sección de fermentadores con tarjetas de temperatura y acciones rápidas.
- Bitácora de actividad y alertas con los eventos más recientes.

### 2.2 Detalle de lote

Modal ancho con:

- Nombre, receta, litros y etapa actual.
- Fermentador asignado, fechas de creación y actualización.
- Aviso de riesgo con el motivo cuando aplica.
- Historial cronológico del lote.
- Acción para avanzar de etapa. Si el siguiente paso es fermentación, se muestra
  un selector de fermentadores libres con capacidad suficiente y una opción
  automática.

### 2.3 Detalle y acciones de fermentador

Las tarjetas de fermentador muestran:

- Nombre, capacidad y estado libre/ocupado.
- Temperatura actual grande, objetivo, desviación y tolerancia.
- Medidor de desviación contra tolerancia.
- Lote asignado con enlace al detalle del lote.
- Acciones: ajustar objetivo, registrar lectura, normalizar o simular +5 °C.

### 2.4 Actividad y alertas

Lista cronológica inversa con:

- Hora del evento.
- Tipo de evento con etiqueta legible.
- Resumen generado a partir del payload real.
- Marca de color por severidad: verde (ok), azul (información), ámbar (advertencia)
  y rojo (falla o riesgo).

### 2.5 Formularios

- **Nuevo lote:** nombre, receta y litros.
- **Nuevo fermentador:** nombre, capacidad, temperatura objetivo, temperatura actual
  y tolerancia.
- **Acción de temperatura:** un solo campo numérico contextualizado por el modo
  (objetivo o lectura actual).

---

## 3. Paleta y tokens

La interfaz usa un tema oscuro cálido inspirado en malta, cobre y cerveza.

| Token | Valor | Uso |
|---|---|---|
| `--fondo` | `#100d0a` | Fondo principal. |
| `--panel` | `#1d1711` | Tarjetas y paneles. |
| `--borde` | `#3a2c1f` | Bordes principales. |
| `--texto` | `#f4ead9` | Texto principal. |
| `--texto-suave` | `#b9a88f` | Texto secundario. |
| `--ambar` | `#f0b34c` | Acento de marca y acciones primarias. |
| `--verde` | `#63d391` | Estado correcto, disponible o normalizado. |
| `--rojo` | `#ff7166` | Alerta, riesgo o falla. |
| `--azul` | `#71b7ff` | Información y eventos de flujo. |
| `--violeta` | `#c79bff` | Etapa de envasado. |

Colores por etapa:

- Molienda: `#d6a46f`
- Cocción: `#f0b34c`
- Fermentación: `#63d391`
- Maduración: `#71b7ff`
- Envasado: `#c79bff`
- Terminado: `#9ea79a`

Los estados de conexión usan el mismo lenguaje: verde para “En vivo”, ámbar para
“Reconectando” y rojo para “Sin conexión”.

---

## 4. Tipografía y jerarquía

- Familia del sistema: Avenir Next, Segoe UI, Helvetica Neue, Arial.
- Título principal fluido entre 2 rem y 3.4 rem.
- Títulos de sección entre 1.35 rem y 1.85 rem.
- Números de métricas entre 1.5 rem y 2.1 rem.
- Texto de apoyo entre 0.72 rem y 0.92 rem.
- Números tabulares en horas, métricas y temperaturas.

La interfaz evita fuentes externas para que el panel funcione sin red y sin
dependencias de terceros.

---

## 5. Componentes

- **Tarjeta de métrica:** etiqueta, valor grande, detalle y barra lateral de color.
- **Chip de etapa:** fondo y borde derivados del color de la etapa.
- **Tarjeta de lote:** nombre, receta, litros, chip de etapa, aviso de riesgo,
  metadatos y acciones.
- **Tarjeta de fermentador:** temperatura, medidor, lote asignado y acciones.
- **Medidor de desviación:** barra que crece respecto a la tolerancia y cambia a
  rojo cuando el fermentador está en alerta.
- **Bitácora:** lista con hora, tipo, resumen y punto de severidad.
- **Modal:** formulario o detalle, con cierre por botón, tecla Escape o clic en el
  fondo.
- **Toast:** confirmación o error temporal en la esquina inferior derecha.

---

## 6. Responsive

- **Más de 1080 px:** 6 métricas por fila, 3 lotes y 3 fermentadores por fila.
- **820-1080 px:** 3 métricas por fila, 2 lotes y 2 fermentadores, pipeline de 3.
- **640-820 px:** navegación debajo de la marca, cabeceras apiladas y detalle en
  dos columnas.
- **Menos de 640 px:** una columna para lotes y fermentadores, dos columnas para
  métricas y pipeline, formularios de una columna.
- **Menos de 430 px:** se oculta el subtítulo de marca y se compacta la conexión.

Se respeta `prefers-reduced-motion` para desactivar animaciones.

---

## 7. Interacción con el backend

| Acción de UI | Endpoint |
|---|---|
| Cargar métricas | `GET /api/metricas` |
| Cargar lotes | `GET /api/lotes` |
| Cargar fermentadores | `GET /api/fermentadores` |
| Cargar salud | `GET /health` |
| Cargar bitácora inicial | `GET /api/eventos?limite=100` |
| Escuchar eventos | `GET /api/eventos/sse` |
| Crear lote | `POST /api/lotes` |
| Avanzar lote | `POST /api/lotes/:id/avanzar` |
| Detalle de lote | `GET /api/lotes/:id` |
| Crear fermentador | `POST /api/fermentadores` |
| Cambiar objetivo | `PUT /api/fermentadores/:id/temperatura` |
| Registrar lectura | `PUT /api/fermentadores/:id/temperatura-actual` |

Estrategia de actualización:

1. Carga inicial con `Promise.all`.
2. Conexión SSE para eventos nuevos.
3. Cada evento relevante programa un refresco con debounce de 450 ms.
4. Respaldo periódico cada 8 segundos por si el SSE se interrumpe.
5. Las acciones de escritura refrescan el estado al recibir la respuesta.

Los errores de negocio se muestran con el mensaje en español que devuelve
`error.mensaje`; nunca se muestra un stack trace al operador.

---

## 8. Accesibilidad

- Enlace “Saltar al contenido”.
- Etiquetas visibles en todos los campos.
- `aria-live` en métricas, lotes, fermentadores y bitácora.
- Botones con texto explícito; los botones de cierre tienen `aria-label`.
- Contraste alto entre texto y fondos.
- Foco visible con contorno ámbar.
- No se depende solo del color: cada estado tiene texto asociado.

---

## 9. Relación con el prompt de Stitch

El archivo [`PROMPT_STITCH.md`](PROMPT_STITCH.md) contiene el encargo original:
dashboard, detalle y bitácora. La implementación cubre esas tres pantallas en una
sola página con modales y navegación por anclas.

No se incluyen capturas exportadas de Stitch en este repositorio. La referencia
visual real es la aplicación servida en `/` después de `rebar3 shell`. Si se
requieren capturas para la entrega, se pueden tomar del panel en ejecución y
guardar en `design/` sin modificar el código.

---

## 10. Cómo revisar el diseño

```bash
rebar3 shell
```

Abrir <http://localhost:8080/> y, en otra terminal:

```bash
curl -s http://localhost:8080/api/lotes \
  -H 'content-type: application/json' \
  -d '{"nombre":"IPA demo","receta":"IPA","litros":800}'
```

Para ver el estado de alerta en la interfaz:

1. Crear un fermentador y un lote.
2. Avanzar el lote hasta fermentación con `fermentador_id`.
3. En la tarjeta del fermentador, usar “Simular +5 °C”.
4. Verificar que el fermentador se marca en rojo, el lote queda en riesgo y la
   bitácora recibe los eventos.
5. Usar “Normalizar” para volver al objetivo y ver el evento de normalización.
