%%% @doc Registro central basado en ETS.
%%%
%%% Implementa el modulo `via' para los procesos dinamicos y conserva el
%%% ultimo snapshot de cada lote y fermentador. Cuando un proceso cae, su
%%% supervisor lo reinicia con los argumentos originales; durante `init/1'
%%% el proceso recupera el snapshot actual desde este registro.
-module(p80_registro).
-behaviour(gen_server).

-export([
    start_link/0,
    via/2,
    nuevo_id/1,
    actualizar_lote/2,
    datos_lote/1,
    pid_lote/1,
    listar_lotes/0,
    eliminar_lote/1,
    actualizar_fermentador/2,
    datos_fermentador/1,
    pid_fermentador/1,
    listar_fermentadores/0,
    eliminar_fermentador/1,
    register_name/2,
    unregister_name/1,
    whereis_name/1,
    send/2
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLA_LOTES, p80_registro_lotes).
-define(TABLA_FERMENTADORES, p80_registro_fermentadores).
-define(TABLA_CONTADORES, p80_registro_contadores).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Nombre `via' para un lote o fermentador.
via(lote, Id) -> {via, ?MODULE, {lote, Id}};
via(fermentador, Id) -> {via, ?MODULE, {fermentador, Id}}.

%% @doc Genera un identificador secuencial por tipo.
nuevo_id(Tipo) when Tipo =:= lote; Tipo =:= fermentador ->
    ets:update_counter(?TABLA_CONTADORES, Tipo, {2, 1}, {Tipo, 0}).

actualizar_lote(Id, Datos) ->
    gen_server:call(?MODULE, {actualizar, lote, Id, Datos}).

datos_lote(Id) ->
    case buscar(?TABLA_LOTES, Id) of
        {_, _, Datos} -> Datos;
        undefined -> undefined
    end.

pid_lote(Id) ->
    case buscar(?TABLA_LOTES, Id) of
        {_, Pid, _} -> Pid;
        undefined -> undefined
    end.

listar_lotes() ->
    listar(?TABLA_LOTES).

eliminar_lote(Id) ->
    gen_server:call(?MODULE, {eliminar, lote, Id}).

actualizar_fermentador(Id, Datos) ->
    gen_server:call(?MODULE, {actualizar, fermentador, Id, Datos}).

datos_fermentador(Id) ->
    case buscar(?TABLA_FERMENTADORES, Id) of
        {_, _, Datos} -> Datos;
        undefined -> undefined
    end.

pid_fermentador(Id) ->
    case buscar(?TABLA_FERMENTADORES, Id) of
        {_, Pid, _} -> Pid;
        undefined -> undefined
    end.

listar_fermentadores() ->
    listar(?TABLA_FERMENTADORES).

eliminar_fermentador(Id) ->
    gen_server:call(?MODULE, {eliminar, fermentador, Id}).

%% Callbacks de `via'.
register_name({Tipo, Id}, Pid) ->
    gen_server:call(?MODULE, {registrar, Tipo, Id, Pid}).

unregister_name({Tipo, Id}) ->
    case whereis_name({Tipo, Id}) of
        undefined -> ok;
        Pid -> gen_server:call(?MODULE, {desregistrar, Tipo, Id, Pid})
    end.

whereis_name({Tipo, Id}) ->
    try buscar(tabla(Tipo), Id) of
        {_, Pid, _} when is_pid(Pid) -> Pid;
        _ -> undefined
    catch
        error:badarg -> undefined
    end;
whereis_name(_) ->
    undefined.

send(Nombre, Mensaje) ->
    case whereis_name(Nombre) of
        undefined -> exit({badarg, {?MODULE, Nombre}});
        Pid ->
            Pid ! Mensaje,
            Pid
    end.

init([]) ->
    ets:new(?TABLA_LOTES, [named_table, protected, set, {read_concurrency, true}]),
    ets:new(?TABLA_FERMENTADORES, [named_table, protected, set, {read_concurrency, true}]),
    ets:new(?TABLA_CONTADORES, [named_table, public, set, {write_concurrency, true}]),
    {ok, #{monitores => #{}}}.

handle_call({registrar, Tipo, Id, Pid}, _From, State) ->
    Tabla = tabla(Tipo),
    Datos = case buscar(Tabla, Id) of
        {_, _, Previos} -> Previos;
        undefined -> undefined
    end,
    ets:insert(Tabla, {Id, Pid, Datos}),
    Ref = erlang:monitor(process, Pid),
    Monitores = maps:put(Ref, {Tipo, Id, Pid}, maps:get(monitores, State)),
    {reply, yes, State#{monitores => Monitores}};
handle_call({desregistrar, Tipo, Id, Pid}, _From, State) ->
    Tabla = tabla(Tipo),
    case buscar(Tabla, Id) of
        {_, Pid, Datos} -> ets:insert(Tabla, {Id, undefined, Datos});
        _ -> ok
    end,
    {reply, ok, State};
handle_call({actualizar, Tipo, Id, Datos}, _From, State) ->
    Tabla = tabla(Tipo),
    Pid = case buscar(Tabla, Id) of
        {_, Existente, _} -> Existente;
        undefined -> undefined
    end,
    ets:insert(Tabla, {Id, Pid, Datos}),
    {reply, ok, State};
handle_call({eliminar, Tipo, Id}, _From, State) ->
    ets:delete(tabla(Tipo), Id),
    {reply, ok, State};
handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, _Razon}, State) ->
    Monitores = maps:get(monitores, State),
    case maps:take(Ref, Monitores) of
        {{Tipo, Id, Pid}, Restantes} ->
            Tabla = tabla(Tipo),
            %% Se conserva el snapshot aunque el proceso ya no este vivo.
            case buscar(Tabla, Id) of
                {_, Pid, Datos} -> ets:insert(Tabla, {Id, undefined, Datos});
                _ -> ok
            end,
            {noreply, State#{monitores => Restantes}};
        _ ->
            {noreply, State}
    end;
handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    ok.

tabla(lote) -> ?TABLA_LOTES;
tabla(fermentador) -> ?TABLA_FERMENTADORES.

buscar(Tabla, Id) ->
    case ets:lookup(Tabla, Id) of
        [Fila] -> Fila;
        [] -> undefined
    end.

listar(Tabla) ->
    try ets:tab2list(Tabla) of
        Filas -> Filas
    catch
        error:badarg -> []
    end.
