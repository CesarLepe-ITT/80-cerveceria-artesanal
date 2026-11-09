%%% @doc Proceso periodico de simulacion y control de temperatura.
%%%
%%% En un sistema real este proceso leeria sensores. Aqui simula una deriva
%%% suave hacia la temperatura objetivo y publica lecturas por el bus de eventos.
-module(p80_control_temperatura).
-behaviour(gen_server).

-export([start_link/0, paso/0, simular_desviacion/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Ejecuta un ciclo de simulacion inmediatamente.
paso() ->
    Fermentadores = p80_fermentadores:listar(),
    lists:foreach(fun simular/1, Fermentadores),
    ok.

%% @doc Fuerza una desviacion respecto al objetivo (util para demos y caos).
simular_desviacion(FermentadorId, Grados) ->
    case p80_fermentadores:estado(FermentadorId) of
        Datos when is_map(Datos) ->
            Objetivo = maps:get(temperatura_objetivo, Datos),
            p80_fermentadores:actualizar_temperatura_actual(
                FermentadorId,
                Objetivo + Grados
            );
        {error, Motivo} ->
            {error, Motivo}
    end.

init([]) ->
    p80_metricas:inc(inicios_control_temperatura),
    p80_eventos:publicar(control_temperatura_iniciado, #{
        pid => self(),
        intervalo_ms => intervalo()
    }),
    avisar_vigilante(),
    programar(intervalo()),
    {ok, #{intervalo => intervalo()}}.

handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info(tick, State) ->
    catch paso(),
    programar(maps:get(intervalo, State)),
    {noreply, State};
handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    ok.

intervalo() ->
    application:get_env(p80_cerveceria_artesanal, control_temperatura_ms, 5000).

programar(Intervalo) when is_integer(Intervalo), Intervalo > 0 ->
    erlang:send_after(Intervalo, self(), tick);
programar(_Intervalo) ->
    ok.

avisar_vigilante() ->
    case whereis(p80_vigilante) of
        undefined -> ok;
        Pid -> Pid ! {control_iniciado, self()}, ok
    end.

simular(Datos) ->
    Id = maps:get(id, Datos),
    Actual = maps:get(temperatura_actual, Datos),
    Objetivo = maps:get(temperatura_objetivo, Datos),
    Delta = Objetivo - Actual,
    Ruido = (rand:uniform() - 0.5) * 0.08,
    Nueva = p80_util:redondear(Actual + Delta * 0.1 + Ruido),
    case abs(Nueva - Actual) >= 0.01 of
        true -> catch p80_fermentadores:actualizar_temperatura_actual(Id, Nueva);
        false -> ok
    end.
