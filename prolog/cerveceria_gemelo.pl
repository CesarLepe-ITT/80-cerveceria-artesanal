%%% @doc Gemelo Digital declarativo de la cervecería artesanal.
%%%
%%% Este módulo no sustituye al núcleo Erlang/OTP: recibe instantáneas de la API
%%% HTTP y deduce riesgo, transiciones, recomendaciones, auditoría y métricas.
%%% Los hechos dinámicos son la proyección del estado real; las reglas son el
%%% conocimiento del gemelo.
:- module(cerveceria_gemelo, [
    sincronizar/1,
    puede_avanzar/3,
    puede_avanzar_info/3,
    candidatos/2,
    motivo/2,
    riesgo/1,
    motivos/2,
    motivos_dict/2,
    estado_normal/1,
    litros_producidos/1,
    litros_en_proceso/1,
    derivar_metricas/1,
    comparar_metricas/1,
    capacidad_disponible/1,
    riesgos/1,
    transiciones/1,
    recomendaciones/1,
    auditoria/1,
    informe/1
]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).

:- dynamic lote/5.
:- dynamic lote_detalle/5.
:- dynamic lote_riesgo_api/3.
:- dynamic lote_historial/5.
:- dynamic fermentador/5.
:- dynamic fermentador_estado/4.
:- dynamic asignacion/2.
:- dynamic control_temperatura_activo/1.
:- dynamic metrica_global/2.
:- dynamic metrica_etapa/2.
:- dynamic evento/3.
:- dynamic modo_twin/1.

/** <module> Gemelo Digital de la cervecería

Estado sincronizado:
  * lote(Id, Litros, Etapa, FermentadorIdHistorico, EnRiesgoAPI)
  * fermentador(Id, Capacidad, TempActual, TempObjetivo, Tolerancia)
  * asignacion(FermentadorId, LoteId) % solo asignación activa (lote_id del fermentador)

El campo `fermentador_id` del lote es histórico: Erlang no lo borra al liberar
el fermentador en `envasado`. Por eso la exclusividad se deduce de asignacion/2.
*/

%!  sincronizar(+Estado) is det.
%
%   Sustituye toda la base dinámica por una instantánea recibida desde Python.
%   Estado es un dict de Janus con claves lotes, fermentadores, metricas,
%   eventos, control_activo y modo.

sincronizar(Estado) :-
    retractall(lote(_,_,_,_,_)),
    retractall(lote_detalle(_,_,_,_,_)),
    retractall(lote_riesgo_api(_,_,_)),
    retractall(lote_historial(_,_,_,_,_)),
    retractall(fermentador(_,_,_,_,_)),
    retractall(fermentador_estado(_,_,_,_)),
    retractall(asignacion(_,_)),
    retractall(control_temperatura_activo(_)),
    retractall(metrica_global(_,_)),
    retractall(metrica_etapa(_,_)),
    retractall(evento(_,_,_)),
    retractall(modo_twin(_)),
    campo(lotes, Estado, Lotes0),
    normalizar_lista(Lotes0, Lotes),
    forall(member(L, Lotes), assert_lote(L)),
    campo(fermentadores, Estado, Fermentadores0),
    normalizar_lista(Fermentadores0, Fermentadores),
    forall(member(F, Fermentadores), assert_fermentador(F)),
    campo(metricas, Estado, Metricas),
    ( is_dict(Metricas) -> dict_pairs(Metricas, _, Pares), forall(member(P, Pares), assert_metrica(P)) ; true ),
    campo(eventos, Estado, Eventos0),
    normalizar_lista(Eventos0, Eventos),
    forall(member(E, Eventos), assert_evento(E)),
    campo(control_activo, Estado, Control0),
    normalizar_bool(Control0, Control),
    assertz(control_temperatura_activo(Control)),
    campo(modo, Estado, Modo0),
    normalizar_modo(Modo0, Modo),
    assertz(modo_twin(Modo)).

campo(Key, Dict, Value) :-
    (   is_dict(Dict),
        get_dict(Key, Dict, Raw)
    ->  Value = Raw
    ;   Value = @(none)
    ).

normalizar_lista(@(none), []) :- !.
normalizar_lista(null, []) :- !.
normalizar_lista(V, V) :- is_list(V), !.
normalizar_lista(_, []).

normalizar_opcional(@(none), undefined) :- !.
normalizar_opcional(null, undefined) :- !.
normalizar_opcional(V, V).

normalizar_numero(@(none), 0) :- !.
normalizar_numero(null, 0) :- !.
normalizar_numero(V, V).

normalizar_texto(@(none), undefined) :- !.
normalizar_texto(null, undefined) :- !.
normalizar_texto(V, A) :- string(V), !, atom_string(A, V).
normalizar_texto(V, V).

normalizar_bool(@(true), true) :- !.
normalizar_bool(@(false), false) :- !.
normalizar_bool(true, true) :- !.
normalizar_bool(false, false) :- !.
normalizar_bool("true", true) :- !.
normalizar_bool("false", false) :- !.
normalizar_bool(V, V).

normalizar_modo(@(none), demo) :- !.
normalizar_modo(undefined, demo) :- !.
normalizar_modo(V, M) :- normalizar_texto(V, M).

normalizar_datos(@(none), D) :- !, dict_create(D, twin, []).
normalizar_datos(D, D).

assert_lote(L) :-
    campo(id, L, Id0), normalizar_opcional(Id0, Id),
    campo(litros, L, Litros0), normalizar_numero(Litros0, Litros),
    campo(etapa, L, Etapa0), normalizar_texto(Etapa0, Etapa),
    campo(fermentador_id, L, F0), normalizar_opcional(F0, FermentadorId),
    campo(en_riesgo, L, R0), normalizar_bool(R0, EnRiesgo),
    campo(motivo_riesgo, L, M0), normalizar_opcional(M0, Motivo),
    campo(nombre, L, Nombre0), normalizar_texto(Nombre0, Nombre),
    campo(receta, L, Receta0), normalizar_texto(Receta0, Receta),
    campo(creado_en, L, C0), normalizar_numero(C0, CreadoEn),
    campo(actualizado_en, L, A0), normalizar_numero(A0, ActualizadoEn),
    assertz(lote(Id, Litros, Etapa, FermentadorId, EnRiesgo)),
    assertz(lote_detalle(Id, Nombre, Receta, CreadoEn, ActualizadoEn)),
    assertz(lote_riesgo_api(Id, EnRiesgo, Motivo)),
    campo(historial, L, H0), normalizar_lista(H0, H),
    forall(member(HE, H), assert_historial(Id, HE)).

assert_historial(Id, H) :-
    campo(ts, H, Ts0), normalizar_numero(Ts0, Ts),
    campo(tipo, H, T0), normalizar_texto(T0, Tipo),
    campo(etapa, H, E0), normalizar_texto(E0, Etapa),
    campo(detalle, H, D0), normalizar_opcional(D0, Detalle),
    assertz(lote_historial(Id, Ts, Tipo, Etapa, Detalle)).

assert_fermentador(F) :-
    campo(id, F, Id0), normalizar_opcional(Id0, Id),
    campo(capacidad_litros, F, C0), normalizar_numero(C0, Capacidad),
    campo(temperatura_actual, F, TA0), normalizar_numero(TA0, TempActual),
    campo(temperatura_objetivo, F, TO0), normalizar_numero(TO0, TempObjetivo),
    campo(tolerancia, F, Tol0), normalizar_numero(Tol0, Tolerancia),
    campo(lote_id, F, L0), normalizar_opcional(L0, LoteId),
    campo(activo, F, A0), normalizar_bool(A0, Activo),
    campo(en_alerta, F, EA0), normalizar_bool(EA0, EnAlerta),
    assertz(fermentador(Id, Capacidad, TempActual, TempObjetivo, Tolerancia)),
    assertz(fermentador_estado(Id, LoteId, Activo, EnAlerta)),
    ( LoteId == undefined -> true ; assertz(asignacion(Id, LoteId)) ).

assert_metrica(Clave-Valor) :-
    (   is_dict(Valor)
    ->  dict_pairs(Valor, _, Pares),
        forall(member(K-V, Pares), assertz(metrica_etapa(K, V)))
    ;   true
    ),
    assertz(metrica_global(Clave, Valor)).

assert_evento(E) :-
    campo(tipo, E, T0), normalizar_texto(T0, Tipo),
    campo(ts, E, Ts0), normalizar_numero(Ts0, Ts),
    campo(datos, E, Datos0), normalizar_datos(Datos0, Datos),
    assertz(evento(Tipo, Ts, Datos)).

%!  etapa_siguiente(?Actual, ?Siguiente) is nondet.
%
%   Secuencia estricta del dominio.

etapa_siguiente(molienda, coccion).
etapa_siguiente(coccion, fermentacion).
etapa_siguiente(fermentacion, maduracion).
etapa_siguiente(maduracion, envasado).
etapa_siguiente(envasado, terminado).

etapas([molienda, coccion, fermentacion, maduracion, envasado, terminado]).
etapa_final(envasado).
etapa_final(terminado).
etapa_activa(fermentacion).
etapa_activa(maduracion).

%!  desviacion(+FermentadorId, -Grados) is nondet.
%!  en_desviacion(+FermentadorId, -Grados) is nondet.
%
%   Desviación absoluta redondeada a 2 decimales, como en Erlang.

desviacion(FermentadorId, Desviacion) :-
    fermentador(FermentadorId, _, Actual, Objetivo, _),
    Bruto is abs(Actual - Objetivo),
    Desviacion is round(Bruto * 100) / 100.

en_desviacion(FermentadorId, Desviacion) :-
    desviacion(FermentadorId, Desviacion),
    fermentador(FermentadorId, _, _, _, Tolerancia),
    Desviacion > Tolerancia.

%!  riesgo(+LoteId) is nondet.
%!  motivo(+LoteId, ?Motivo) is nondet.
%
%   Causa raíz deducida. El estado marcado por Erlang sin causa térmica ni de
%   control se conserva como motivo(estado_lote_riesgo) para auditoría.

riesgo_termico(LoteId, FermentadorId, Desviacion) :-
    asignacion(FermentadorId, LoteId),
    en_desviacion(FermentadorId, Desviacion).

riesgo_control(LoteId) :-
    control_temperatura_activo(false),
    asignacion(_, LoteId).

riesgo(LoteId) :-
    riesgo_termico(LoteId, _, _).
riesgo(LoteId) :-
    riesgo_control(LoteId).
riesgo(LoteId) :-
    lote(LoteId, _, _, _, true).

motivo(LoteId, desviacion_termica(FermentadorId, Desviacion)) :-
    riesgo_termico(LoteId, FermentadorId, Desviacion).
motivo(LoteId, caida_control_temperatura) :-
    riesgo_control(LoteId).
motivo(LoteId, estado_lote_riesgo) :-
    lote(LoteId, _, _, _, true),
    \+ riesgo_termico(LoteId, _, _),
    \+ riesgo_control(LoteId).

motivo(desviacion_termica, FermentadorId, Desviacion) :-
    riesgo_termico(_, FermentadorId, Desviacion).
motivo(caida_control_temperatura) :-
    control_temperatura_activo(false),
    asignacion(_, _).
motivo(estado_lote_riesgo) :-
    lote(LoteId, _, _, _, true),
    \+ riesgo_termico(LoteId, _, _),
    \+ riesgo_control(LoteId).

%!  motivos(+LoteId, -Motivos) is det.
%!  estado_normal(+LoteId) is nondet.

motivos(LoteId, Motivos) :-
    findall(M, motivo(LoteId, M), Motivos).

estado_normal(LoteId) :-
    lote(LoteId, _, _, _, false),
    control_temperatura_activo(true),
    \+ riesgo_termico(LoteId, _, _).

%!  candidatos(+LoteId, -Fermentadores) is det.
%
%   Fermentadores libres con capacidad suficiente, ordenados por id, igual que
%   p80_fermentadores:asignar_automatico/2.

candidatos(LoteId, Fermentadores) :-
    lote(LoteId, Litros, _, _, _),
    findall(F, (
        fermentador(F, Capacidad, _, _, _),
        \+ asignacion(F, _),
        Capacidad >= Litros
    ), Ids),
    msort(Ids, Fermentadores).

mejor_candidato(LoteId, FermentadorId) :-
    candidatos(LoteId, [FermentadorId|_]).

%!  puede_avanzar(+LoteId, ?EtapaDestino, -Estado) is det.
%
%   Estado es permitido o bloqueado(Motivo). Motivo ∈
%   {secuencia_invalida, lote_terminado, fermentador_no_encontrado,
%    capacidad_insuficiente, fermentador_ocupado, sin_fermentador_disponible}.

puede_avanzar(LoteId, Destino, Estado) :-
    lote(LoteId, _, Actual, _, _),
    (   Actual == terminado
    ->  Destino = undefined,
        Estado = bloqueado(lote_terminado)
    ;   etapa_siguiente(Actual, Esperado),
        ( var(Destino) -> Destino = Esperado ; true ),
        (   Destino == Esperado
        ->  verificar_transicion(LoteId, Destino, Estado)
        ;   Estado = bloqueado(secuencia_invalida)
        )
    ).

puede_avanzar_info(LoteId, Destino, Informacion) :-
    puede_avanzar(LoteId, Destino, EstadoCrudo),
    estado_atomo(EstadoCrudo, Estado),
    motivo_estado(EstadoCrudo, Motivo),
    dict_create(Informacion, twin, [
        destino-Destino, estado-Estado, motivo-Motivo
    ]).

verificar_transicion(LoteId, fermentacion, Estado) :-
    !,
    verificar_asignacion_fermentacion(LoteId, Estado).
verificar_transicion(LoteId, _, Estado) :-
    transicion_aprobada(LoteId, Estado).

verificar_asignacion_fermentacion(LoteId, Estado) :-
    lote(LoteId, Litros, _, Preferido, _),
    (   Preferido == undefined
    ->  ( mejor_candidato(LoteId, _) -> Estado = permitido
        ; Estado = bloqueado(sin_fermentador_disponible) )
    ;   verificar_preferido(Preferido, Litros, Estado)
    ).

verificar_preferido(FermentadorId, Litros, Estado) :-
    (   \+ fermentador(FermentadorId, _, _, _, _)
    ->  Estado = bloqueado(fermentador_no_encontrado)
    ;   fermentador(FermentadorId, Capacidad, _, _, _),
        (   Capacidad < Litros
        ->  Estado = bloqueado(capacidad_insuficiente)
        ;   asignacion(FermentadorId, _)
        ->  Estado = bloqueado(fermentador_ocupado)
        ;   Estado = permitido
        )
    ).

transicion_aprobada(_, permitido).

libera_fermentador(LoteId, Destino, FermentadorId) :-
    (   Destino == envasado,
        lote(LoteId, _, _, F, _),
        F \== undefined
    ->  FermentadorId = F
    ;   FermentadorId = undefined
    ).

%!  litros_producidos(-Litros) is det.
%!  litros_en_proceso(-Litros) is det.

litros_producidos(Litros) :-
    suma_litros(terminado, Litros).

litros_en_proceso(Litros) :-
    findall(L, (lote(_, L, Etapa, _, _), Etapa \== terminado), Lista),
    sum_list(Lista, Litros).

suma_litros(Etapa, Litros) :-
    findall(L, lote(_, L, Etapa, _, _), Lista),
    sum_list(Lista, Litros).

%!  derivar_metricas(-Metricas) is det.
%
%   Métricas calculadas desde las instantáneas del gemelo, no copiadas de la API.

derivar_metricas(Metricas) :-
    aggregate_all(count, lote(_,_,_,_,_), TotalLotes),
    aggregate_all(count, (lote(Id,_,_,_,_), once(riesgo(Id))), EnRiesgo),
    aggregate_all(count, asignacion(_,_), FermentadoresActivos),
    aggregate_all(count, fermentador(_,_,_,_,_), FermentadoresTotales),
    aggregate_all(count, en_desviacion(_,_), Desviaciones),
    litros_producidos(LitrosProducidos),
    litros_en_proceso(LitrosEnProceso),
    derivar_lotes_por_etapa(PorEtapa),
    dict_create(Metricas, twin, [
        total_lotes-TotalLotes,
        lotes_en_riesgo-EnRiesgo,
        fermentadores_activos-FermentadoresActivos,
        fermentadores_totales-FermentadoresTotales,
        desviaciones_temperatura-Desviaciones,
        litros_producidos-LitrosProducidos,
        litros_en_proceso-LitrosEnProceso,
        lotes_por_etapa-PorEtapa
    ]).

derivar_lotes_por_etapa(PorEtapa) :-
    etapas(Etapas),
    findall(E-N, (
        member(E, Etapas),
        aggregate_all(count, lote(_,_,E,_,_), N)
    ), Pares),
    dict_create(PorEtapa, twin, Pares).

%!  comparar_metricas(-Comparaciones) is det.

comparar_metricas(Comparaciones) :-
    derivar_metricas(Deducido),
    findall(C, (
        member(K, [total_lotes, lotes_en_riesgo, fermentadores_activos,
                   fermentadores_totales, desviaciones_temperatura,
                   litros_producidos, litros_en_proceso]),
        get_dict(K, Deducido, V),
        metrica_global(K, Reportado),
        comparacion(K, V, Reportado, C)
    ), Escalares),
    findall(C, (
        member(E, [molienda, coccion, fermentacion, maduracion, envasado, terminado]),
        get_dict(lotes_por_etapa, Deducido, PorEtapa),
        get_dict(E, PorEtapa, V),
        metrica_etapa(E, Reportado),
        atom_concat(lotes_por_etapa_, E, K),
        comparacion(K, V, Reportado, C)
    ), PorEtapaComparaciones),
    append(Escalares, PorEtapaComparaciones, Comparaciones).

comparacion(Clave, Deducido, Reportado, Comparacion) :-
    ( iguales(Deducido, Reportado) -> Coincide = true ; Coincide = false ),
    dict_create(Comparacion, twin, [
        clave-Clave, deducido-Deducido, reportado-Reportado, coincide-Coincide
    ]).

iguales(A, B) :-
    ( number(A), number(B) -> A =:= B ; A == B ).

%!  capacidad_disponible(-Capacidad) is det.

capacidad_disponible(Capacidad) :-
    findall(C, (
        fermentador(F, C, _, _, _),
        \+ asignacion(F, _)
    ), Capacidades),
    sum_list(Capacidades, Capacidad).

%!  riesgos(-Riesgos) is det.
%!  transiciones(-Transiciones) is det.
%!  recomendaciones(-Recomendaciones) is det.
%!  auditoria(-Hallazgos) is det.
%!  informe(-Informe) is det.

riesgos(Riesgos) :-
    findall(R, (
        lote(Id, Litros, Etapa, _, _),
        once(riesgo(Id)),
        motivos_dict(Id, Motivos),
        ( riesgo_control(Id) -> Control = false ; Control = true ),
        dict_create(R, twin, [
            lote_id-Id, litros-Litros, etapa-Etapa,
            motivos-Motivos, control_temperatura-Control
        ])
    ), Riesgos).

motivos_dict(LoteId, Motivos) :-
    findall(M, motivo(LoteId, M), Crudos),
    maplist(motivo_dict, Crudos, Motivos).

motivo_dict(desviacion_termica(F, D), Dict) :-
    dict_create(Dict, twin, [
        causa-desviacion_termica, fermentador_id-F, desviacion-D
    ]).
motivo_dict(caida_control_temperatura, Dict) :-
    dict_create(Dict, twin, [causa-caida_control_temperatura]).
motivo_dict(estado_lote_riesgo, Dict) :-
    dict_create(Dict, twin, [causa-estado_lote_riesgo]).

transiciones(Transiciones) :-
    findall(T, (
        lote(Id, _, _, _, _),
        puede_avanzar(Id, Destino, EstadoCrudo),
        estado_atomo(EstadoCrudo, Estado),
        motivo_estado(EstadoCrudo, Motivo),
        candidatos_de_transicion(Id, Destino, Candidatos),
        libera_fermentador(Id, Destino, Libera),
        dict_create(T, twin, [
            lote_id-Id, destino-Destino, estado-Estado, motivo-Motivo,
            fermentadores_candidatos-Candidatos, libera-Libera
        ])
    ), Transiciones).

estado_atomo(bloqueado(_), bloqueado) :- !.
estado_atomo(E, E).

motivo_estado(bloqueado(M), M) :- !.
motivo_estado(permitido, ok).

candidatos_de_transicion(Id, fermentacion, Candidatos) :-
    !,
    candidatos(Id, Candidatos).
candidatos_de_transicion(_, _, []).

recomendaciones(Recomendaciones) :-
    findall(R, recomendacion(R), Rec0),
    sort(Rec0, Recomendaciones).

recomendacion(R) :-
    riesgo_termico(Id, F, D),
    dict_create(R, twin, [
        prioridad-alta, accion-enfriar_o_ajustar_objetivo,
        lote_id-Id, fermentador_id-F, desviacion-D
    ]).
recomendacion(R) :-
    control_temperatura_activo(false),
    asignacion(_, _),
    dict_create(R, twin, [
        prioridad-alta, accion-reiniciar_control_temperatura,
        detalle-Control
    ]),
    Control = 'Lecturas de temperatura no confiables; lotes aislados'.
recomendacion(R) :-
    lote(Id, _, coccion, _, _),
    puede_avanzar(Id, fermentacion, bloqueado(Motivo)),
    dict_create(R, twin, [
        prioridad-media, accion-bloquear_avance, lote_id-Id, motivo-Motivo
    ]).
recomendacion(R) :-
    lote(Id, _, coccion, _, _),
    mejor_candidato(Id, F),
    dict_create(R, twin, [
        prioridad-media, accion-asignar_fermentador,
        lote_id-Id, fermentador_id-F
    ]).

auditoria(Hallazgos) :-
    findall(H, hallazgo(H), Hallazgos).

hallazgo(H) :-
    asignacion(F, Id),
    lote(Id, _, Etapa, _, _),
    etapa_final(Etapa),
    dict_create(H, twin, [
        tipo-asignacion_activa_en_etapa_final,
        fermentador_id-F, lote_id-Id, etapa-Etapa
    ]).
hallazgo(H) :-
    lote(Id, _, Etapa, F, _),
    etapa_activa(Etapa),
    F \== undefined,
    \+ asignacion(F, Id),
    dict_create(H, twin, [
        tipo-lote_activo_sin_asignacion,
        fermentador_id-F, lote_id-Id, etapa-Etapa
    ]).
hallazgo(H) :-
    findall(par(F, A, B), (
        asignacion(F, A), asignacion(F, B), A @< B
    ), Duplicados),
    member(par(F, A, B), Duplicados),
    dict_create(H, twin, [
        tipo-exclusividad_violada,
        fermentador_id-F, lotes-[A, B]
    ]).
hallazgo(H) :-
    fermentador_estado(F, _, _, EnAlerta),
    ( en_desviacion(F, _) -> Esperado = true ; Esperado = false ),
    EnAlerta \== Esperado,
    dict_create(H, twin, [
        tipo-alerta_temperatura_inconsistente,
        fermentador_id-F, reportado-EnAlerta, deducido-Esperado
    ]).

informe(Informe) :-
    ( modo_twin(Modo) -> true ; Modo = sin_sincronizar ),
    riesgos(Riesgos),
    transiciones(Transiciones),
    recomendaciones(Recomendaciones),
    auditoria(Auditoria),
    derivar_metricas(Metricas),
    comparar_metricas(Comparaciones),
    capacidad_disponible(Capacidad),
    aggregate_all(count, lote(_,_,_,_,_), TotalLotes),
    dict_create(Informe, twin, [
        modo-Modo,
        total_lotes-TotalLotes,
        riesgos-Riesgos,
        transiciones-Transiciones,
        recomendaciones-Recomendaciones,
        auditoria-Auditoria,
        metricas-Metricas,
        comparacion_metricas-Comparaciones,
        capacidad_disponible-Capacidad
    ]).
