%%% @doc Maquina de estados de un lote de cerveza.
%%%
%%% Etapas: molienda -> coccion -> fermentacion -> maduracion -> envasado
%%% -> terminado. Solo se permite avanzar a la etapa inmediata siguiente.
-module(p80_lote).
-behaviour(gen_statem).

-export([
    start_link/2,
    child_spec/2,
    estado/1,
    avanzar/2,
    marcar_en_riesgo/2,
    normalizar_riesgo/2,
    historial/1,
    pid/1
]).

-export([init/1, callback_mode/0, handle_event/4, terminate/3]).

-define(HISTORIAL_MAX, 200).

start_link(Id, Datos) ->
    gen_statem:start_link(p80_registro:via(lote, Id), ?MODULE, {Id, Datos}, []).

child_spec(Id, Datos) ->
    #{
        id => {lote, Id},
        start => {?MODULE, start_link, [Id, Datos]},
        restart => transient,
        shutdown => 5000,
        type => worker,
        modules => [?MODULE]
    }.

estado(Id) ->
    llamar(Id, estado).

avanzar(Id, Opciones) when is_map(Opciones) ->
    llamar(Id, {avanzar, Opciones}).

marcar_en_riesgo(Id, Motivo) ->
    llamar(Id, {marcar_en_riesgo, Motivo}).

normalizar_riesgo(Id, Motivo) ->
    llamar(Id, {normalizar_riesgo, Motivo}).

historial(Id) ->
    llamar(Id, historial).

pid(Id) ->
    p80_registro:pid_lote(Id).

init({Id, DatosIniciales}) ->
    Previo = p80_registro:datos_lote(Id),
    {Datos, Reinicio} = case Previo of
        undefined ->
            Inicial = normalizar_inicial(Id, DatosIniciales),
            {agregar_historial(creado, <<"Lote creado">>, Inicial), false};
        _ ->
            {Previo#{id => Id}, true}
    end,
    p80_registro:actualizar_lote(Id, Datos),
    case Reinicio of
        true ->
            p80_eventos:publicar(lote_reiniciado, #{
                lote_id => Id,
                etapa => maps:get(etapa, Datos)
            });
        false ->
            p80_eventos:publicar(lote_creado, #{
                lote_id => Id,
                nombre => maps:get(nombre, Datos),
                receta => maps:get(receta, Datos),
                litros => maps:get(litros, Datos),
                etapa => maps:get(etapa, Datos)
            })
    end,
    {ok, maps:get(etapa, Datos), Datos}.

callback_mode() ->
    handle_event_function.

handle_event({call, From}, estado, _Estado, Datos) ->
    {keep_state, Datos, [{reply, From, Datos}]};
handle_event({call, From}, historial, _Estado, Datos) ->
    {keep_state, Datos, [{reply, From, maps:get(historial, Datos)}]};
handle_event({call, From}, {avanzar, Opciones}, Estado, Datos) ->
    case siguiente(Estado) of
        undefined ->
            {keep_state, Datos, [{reply, From, {error, lote_terminado}}]};
        Siguiente ->
            case preparar_transicion(Estado, Siguiente, Opciones, Datos) of
                {ok, DatosPreparado, EventosExtra} ->
                    Ts = p80_util:ahora_ms(),
                    Datos2 = DatosPreparado#{
                        etapa => Siguiente,
                        actualizado_en => Ts
                    },
                    Detalle = detalle_transicion(Estado, Siguiente),
                    Datos3 = agregar_historial(transicion, Detalle, Datos2),
                    p80_registro:actualizar_lote(maps:get(id, Datos3), Datos3),
                    publicar_transicion(Estado, Siguiente, Datos3),
                    lists:foreach(
                        fun({Tipo, DatosEvento}) -> p80_eventos:publicar(Tipo, DatosEvento) end,
                        EventosExtra
                    ),
                    {next_state, Siguiente, Datos3, [{reply, From, {ok, Datos3}}]};
                {error, Motivo} ->
                    {keep_state, Datos, [{reply, From, {error, Motivo}}]}
            end
    end;
handle_event({call, From}, {marcar_en_riesgo, Motivo}, _Estado, Datos) ->
    Id = maps:get(id, Datos),
    YaEnRiesgo = maps:get(en_riesgo, Datos, false),
    Datos2 = Datos#{
        en_riesgo => true,
        motivo_riesgo => Motivo,
        actualizado_en => p80_util:ahora_ms()
    },
    Datos3 = agregar_historial(riesgo, Motivo, Datos2),
    p80_registro:actualizar_lote(Id, Datos3),
    case YaEnRiesgo of
        true -> ok;
        false ->
            p80_eventos:publicar(alerta_lote, #{
                lote_id => Id,
                nombre => maps:get(nombre, Datos3),
                motivo => Motivo,
                etapa => maps:get(etapa, Datos3),
                severidad => alta
            })
    end,
    {keep_state, Datos3, [{reply, From, ok}]};
handle_event({call, From}, {normalizar_riesgo, Motivo}, _Estado, Datos) ->
    Id = maps:get(id, Datos),
    case maps:get(en_riesgo, Datos, false) of
        false ->
            {keep_state, Datos, [{reply, From, ok}]};
        true ->
            Datos2 = Datos#{
                en_riesgo => false,
                motivo_riesgo => undefined,
                actualizado_en => p80_util:ahora_ms()
            },
            Datos3 = agregar_historial(normalizado, Motivo, Datos2),
            p80_registro:actualizar_lote(Id, Datos3),
            p80_eventos:publicar(lote_normalizado, #{
                lote_id => Id,
                nombre => maps:get(nombre, Datos3),
                motivo => Motivo
            }),
            {keep_state, Datos3, [{reply, From, ok}]}
    end;
handle_event(cast, _Mensaje, _Estado, _Datos) ->
    keep_state_and_data;
handle_event(info, _Informacion, _Estado, _Datos) ->
    keep_state_and_data.

terminate(_Razon, _Estado, _Datos) ->
    ok.

llamar(Id, Mensaje) ->
    try gen_statem:call(p80_registro:via(lote, Id), Mensaje, 5000) of
        Respuesta -> Respuesta
    catch
        exit:_ -> {error, no_encontrado}
    end.

normalizar_inicial(Id, Datos) ->
    Ts = p80_util:ahora_ms(),
    #{
        id => Id,
        nombre => maps:get(nombre, Datos),
        receta => maps:get(receta, Datos),
        litros => maps:get(litros, Datos),
        etapa => molienda,
        fermentador_id => maps:get(fermentador_id, Datos, undefined),
        en_riesgo => false,
        motivo_riesgo => undefined,
        creado_en => Ts,
        actualizado_en => Ts,
        historial => []
    }.

siguiente(molienda) -> coccion;
siguiente(coccion) -> fermentacion;
siguiente(fermentacion) -> maduracion;
siguiente(maduracion) -> envasado;
siguiente(envasado) -> terminado;
siguiente(terminado) -> undefined.

preparar_transicion(_Estado, fermentacion, Opciones, Datos) ->
    asignar_fermentador(Datos, Opciones);
preparar_transicion(_Estado, envasado, _Opciones, Datos) ->
    liberar_fermentador(Datos);
preparar_transicion(_Estado, _Siguiente, _Opciones, Datos) ->
    {ok, Datos, []}.

asignar_fermentador(Datos, Opciones) ->
    LoteId = maps:get(id, Datos),
    Litros = maps:get(litros, Datos),
    Solicitado = case maps:get(fermentador_id, Opciones, undefined) of
        undefined -> maps:get(fermentador_id, Datos, undefined);
        Id -> Id
    end,
    case Solicitado of
        undefined ->
            case p80_fermentadores:asignar_automatico(LoteId, Litros) of
                {ok, FermentadorId} ->
                    Datos2 = Datos#{fermentador_id => FermentadorId},
                    {ok, Datos2, [{
                        fermentador_asignado,
                        #{lote_id => LoteId, fermentador_id => FermentadorId}
                    }]};
                {error, Motivo} ->
                    {error, Motivo}
            end;
        FermentadorId ->
            case validar_asignacion(FermentadorId, LoteId, Litros) of
                ok ->
                    Datos2 = Datos#{fermentador_id => FermentadorId},
                    {ok, Datos2, [{
                        fermentador_asignado,
                        #{lote_id => LoteId, fermentador_id => FermentadorId}
                    }]};
                {error, Motivo} ->
                    {error, Motivo}
            end
    end.

validar_asignacion(FermentadorId, LoteId, Litros) ->
    case p80_fermentadores:estado(FermentadorId) of
        Fermentador when is_map(Fermentador) ->
            Capacidad = maps:get(capacidad_litros, Fermentador),
            case Capacidad >= Litros of
                false ->
                    {error, capacidad_insuficiente};
                true ->
                    case p80_fermentadores:asignar(FermentadorId, LoteId) of
                        {ok, _} -> ok;
                        {error, Motivo} -> {error, Motivo}
                    end
            end;
        {error, no_encontrado} ->
            {error, fermentador_no_encontrado}
    end.

liberar_fermentador(Datos) ->
    LoteId = maps:get(id, Datos),
    case maps:get(fermentador_id, Datos, undefined) of
        undefined ->
            {ok, Datos, []};
        FermentadorId ->
            case p80_fermentadores:liberar_lote(FermentadorId, LoteId) of
                ok ->
                    {ok, Datos, [{
                        fermentador_liberado,
                        #{lote_id => LoteId, fermentador_id => FermentadorId}
                    }]};
                {error, _} ->
                    {ok, Datos, []}
            end
    end.

detalle_transicion(Anterior, Siguiente) ->
    iolist_to_binary(io_lib:format("Etapa ~s -> ~s", [Anterior, Siguiente])).

publicar_transicion(Anterior, Siguiente, Datos) ->
    DatosEvento = #{
        lote_id => maps:get(id, Datos),
        nombre => maps:get(nombre, Datos),
        etapa_anterior => Anterior,
        etapa => Siguiente,
        fermentador_id => maps:get(fermentador_id, Datos, undefined)
    },
    p80_eventos:publicar(etapa_avanzada, DatosEvento),
    case Siguiente of
        terminado -> p80_eventos:publicar(lote_terminado, DatosEvento);
        _ -> ok
    end.

agregar_historial(Tipo, Detalle, Datos) ->
    Ts = p80_util:ahora_ms(),
    Entrada = #{
        ts => Ts,
        tipo => Tipo,
        etapa => maps:get(etapa, Datos),
        detalle => Detalle
    },
    Historial = maps:get(historial, Datos, []),
    Recortado = lists:sublist([Entrada | Historial], ?HISTORIAL_MAX),
    Datos#{historial => Recortado, actualizado_en => Ts}.
