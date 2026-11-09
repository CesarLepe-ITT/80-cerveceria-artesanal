%%% @doc Supervisor dinamico de lotes.
-module(p80_lote_sup).
-behaviour(supervisor).

-export([start_link/0, iniciar_lote/2, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

iniciar_lote(Id, Datos) ->
    supervisor:start_child(?MODULE, p80_lote:child_spec(Id, Datos)).

init([]) ->
    Hijos = lists:filtermap(
        fun({Id, Pid, Datos}) ->
            recuperar(Id, Pid, Datos)
        end,
        p80_registro:listar_lotes()
    ),
    {ok, {#{strategy => one_for_one, intensity => 10, period => 60}, Hijos}}.

recuperar(_Id, _Pid, undefined) ->
    false;
recuperar(Id, Pid, Datos) ->
    Vivo = is_pid(Pid) andalso is_process_alive(Pid),
    case Vivo of
        true -> false;
        false -> {true, p80_lote:child_spec(Id, Datos)}
    end.
