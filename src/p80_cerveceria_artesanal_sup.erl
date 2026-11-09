%%% @doc Supervisor principal de la cerveceria.
%%%
%%% Estrategia `rest_for_one' porque hay dependencias de arranque:
%%% registro -> eventos -> metricas -> supervisores de dominio -> HTTP ->
%%% vigilante -> control de temperatura.
-module(p80_cerveceria_artesanal_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Hijos = [
        trabajador(p80_registro),
        trabajador(p80_eventos),
        trabajador(p80_metricas),
        supervisor_hijo(p80_lote_sup),
        supervisor_hijo(p80_fermentador_sup),
        trabajador(p80_http),
        trabajador(p80_vigilante),
        trabajador(p80_control_temperatura)
    ],
    {ok, {#{strategy => rest_for_one, intensity => 5, period => 30}, Hijos}}.

trabajador(Modulo) ->
    #{
        id => Modulo,
        start => {Modulo, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [Modulo]
    }.

supervisor_hijo(Modulo) ->
    #{
        id => Modulo,
        start => {Modulo, start_link, []},
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [Modulo]
    }.
