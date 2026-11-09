%%% @doc Metricas de negocio y salida compatible con Prometheus.
-module(p80_metricas).
-behaviour(gen_server).

-export([start_link/0, inc/1, contador/1, resumen/0, prometheus/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLA, p80_metricas_contadores).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

inc(Clave) when is_atom(Clave) ->
    try
        ets:update_counter(?TABLA, Clave, {2, 1}, {Clave, 0})
    catch
        error:badarg -> 0
    end.

contador(Clave) ->
    try ets:lookup(?TABLA, Clave) of
        [{Clave, Valor}] -> Valor;
        [] -> 0
    catch
        error:badarg -> 0
    end.

%% @doc Resumen en forma de mapa listo para JSON.
resumen() ->
    Lotes = listar_lotes(),
    Fermentadores = listar_fermentadores(),
    Etapas = p80_util:etapas(),
    PorEtapa = maps:from_list([
        {Etapa, length([L || L <- Lotes, maps:get(etapa, L, undefined) =:= Etapa])}
     || Etapa <- Etapas
    ]),
    LitrosProducidos = sumar_litros([L || L <- Lotes, maps:get(etapa, L, undefined) =:= terminado]),
    LitrosEnProceso = sumar_litros([L || L <- Lotes, maps:get(etapa, L, undefined) =/= terminado]),
    Activos = length([
        F || F <- Fermentadores,
             maps:get(lote_id, F, undefined) =/= undefined
    ]),
    Desviaciones = length([
        F || F <- Fermentadores, maps:get(en_alerta, F, false) =:= true
    ]),
    EnRiesgo = length([
        L || L <- Lotes, maps:get(en_riesgo, L, false) =:= true
    ]),
    #{
        lotes_por_etapa => PorEtapa,
        total_lotes => length(Lotes),
        lotes_en_riesgo => EnRiesgo,
        fermentadores_activos => Activos,
        fermentadores_totales => length(Fermentadores),
        desviaciones_temperatura => Desviaciones,
        litros_producidos => LitrosProducidos,
        litros_en_proceso => LitrosEnProceso,
        eventos_registrados => eventos_total(),
        alertas_temperatura => contador(alertas_temperatura),
        caidas_control_temperatura => contador(caidas_control_temperatura),
        inicios_control_temperatura => contador(inicios_control_temperatura)
    }.

%% @doc Metricas en formato de texto Prometheus 0.0.4.
prometheus() ->
    Resumen = resumen(),
    PorEtapa = maps:get(lotes_por_etapa, Resumen),
    [
        "# HELP cerveceria_lotes_por_etapa Cantidad de lotes en cada etapa.\n",
        "# TYPE cerveceria_lotes_por_etapa gauge\n",
        [
            io_lib:format(
                "cerveceria_lotes_por_etapa{etapa=\"~s\"} ~p~n",
                [atom_to_list(Etapa), maps:get(Etapa, PorEtapa, 0)]
            )
         || Etapa <- p80_util:etapas()
        ],
        "# HELP cerveceria_lotes_en_riesgo Lotes marcados en riesgo.\n",
        "# TYPE cerveceria_lotes_en_riesgo gauge\n",
        io_lib:format("cerveceria_lotes_en_riesgo ~p~n", [maps:get(lotes_en_riesgo, Resumen)]),
        "# HELP cerveceria_fermentadores_activos Fermentadores con lote asignado.\n",
        "# TYPE cerveceria_fermentadores_activos gauge\n",
        io_lib:format("cerveceria_fermentadores_activos ~p~n", [maps:get(fermentadores_activos, Resumen)]),
        "# HELP cerveceria_fermentadores_totales Fermentadores registrados.\n",
        "# TYPE cerveceria_fermentadores_totales gauge\n",
        io_lib:format("cerveceria_fermentadores_totales ~p~n", [maps:get(fermentadores_totales, Resumen)]),
        "# HELP cerveceria_desviaciones_temperatura Fermentadores fuera de tolerancia.\n",
        "# TYPE cerveceria_desviaciones_temperatura gauge\n",
        io_lib:format("cerveceria_desviaciones_temperatura ~p~n", [maps:get(desviaciones_temperatura, Resumen)]),
        "# HELP cerveceria_litros_producidos Litros de lotes terminados.\n",
        "# TYPE cerveceria_litros_producidos counter\n",
        io_lib:format("cerveceria_litros_producidos ~p~n", [maps:get(litros_producidos, Resumen)]),
        "# HELP cerveceria_litros_en_proceso Litros de lotes no terminados.\n",
        "# TYPE cerveceria_litros_en_proceso gauge\n",
        io_lib:format("cerveceria_litros_en_proceso ~p~n", [maps:get(litros_en_proceso, Resumen)]),
        "# HELP cerveceria_alertas_temperatura Alertas de temperatura emitidas.\n",
        "# TYPE cerveceria_alertas_temperatura counter\n",
        io_lib:format("cerveceria_alertas_temperatura ~p~n", [maps:get(alertas_temperatura, Resumen)]),
        "# HELP cerveceria_caidas_control_temperatura Caidas del control de temperatura.\n",
        "# TYPE cerveceria_caidas_control_temperatura counter\n",
        io_lib:format("cerveceria_caidas_control_temperatura ~p~n", [maps:get(caidas_control_temperatura, Resumen)]),
        "# HELP cerveceria_inicios_control_temperatura Inicios del control de temperatura.\n",
        "# TYPE cerveceria_inicios_control_temperatura counter\n",
        io_lib:format("cerveceria_inicios_control_temperatura ~p~n", [maps:get(inicios_control_temperatura, Resumen)])
    ].

init([]) ->
    ets:new(?TABLA, [named_table, public, set, {write_concurrency, true}]),
    {ok, #{}}.

handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    ok.

listar_lotes() ->
    try p80_lotes:listar() catch _:_ -> [] end.

listar_fermentadores() ->
    try p80_fermentadores:listar() catch _:_ -> [] end.

eventos_total() ->
    try p80_eventos:total() catch _:_ -> 0 end.

sumar_litros(Lotes) ->
    lists:sum([maps:get(litros, L, 0) || L <- Lotes]).
