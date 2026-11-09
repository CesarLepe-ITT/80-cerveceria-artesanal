%%% @doc Proceso de control de un fermentador.
%%%
%%% Mantiene temperatura actual, temperatura objetivo, tolerancia y el lote
%%% asignado. Detecta desviaciones y notifica al lote para marcarlo en riesgo.
-module(p80_fermentador).
-behaviour(gen_server).

-export([
    start_link/2,
    child_spec/2,
    estado/1,
    fijar_temperatura_objetivo/2,
    actualizar_temperatura_actual/2,
    asignar_lote/2,
    liberar_lote/2,
    pid/1
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link(Id, Datos) ->
    gen_server:start_link(p80_registro:via(fermentador, Id), ?MODULE, {Id, Datos}, []).

child_spec(Id, Datos) ->
    #{
        id => {fermentador, Id},
        start => {?MODULE, start_link, [Id, Datos]},
        restart => transient,
        shutdown => 5000,
        type => worker,
        modules => [?MODULE]
    }.

estado(Id) ->
    llamar(Id, estado).

fijar_temperatura_objetivo(Id, Temperatura) ->
    llamar(Id, {fijar_objetivo, Temperatura}).

actualizar_temperatura_actual(Id, Temperatura) ->
    llamar(Id, {actualizar_actual, Temperatura}).

asignar_lote(Id, LoteId) ->
    llamar(Id, {asignar_lote, LoteId}).

liberar_lote(Id, LoteId) ->
    llamar(Id, {liberar_lote, LoteId}).

pid(Id) ->
    p80_registro:pid_fermentador(Id).

init({Id, DatosIniciales}) ->
    Previo = p80_registro:datos_fermentador(Id),
    {Datos, Reinicio} = case Previo of
        undefined ->
            {normalizar_inicial(Id, DatosIniciales), false};
        _ ->
            {Previo#{id => Id}, true}
    end,
    p80_registro:actualizar_fermentador(Id, Datos),
    case Reinicio of
        true ->
            p80_eventos:publicar(fermentador_reiniciado, #{
                fermentador_id => Id,
                nombre => maps:get(nombre, Datos),
                temperatura_actual => maps:get(temperatura_actual, Datos),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos)
            });
        false ->
            p80_eventos:publicar(fermentador_creado, #{
                fermentador_id => Id,
                nombre => maps:get(nombre, Datos),
                capacidad_litros => maps:get(capacidad_litros, Datos),
                temperatura_actual => maps:get(temperatura_actual, Datos),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos),
                tolerancia => maps:get(tolerancia, Datos)
            })
    end,
    case maps:get(en_alerta, Datos, false) of
        true -> notificar_alerta(Datos, <<"Desviacion de temperatura al iniciar">>);
        false -> ok
    end,
    {ok, Datos}.

handle_call(estado, _From, Datos) ->
    {reply, Datos, Datos};
handle_call({fijar_objetivo, Temperatura}, _From, Datos) ->
    case p80_util:numero(Temperatura) of
        {ok, Temp} when Temp >= -20.0, Temp =< 120.0 ->
            AnteriorAlerta = maps:get(en_alerta, Datos),
            Datos2 = recalcular(Datos#{temperatura_objetivo => p80_util:redondear(Temp)}),
            Datos3 = Datos2#{actualizado_en => p80_util:ahora_ms()},
            persistir(Datos3),
            p80_eventos:publicar(temperatura_objetivo_actualizada, #{
                fermentador_id => maps:get(id, Datos3),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos3),
                temperatura_actual => maps:get(temperatura_actual, Datos3),
                desviacion => maps:get(desviacion, Datos3)
            }),
            gestionar_cambio_alerta(AnteriorAlerta, Datos3),
            {reply, {ok, Datos3}, Datos3};
        {ok, _} ->
            {reply, {error, {validacion, <<"temperatura_objetivo fuera de rango">>}}, Datos};
        error ->
            {reply, {error, {validacion, <<"temperatura_objetivo debe ser numerica">>}}, Datos}
    end;
handle_call({actualizar_actual, Temperatura}, _From, Datos) ->
    case p80_util:numero(Temperatura) of
        {ok, Temp} when Temp >= -20.0, Temp =< 120.0 ->
            AnteriorAlerta = maps:get(en_alerta, Datos),
            Datos2 = recalcular(Datos#{temperatura_actual => p80_util:redondear(Temp)}),
            Datos3 = Datos2#{actualizado_en => p80_util:ahora_ms()},
            persistir(Datos3),
            p80_eventos:publicar(lectura_temperatura, #{
                fermentador_id => maps:get(id, Datos3),
                temperatura_actual => maps:get(temperatura_actual, Datos3),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos3),
                desviacion => maps:get(desviacion, Datos3),
                en_alerta => maps:get(en_alerta, Datos3)
            }),
            gestionar_cambio_alerta(AnteriorAlerta, Datos3),
            {reply, {ok, Datos3}, Datos3};
        {ok, _} ->
            {reply, {error, {validacion, <<"temperatura_actual fuera de rango">>}}, Datos};
        error ->
            {reply, {error, {validacion, <<"temperatura_actual debe ser numerica">>}}, Datos}
    end;
handle_call({asignar_lote, LoteId}, _From, Datos) ->
    Actual = maps:get(lote_id, Datos, undefined),
    case Actual of
        undefined ->
            Datos2 = Datos#{
                lote_id => LoteId,
                activo => true,
                actualizado_en => p80_util:ahora_ms()
            },
            persistir(Datos2),
            p80_eventos:publicar(fermentador_asignado, #{
                fermentador_id => maps:get(id, Datos2),
                lote_id => LoteId,
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos2)
            }),
            case maps:get(en_alerta, Datos2, false) of
                true -> notificar_alerta(Datos2, <<"Fermentador asignado con temperatura fuera de rango">>);
                false -> ok
            end,
            {reply, {ok, Datos2}, Datos2};
        LoteId ->
            {reply, {ok, Datos}, Datos};
        _Otro ->
            {reply, {error, fermentador_ocupado}, Datos}
    end;
handle_call({liberar_lote, LoteId}, _From, Datos) ->
    case maps:get(lote_id, Datos, undefined) of
        undefined ->
            {reply, ok, Datos};
        LoteId ->
            Datos2 = Datos#{
                lote_id => undefined,
                activo => false,
                actualizado_en => p80_util:ahora_ms()
            },
            persistir(Datos2),
            p80_eventos:publicar(fermentador_liberado, #{
                fermentador_id => maps:get(id, Datos2),
                lote_id => LoteId
            }),
            {reply, ok, Datos2};
        _Otro ->
            {reply, {error, lote_no_asignado}, Datos}
    end;
handle_call(_Solicitud, _From, Datos) ->
    {reply, {error, desconocido}, Datos}.

handle_cast(_Mensaje, Datos) ->
    {noreply, Datos}.

handle_info(_Informacion, Datos) ->
    {noreply, Datos}.

terminate(_Razon, _Datos) ->
    ok.

llamar(Id, Mensaje) ->
    try gen_server:call(p80_registro:via(fermentador, Id), Mensaje, 5000) of
        Respuesta -> Respuesta
    catch
        exit:_ -> {error, no_encontrado}
    end.

normalizar_inicial(Id, Datos) ->
    Ts = p80_util:ahora_ms(),
    Base = #{
        id => Id,
        nombre => maps:get(nombre, Datos),
        capacidad_litros => maps:get(capacidad_litros, Datos),
        temperatura_actual => maps:get(temperatura_actual, Datos),
        temperatura_objetivo => maps:get(temperatura_objetivo, Datos),
        tolerancia => maps:get(tolerancia, Datos),
        lote_id => undefined,
        activo => false,
        creado_en => Ts,
        actualizado_en => Ts
    },
    recalcular(Base).

recalcular(Datos) ->
    Actual = maps:get(temperatura_actual, Datos),
    Objetivo = maps:get(temperatura_objetivo, Datos),
    Tolerancia = maps:get(tolerancia, Datos),
    Desviacion = p80_util:redondear(abs(Actual - Objetivo)),
    EnAlerta = Desviacion > Tolerancia,
    Datos#{desviacion => Desviacion, en_alerta => EnAlerta}.

persistir(Datos) ->
    p80_registro:actualizar_fermentador(maps:get(id, Datos), Datos).

gestionar_cambio_alerta(Anterior, Datos) ->
    Actual = maps:get(en_alerta, Datos),
    case {Anterior, Actual} of
        {false, true} ->
            p80_metricas:inc(alertas_temperatura),
            p80_eventos:publicar(alerta_temperatura, #{
                fermentador_id => maps:get(id, Datos),
                temperatura_actual => maps:get(temperatura_actual, Datos),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos),
                desviacion => maps:get(desviacion, Datos),
                tolerancia => maps:get(tolerancia, Datos),
                lote_id => maps:get(lote_id, Datos, undefined),
                severidad => alta
            }),
            notificar_alerta(Datos, <<"Temperatura fuera de tolerancia">>);
        {true, false} ->
            p80_eventos:publicar(temperatura_normalizada, #{
                fermentador_id => maps:get(id, Datos),
                temperatura_actual => maps:get(temperatura_actual, Datos),
                temperatura_objetivo => maps:get(temperatura_objetivo, Datos),
                lote_id => maps:get(lote_id, Datos, undefined)
            }),
            notificar_normalizacion(Datos);
        _ ->
            ok
    end.

notificar_alerta(Datos, Motivo) ->
    case maps:get(lote_id, Datos, undefined) of
        undefined ->
            ok;
        LoteId ->
            spawn(fun() ->
                catch p80_lotes:marcar_en_riesgo(LoteId, Motivo)
            end),
            ok
    end.

notificar_normalizacion(Datos) ->
    case maps:get(lote_id, Datos, undefined) of
        undefined ->
            ok;
        LoteId ->
            spawn(fun() ->
                catch p80_lotes:normalizar_riesgo(LoteId, <<"Temperatura normalizada">>)
            end),
            ok
    end.
