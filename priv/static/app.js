"use strict";

const ETAPAS = [
    "molienda",
    "coccion",
    "fermentacion",
    "maduracion",
    "envasado",
    "terminado"
];

const ETIQUETAS_ETAPA = {
    molienda: "Molienda",
    coccion: "Cocción",
    fermentacion: "Fermentación",
    maduracion: "Maduración",
    envasado: "Envasado",
    terminado: "Terminado"
};

const SIGUIENTE_ETAPA = {
    molienda: "coccion",
    coccion: "fermentacion",
    fermentacion: "maduracion",
    maduracion: "envasado",
    envasado: "terminado"
};

const EVENTOS = {
    lote_creado: { etiqueta: "Lote creado", clase: "ok" },
    etapa_avanzada: { etiqueta: "Etapa avanzada", clase: "info" },
    lote_terminado: { etiqueta: "Lote terminado", clase: "ok" },
    alerta_lote: { etiqueta: "Lote en riesgo", clase: "peligro" },
    lote_normalizado: { etiqueta: "Lote normalizado", clase: "ok" },
    lote_reiniciado: { etiqueta: "Lote reiniciado", clase: "alerta" },
    fermentador_creado: { etiqueta: "Fermentador creado", clase: "ok" },
    fermentador_asignado: { etiqueta: "Fermentador asignado", clase: "info" },
    fermentador_liberado: { etiqueta: "Fermentador liberado", clase: "info" },
    fermentador_reiniciado: { etiqueta: "Fermentador reiniciado", clase: "alerta" },
    lectura_temperatura: { etiqueta: "Lectura de temperatura", clase: "info" },
    temperatura_objetivo_actualizada: { etiqueta: "Objetivo actualizado", clase: "info" },
    alerta_temperatura: { etiqueta: "Alerta de temperatura", clase: "peligro" },
    temperatura_normalizada: { etiqueta: "Temperatura normalizada", clase: "ok" },
    control_temperatura_iniciado: { etiqueta: "Control iniciado", clase: "info" },
    control_temperatura_caido: { etiqueta: "Control caído", clase: "peligro" },
    riesgo_por_fallo_control: { etiqueta: "Riesgo por falla del control", clase: "peligro" },
    evento_prueba_api: { etiqueta: "Evento de prueba", clase: "info" }
};

const TIPOS_RECIENTES_HISTORIAL = {
    creado: "Creación",
    transicion: "Transición",
    riesgo: "Riesgo",
    normalizado: "Normalización"
};

const ESTADO = {
    metricas: null,
    lotes: [],
    fermentadores: [],
    eventos: [],
    salud: null,
    detalle: null
};

const $ = (selector) => document.querySelector(selector);

function escapar(valor) {
    return String(valor ?? "").replace(/[&<>"']/g, (caracter) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;"
    }[caracter]));
}

function numero(valor, porDefecto = 0) {
    const n = Number(valor);
    return Number.isFinite(n) ? n : porDefecto;
}

function litros(valor) {
    return new Intl.NumberFormat("es-MX").format(numero(valor));
}

function temperatura(valor) {
    return `${numero(valor).toFixed(1)} °C`;
}

function fechaHora(ts) {
    if (!ts) return "—";
    const fecha = new Date(ts);
    if (Number.isNaN(fecha.getTime())) return "—";
    return fecha.toLocaleString("es-MX", {
        day: "2-digit",
        month: "short",
        hour: "2-digit",
        minute: "2-digit"
    });
}

function hora(ts) {
    if (!ts) return "--:--";
    const fecha = new Date(ts);
    if (Number.isNaN(fecha.getTime())) return "--:--";
    return fecha.toLocaleTimeString("es-MX", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit"
    });
}

function duracion(segundos) {
    const total = Math.max(0, numero(segundos));
    const horas = Math.floor(total / 3600);
    const minutos = Math.floor((total % 3600) / 60);
    if (horas > 0) return `${horas} h ${minutos} min`;
    if (minutos > 0) return `${minutos} min`;
    return `${Math.floor(total)} s`;
}

function etiquetaEtapa(etapa) {
    return ETIQUETAS_ETAPA[etapa] || etapa || "—";
}

function textoEvento(tipo) {
    return EVENTOS[tipo]?.etiqueta || String(tipo || "Evento").replaceAll("_", " ");
}

function claseEvento(tipo) {
    return EVENTOS[tipo]?.clase || "info";
}

async function api(ruta, opciones = {}) {
    const configuracion = {
        ...opciones,
        headers: {
            "content-type": "application/json",
            ...(opciones.headers || {})
        }
    };
    const respuesta = await fetch(ruta, configuracion);
    const cuerpo = await respuesta.text();
    let datos = {};
    if (cuerpo) {
        try {
            datos = JSON.parse(cuerpo);
        } catch {
            datos = { texto: cuerpo };
        }
    }
    if (!respuesta.ok) {
        const mensaje = datos?.error?.mensaje || `Error HTTP ${respuesta.status}`;
        throw new Error(mensaje);
    }
    return datos;
}

function marcarConexion(texto, clase = "") {
    $("#estado-conexion").textContent = texto;
    $("#indicador-conexion").className = `punto ${clase}`.trim();
}

function toast(mensaje, tipo = "info") {
    const contenedor = $("#toasts");
    const elemento = document.createElement("div");
    elemento.className = `toast ${tipo}`;
    elemento.textContent = mensaje;
    contenedor.appendChild(elemento);
    window.setTimeout(() => elemento.remove(), 4800);
}

function abrirModal(id) {
    const modal = document.getElementById(id);
    if (modal && !modal.open) modal.showModal();
}

function cerrarModal(id) {
    const modal = document.getElementById(id);
    if (modal?.open) modal.close();
}

function renderMetricas() {
    const m = ESTADO.metricas || {};
    const terminados = numero(m.lotes_por_etapa?.terminado);
    const enProceso = Math.max(0, numero(m.total_lotes) - terminados);
    const enRiesgo = numero(m.lotes_en_riesgo);
    const tarjetas = [
        {
            etiqueta: "Lotes totales",
            valor: numero(m.total_lotes),
            detalle: `${enProceso} en proceso`,
            clase: ""
        },
        {
            etiqueta: "Lotes en riesgo",
            valor: enRiesgo,
            detalle: enRiesgo > 0 ? "Requieren atención" : "Sin riesgos activos",
            clase: enRiesgo > 0 ? "peligro" : "ok"
        },
        {
            etiqueta: "Fermentadores",
            valor: `${numero(m.fermentadores_activos)} / ${numero(m.fermentadores_totales)}`,
            detalle: "Ocupados / registrados",
            clase: "info"
        },
        {
            etiqueta: "Litros producidos",
            valor: litros(m.litros_producidos),
            detalle: "Lotes terminados",
            clase: "ok"
        },
        {
            etiqueta: "Litros en proceso",
            valor: litros(m.litros_en_proceso),
            detalle: "Lotes sin terminar",
            clase: ""
        },
        {
            etiqueta: "Alertas de temperatura",
            valor: numero(m.alertas_temperatura),
            detalle: `${numero(m.caidas_control_temperatura)} caídas del control`,
            clase: numero(m.alertas_temperatura) > 0 ? "peligro" : "ok"
        }
    ];

    $("#metricas").innerHTML = tarjetas.map((tarjeta) => `
        <article class="metrica ${tarjeta.clase}">
            <span class="etiqueta">${escapar(tarjeta.etiqueta)}</span>
            <span class="valor">${escapar(tarjeta.valor)}</span>
            <span class="detalle">${escapar(tarjeta.detalle)}</span>
        </article>
    `).join("");
}

function renderPipeline() {
    const m = ESTADO.metricas || {};
    const porEtapa = m.lotes_por_etapa || {};
    const total = Math.max(1, numero(m.total_lotes));

    $("#pipeline").innerHTML = ETAPAS.map((etapa, indice) => {
        const cantidad = numero(porEtapa[etapa]);
        const porcentaje = Math.round((cantidad / total) * 100);
        return `
            <div class="etapa etapa-${etapa}">
                <div class="etapa-top">
                    <span class="etapa-numero">${indice + 1}</span>
                    <span>${escapar(etiquetaEtapa(etapa))}</span>
                </div>
                <strong>${cantidad}</strong>
                <div class="etapa-barra" title="${cantidad} de ${numero(m.total_lotes)} lotes">
                    <span style="width: ${Math.min(100, porcentaje)}%"></span>
                </div>
            </div>
        `;
    }).join("");
}

function renderLotes() {
    const filtro = $("#filtro-etapa").value;
    const lotes = [...ESTADO.lotes]
        .filter((lote) => !filtro || lote.etapa === filtro)
        .sort((a, b) => numero(b.id) - numero(a.id));

    const contenedor = $("#lista-lotes");
    if (lotes.length === 0) {
        contenedor.innerHTML = `
            <div class="vacio">
                <strong>No hay lotes para mostrar</strong>
                Crea un lote nuevo o cambia el filtro de etapa.
            </div>
        `;
        return;
    }

    contenedor.innerHTML = lotes.map((lote) => {
        const siguiente = SIGUIENTE_ETAPA[lote.etapa];
        const enRiesgo = lote.en_riesgo === true;
        const asignado = lote.fermentador_id
            ? `Fermentador #${lote.fermentador_id}`
            : "Sin fermentador";
        const accionAvance = siguiente
            ? `<button type="button" class="boton chico primario"
                       data-accion="avanzar" data-id="${lote.id}">
                   Avanzar a ${escapar(etiquetaEtapa(siguiente))}
               </button>`
            : `<span class="nota">Ciclo completo</span>`;

        return `
            <article class="lote-card etapa-${lote.etapa} ${enRiesgo ? "riesgo" : ""}">
                <div class="lote-cabecera">
                    <div>
                        <h3>${escapar(lote.nombre)}</h3>
                        <p>${escapar(lote.receta)} · ${litros(lote.litros)} L</p>
                    </div>
                    <span class="chip etapa-${lote.etapa}">${escapar(etiquetaEtapa(lote.etapa))}</span>
                </div>
                ${enRiesgo ? `
                    <div class="riesgo-aviso">
                        En riesgo: ${escapar(lote.motivo_riesgo || "revisar temperatura del fermentador")}
                    </div>
                ` : ""}
                <div class="lote-meta">
                    <span>Lote <strong>#${lote.id}</strong></span>
                    <span>${escapar(asignado)}</span>
                    <span>Actualizado ${escapar(fechaHora(lote.actualizado_en))}</span>
                </div>
                <div class="lote-pie">
                    <button type="button" class="boton chico fantasma"
                            data-accion="detalle" data-id="${lote.id}">
                        Detalle
                    </button>
                    ${accionAvance}
                </div>
            </article>
        `;
    }).join("");
}

function renderFermentadores() {
    const fermentadores = [...ESTADO.fermentadores].sort(
        (a, b) => numero(a.id) - numero(b.id)
    );
    const contenedor = $("#lista-fermentadores");

    if (fermentadores.length === 0) {
        contenedor.innerHTML = `
            <div class="vacio">
                <strong>No hay fermentadores registrados</strong>
                Agrega el primer fermentador para comenzar a planear la producción.
            </div>
        `;
        return;
    }

    contenedor.innerHTML = fermentadores.map((fermentador) => {
        const alerta = fermentador.en_alerta === true;
        const activo = fermentador.lote_id !== null && fermentador.lote_id !== undefined;
        const tolerancia = Math.max(0.1, numero(fermentador.tolerancia, 1));
        const porcentaje = Math.min(100, (numero(fermentador.desviacion) / tolerancia) * 100);
        const lote = activo
            ? `<button type="button" class="enlace" data-accion="detalle" data-id="${fermentador.lote_id}">
                   #${fermentador.lote_id}
               </button>`
            : "—";
        const accionTemperatura = alerta
            ? `<button type="button" class="boton chico"
                       data-accion="normalizar" data-id="${fermentador.id}">
                   Normalizar
               </button>`
            : `<button type="button" class="boton chico"
                       data-accion="simular" data-id="${fermentador.id}"
                       title="Simula que el fermentador pierde frío y sube 5 °C">
                   Simular +5 °C
               </button>`;

        return `
            <article class="fermentador-card ${alerta ? "alerta" : ""} ${activo ? "ocupado" : ""}">
                <div class="fermentador-cabecera">
                    <div>
                        <h3>${escapar(fermentador.nombre)}</h3>
                        <p>Capacidad ${litros(fermentador.capacidad_litros)} L</p>
                    </div>
                    <span class="chip ${activo ? "" : "neutral"}">
                        ${activo ? "Ocupado" : "Libre"}
                    </span>
                </div>
                <div class="fermentador-temperatura">
                    <span class="temperatura-grande ${alerta ? "alerta" : ""}">
                        ${temperatura(fermentador.temperatura_actual)}
                    </span>
                    <span class="temperatura-detalle">
                        Objetivo ${temperatura(fermentador.temperatura_objetivo)}<br>
                        Desviación ${temperatura(fermentador.desviacion)} · tolerancia ${temperatura(fermentador.tolerancia)}
                    </span>
                </div>
                <div class="medidor ${alerta ? "alerta" : ""}"
                     title="Desviación ${temperatura(fermentador.desviacion)} de ${temperatura(fermentador.tolerancia)}">
                    <span style="width: ${Math.max(2, porcentaje)}%"></span>
                </div>
                <div class="fermentador-datos">
                    <div><span>Lote asignado</span><strong>${lote}</strong></div>
                    <div><span>Fermentador</span><strong>#${fermentador.id}</strong></div>
                </div>
                <div class="fermentador-pie">
                    <button type="button" class="boton chico fantasma"
                            data-accion="objetivo" data-id="${fermentador.id}">
                        Objetivo
                    </button>
                    <button type="button" class="boton chico fantasma"
                            data-accion="lectura" data-id="${fermentador.id}">
                        Lectura
                    </button>
                    ${accionTemperatura}
                </div>
            </article>
        `;
    }).join("");
}

function resumenEvento(evento) {
    const d = evento.datos || {};
    switch (evento.tipo) {
        case "lote_creado":
            return `Lote “${d.nombre}” (#${d.lote_id}) creado con ${litros(d.litros)} L en ${etiquetaEtapa(d.etapa)}.`;
        case "etapa_avanzada":
            return `Lote #${d.lote_id} pasó de ${etiquetaEtapa(d.etapa_anterior)} a ${etiquetaEtapa(d.etapa)}${d.fermentador_id ? ` con el fermentador #${d.fermentador_id}` : ""}.`;
        case "lote_terminado":
            return `Lote #${d.lote_id} completó el ciclo de producción.`;
        case "alerta_lote":
            return `Lote #${d.lote_id} marcado en riesgo: ${d.motivo}.`;
        case "lote_normalizado":
            return `Lote #${d.lote_id} salió del estado de riesgo: ${d.motivo}.`;
        case "lote_reiniciado":
            return `El proceso del lote #${d.lote_id} se reinició y recuperó su etapa ${etiquetaEtapa(d.etapa)}.`;
        case "fermentador_creado":
            return `Fermentador “${d.nombre}” (#${d.fermentador_id}) registrado con ${litros(d.capacidad_litros)} L.`;
        case "fermentador_asignado":
            return `Lote #${d.lote_id} asignado al fermentador #${d.fermentador_id}.`;
        case "fermentador_liberado":
            return `Fermentador #${d.fermentador_id} liberado del lote #${d.lote_id}.`;
        case "fermentador_reiniciado":
            return `El proceso del fermentador #${d.fermentador_id} se reinició y recuperó su estado.`;
        case "lectura_temperatura":
            return `Fermentador #${d.fermentador_id}: ${temperatura(d.temperatura_actual)}; objetivo ${temperatura(d.temperatura_objetivo)}; desviación ${temperatura(d.desviacion)}.`;
        case "temperatura_objetivo_actualizada":
            return `Fermentador #${d.fermentador_id}: nuevo objetivo ${temperatura(d.temperatura_objetivo)}.`;
        case "alerta_temperatura":
            return `Fermentador #${d.fermentador_id} fuera de tolerancia: desviación de ${temperatura(d.desviacion)}.`;
        case "temperatura_normalizada":
            return `Fermentador #${d.fermentador_id} volvió a su rango de temperatura.`;
        case "control_temperatura_iniciado":
            return `Control de temperatura iniciado con intervalo de ${numero(d.intervalo_ms) / 1000} s.`;
        case "control_temperatura_caido":
            return `El control de temperatura cayó (${d.razon}). El vigilante mantiene la alerta.`;
        case "riesgo_por_fallo_control":
            return `Lotes marcados en riesgo por falla del control: ${(d.lotes || []).join(", ") || "sin lotes asignados"}.`;
        default:
            return JSON.stringify(d).slice(0, 220);
    }
}

function renderEventos() {
    const contenedor = $("#lista-eventos");
    const eventos = ESTADO.eventos.slice(0, 100);
    $("#contador-eventos").textContent = `${eventos.length} eventos recientes`;

    if (eventos.length === 0) {
        contenedor.innerHTML = `
            <li class="vacio">
                <strong>Sin actividad todavía</strong>
                Los eventos aparecerán aquí en cuanto la planta comience a operar.
            </li>
        `;
        return;
    }

    contenedor.innerHTML = eventos.map((evento) => `
        <li class="evento ${claseEvento(evento.tipo)}">
            <span class="evento-hora">${escapar(hora(evento.ts))}</span>
            <div class="evento-cuerpo">
                <span class="evento-tipo">${escapar(textoEvento(evento.tipo))}</span>
                <p>${escapar(resumenEvento(evento))}</p>
            </div>
            <span class="evento-marca" aria-hidden="true"></span>
        </li>
    `).join("");
}

function renderSalud() {
    if (!ESTADO.salud) return;
    $("#uptime").textContent = `Activo ${duracion(ESTADO.salud.uptime_segundos)}`;
    $("#version").textContent = `v${ESTADO.salud.version || "?"}`;
}

function renderDetalle(lote) {
    const siguiente = SIGUIENTE_ETAPA[lote.etapa];
    const enRiesgo = lote.en_riesgo === true;
    $("#detalle-titulo").innerHTML = `
        <p class="eyebrow">Lote #${lote.id}</p>
        <h2>${escapar(lote.nombre)}</h2>
        <p>${escapar(lote.receta)} · ${litros(lote.litros)} L</p>
    `;

    const historial = [...(lote.historial || [])].reverse();
    const filasHistorial = historial.map((entrada) => `
        <li>
            <div class="historial-hora">
                ${escapar(fechaHora(entrada.ts))} · ${escapar(TIPOS_RECIENTES_HISTORIAL[entrada.tipo] || entrada.tipo)}
            </div>
            <div class="historial-detalle">${escapar(entrada.detalle)}</div>
        </li>
    `).join("");

    $("#detalle-contenido").innerHTML = `
        <div class="detalle-resumen">
            <div class="detalle-dato">
                <span>Etapa actual</span>
                <strong><span class="chip etapa-${lote.etapa}">${escapar(etiquetaEtapa(lote.etapa))}</span></strong>
            </div>
            <div class="detalle-dato">
                <span>Fermentador</span>
                <strong>${lote.fermentador_id ? `#${lote.fermentador_id}` : "Sin asignar"}</strong>
            </div>
            <div class="detalle-dato">
                <span>Creado</span>
                <strong>${escapar(fechaHora(lote.creado_en))}</strong>
            </div>
            <div class="detalle-dato">
                <span>Actualizado</span>
                <strong>${escapar(fechaHora(lote.actualizado_en))}</strong>
            </div>
        </div>
        ${enRiesgo ? `
            <div class="detalle-riesgo">
                En riesgo: ${escapar(lote.motivo_riesgo || "revisar temperatura del fermentador")}
            </div>
        ` : ""}
        <div>
            <h3>Historial del lote</h3>
            <ol class="historial">${filasHistorial || "<li>Sin movimientos registrados.</li>"}</ol>
        </div>
    `;

    const acciones = $("#detalle-acciones");
    if (!siguiente) {
        acciones.innerHTML = `<span class="nota">El lote completó su ciclo de producción.</span>`;
        return;
    }

    let selector = "";
    if (siguiente === "fermentacion") {
        const disponibles = ESTADO.fermentadores
            .filter((f) => !f.lote_id && numero(f.capacidad_litros) >= numero(lote.litros))
            .sort((a, b) => numero(a.id) - numero(b.id));
        const opciones = disponibles.map((f) => `
            <option value="${f.id}">
                #${f.id} ${escapar(f.nombre)} · ${litros(f.capacidad_litros)} L
            </option>
        `).join("");
        selector = `
            <label>
                Asignar a
                <select id="detalle-fermentador">
                    <option value="">Automático</option>
                    ${opciones}
                </select>
            </label>
        `;
    }

    acciones.innerHTML = `
        <div class="detalle-avance">
            ${selector}
            <button type="button" class="boton primario"
                    data-accion="detalle-avanzar" data-id="${lote.id}">
                Avanzar a ${escapar(etiquetaEtapa(siguiente))}
            </button>
        </div>
    `;
}

async function cargarDominio() {
    const [metricas, lotes, fermentadores] = await Promise.all([
        api("/api/metricas"),
        api("/api/lotes"),
        api("/api/fermentadores")
    ]);
    ESTADO.metricas = metricas.metricas || null;
    ESTADO.lotes = lotes.lotes || [];
    ESTADO.fermentadores = fermentadores.fermentadores || [];
    renderMetricas();
    renderPipeline();
    renderLotes();
    renderFermentadores();
}

async function cargarEventos() {
    const respuesta = await api("/api/eventos?limite=100");
    ESTADO.eventos = respuesta.eventos || [];
    renderEventos();
}

async function cargarSalud() {
    try {
        ESTADO.salud = await api("/health");
        renderSalud();
    } catch {
        ESTADO.salud = null;
    }
}

async function cargarTodo(mostrarErrores = false) {
    try {
        await Promise.all([cargarDominio(), cargarEventos(), cargarSalud()]);
        marcarConexion("En vivo", "ok");
    } catch (error) {
        marcarConexion("Sin conexión", "peligro");
        if (mostrarErrores) toast(error.message, "error");
    }
}

function programarRefresco() {
    window.clearTimeout(programarRefresco.temporizador);
    programarRefresco.temporizador = window.setTimeout(() => {
        cargarDominio().catch(() => marcarConexion("Reconectando", "alerta"));
        cargarSalud();
    }, 450);
}

function agregarEvento(evento) {
    ESTADO.eventos = [evento, ...ESTADO.eventos].slice(0, 100);
    renderEventos();
    if (["alerta_temperatura", "control_temperatura_caido", "alerta_lote"].includes(evento.tipo)) {
        toast(resumenEvento(evento), "error");
    } else if (evento.tipo === "lote_terminado") {
        toast(resumenEvento(evento), "ok");
    }
    programarRefresco();
}

function conectarSSE() {
    if (!("EventSource" in window)) {
        marcarConexion("Sin SSE", "alerta");
        return;
    }
    const fuente = new EventSource("/api/eventos/sse");
    fuente.addEventListener("open", () => marcarConexion("En vivo", "ok"));
    fuente.addEventListener("error", () => marcarConexion("Reconectando", "alerta"));
    fuente.addEventListener("message", (mensaje) => {
        try {
            agregarEvento(JSON.parse(mensaje.data));
        } catch {
            // Ignora mensajes que no sean JSON.
        }
    });
    window.addEventListener("beforeunload", () => fuente.close());
}

async function avanzarLote(id, fermentadorId) {
    const cuerpo = fermentadorId ? { fermentador_id: fermentadorId } : {};
    try {
        const respuesta = await api(`/api/lotes/${id}/avanzar`, {
            method: "POST",
            body: JSON.stringify(cuerpo)
        });
        toast(`Lote #${id} avanzó a ${etiquetaEtapa(respuesta.lote.etapa)}.`, "ok");
        cerrarModal("modal-detalle");
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
}

async function abrirDetalle(id) {
    try {
        const respuesta = await api(`/api/lotes/${id}`);
        ESTADO.detalle = respuesta.lote;
        renderDetalle(respuesta.lote);
        abrirModal("modal-detalle");
    } catch (error) {
        toast(error.message, "error");
    }
}

function abrirAccionFermentador(id, modo) {
    const fermentador = ESTADO.fermentadores.find((f) => numero(f.id) === numero(id));
    if (!fermentador) {
        toast("El fermentador ya no está disponible.", "error");
        return;
    }
    const formulario = $("#form-fermentador-accion");
    formulario.elements.id.value = id;
    formulario.elements.modo.value = modo;
    const esObjetivo = modo === "objetivo";
    $("#accion-eyebrow").textContent = esObjetivo ? "Temperatura objetivo" : "Lectura de sensor";
    $("#accion-titulo").textContent = esObjetivo
        ? "Ajustar temperatura objetivo"
        : "Registrar temperatura actual";
    $("#accion-etiqueta").textContent = esObjetivo
        ? "Temperatura objetivo (°C)"
        : "Temperatura actual (°C)";
    formulario.elements.valor.value = esObjetivo
        ? numero(fermentador.temperatura_objetivo).toFixed(1)
        : numero(fermentador.temperatura_actual).toFixed(1);
    $("#accion-ayuda").textContent = esObjetivo
        ? "La alerta se recalcula contra la tolerancia configurada del fermentador."
        : "La lectura se compara de inmediato contra el objetivo y su tolerancia.";
    abrirModal("modal-fermentador-accion");
    window.setTimeout(() => formulario.elements.valor.focus(), 40);
}

async function simularDesviacion(id) {
    const fermentador = ESTADO.fermentadores.find((f) => numero(f.id) === numero(id));
    if (!fermentador) return;
    const nueva = numero(fermentador.temperatura_objetivo) + 5;
    try {
        await api(`/api/fermentadores/${id}/temperatura-actual`, {
            method: "PUT",
            body: JSON.stringify({ temperatura_actual: nueva })
        });
        toast(`Fermentador #${id}: se simularon +5 °C sobre el objetivo.`, "alerta");
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
}

async function normalizarFermentador(id) {
    const fermentador = ESTADO.fermentadores.find((f) => numero(f.id) === numero(id));
    if (!fermentador) return;
    try {
        await api(`/api/fermentadores/${id}/temperatura-actual`, {
            method: "PUT",
            body: JSON.stringify({ temperatura_actual: fermentador.temperatura_objetivo })
        });
        toast(`Fermentador #${id}: temperatura normalizada.`, "ok");
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
}

$("#form-lote").addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const formulario = evento.currentTarget;
    const datos = new FormData(formulario);
    const cuerpo = {
        nombre: String(datos.get("nombre") || "").trim(),
        litros: Number(datos.get("litros"))
    };
    const receta = String(datos.get("receta") || "").trim();
    if (receta) cuerpo.receta = receta;
    try {
        const respuesta = await api("/api/lotes", {
            method: "POST",
            body: JSON.stringify(cuerpo)
        });
        formulario.reset();
        cerrarModal("modal-lote");
        toast(`Lote #${respuesta.lote.id} creado en molienda.`, "ok");
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
});

$("#form-fermentador").addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const formulario = evento.currentTarget;
    const datos = new FormData(formulario);
    const cuerpo = {
        nombre: String(datos.get("nombre") || "").trim(),
        capacidad_litros: Number(datos.get("capacidad_litros"))
    };
    for (const [campo, destino] of [
        ["temperatura_objetivo", "temperatura_objetivo"],
        ["temperatura_actual", "temperatura_actual"],
        ["tolerancia", "tolerancia"]
    ]) {
        const valor = String(datos.get(campo) || "").trim();
        if (valor !== "") cuerpo[destino] = Number(valor);
    }
    try {
        const respuesta = await api("/api/fermentadores", {
            method: "POST",
            body: JSON.stringify(cuerpo)
        });
        formulario.reset();
        cerrarModal("modal-fermentador");
        toast(`Fermentador #${respuesta.fermentador.id} registrado.`, "ok");
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
});

$("#form-fermentador-accion").addEventListener("submit", async (evento) => {
    evento.preventDefault();
    const formulario = evento.currentTarget;
    const id = formulario.elements.id.value;
    const modo = formulario.elements.modo.value;
    const valor = Number(formulario.elements.valor.value);
    const esObjetivo = modo === "objetivo";
    const ruta = esObjetivo
        ? `/api/fermentadores/${id}/temperatura`
        : `/api/fermentadores/${id}/temperatura-actual`;
    const cuerpo = esObjetivo
        ? { temperatura_objetivo: valor }
        : { temperatura_actual: valor };
    try {
        await api(ruta, { method: "PUT", body: JSON.stringify(cuerpo) });
        cerrarModal("modal-fermentador-accion");
        toast(
            esObjetivo
                ? `Fermentador #${id}: objetivo actualizado a ${temperatura(valor)}.`
                : `Fermentador #${id}: lectura registrada en ${temperatura(valor)}.`,
            "ok"
        );
        await cargarTodo(true);
    } catch (error) {
        toast(error.message, "error");
    }
});

document.addEventListener("click", (evento) => {
    const abridor = evento.target.closest("[data-abrir]");
    if (abridor) {
        abrirModal(abridor.dataset.abrir);
        return;
    }

    const cerrador = evento.target.closest("[data-cerrar]");
    if (cerrador) {
        cerrador.closest("dialog")?.close();
        return;
    }

    const boton = evento.target.closest("[data-accion]");
    if (!boton) return;
    const id = Number(boton.dataset.id);
    switch (boton.dataset.accion) {
        case "detalle":
            abrirDetalle(id);
            break;
        case "avanzar":
            avanzarLote(id, null);
            break;
        case "detalle-avanzar": {
            const selector = document.getElementById("detalle-fermentador");
            const fermentadorId = selector?.value ? Number(selector.value) : null;
            avanzarLote(id, fermentadorId);
            break;
        }
        case "objetivo":
            abrirAccionFermentador(id, "objetivo");
            break;
        case "lectura":
            abrirAccionFermentador(id, "lectura");
            break;
        case "simular":
            simularDesviacion(id);
            break;
        case "normalizar":
            normalizarFermentador(id);
            break;
        default:
            break;
    }
});

document.querySelectorAll("dialog").forEach((dialogo) => {
    dialogo.addEventListener("click", (evento) => {
        if (evento.target === dialogo) dialogo.close();
    });
});

$("#filtro-etapa").addEventListener("change", renderLotes);
$("#btn-actualizar").addEventListener("click", () => cargarTodo(true));

window.setInterval(() => {
    cargarDominio().catch(() => marcarConexion("Reconectando", "alerta"));
    cargarSalud();
}, 8000);

marcarConexion("Conectando", "alerta");
cargarTodo(true).then(conectarSSE);
