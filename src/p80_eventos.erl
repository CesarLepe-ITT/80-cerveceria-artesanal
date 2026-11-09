%%% @doc Bus de eventos y bitacora en memoria.
%%%
%%% Los procesos de dominio publican eventos; los clientes SSE se suscriben
%%% y reciben cada evento como mensaje `{p80_evento, Evento}'.
-module(p80_eventos).
-behaviour(gen_server).

-export([
    start_link/0,
    suscribir/1,
    desuscribir/1,
    publicar/2,
    recientes/1,
    total/0,
    sincronizar/0
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

suscribir(Pid) when is_pid(Pid) ->
    gen_server:call(?MODULE, {suscribir, Pid}).

desuscribir(Pid) when is_pid(Pid) ->
    gen_server:call(?MODULE, {desuscribir, Pid}).

publicar(Tipo, Datos) ->
    gen_server:cast(?MODULE, {publicar, Tipo, Datos}).

recientes(Limite) when is_integer(Limite), Limite > 0 ->
    gen_server:call(?MODULE, {recientes, Limite});
recientes(_) ->
    [].

total() ->
    gen_server:call(?MODULE, total).

sincronizar() ->
    gen_server:call(?MODULE, sincronizar).

init([]) ->
    Max = application:get_env(p80_cerveceria_artesanal, max_eventos, 500),
    {ok, #{suscriptores => #{}, eventos => [], max => Max}}.

handle_call({suscribir, Pid}, _From, State) ->
    Suscriptores = maps:get(suscriptores, State),
    case maps:is_key(Pid, Suscriptores) of
        true ->
            {reply, ok, State};
        false ->
            Ref = erlang:monitor(process, Pid),
            {reply, ok, State#{suscriptores => maps:put(Pid, Ref, Suscriptores)}}
    end;
handle_call({desuscribir, Pid}, _From, State) ->
    Suscriptores = maps:get(suscriptores, State),
    case maps:take(Pid, Suscriptores) of
        {Ref, Restantes} ->
            erlang:demonitor(Ref, [flush]),
            {reply, ok, State#{suscriptores => Restantes}};
        error ->
            {reply, ok, State}
    end;
handle_call({recientes, Limite}, _From, State) ->
    Eventos = maps:get(eventos, State),
    {reply, lists:sublist(Eventos, Limite), State};
handle_call(total, _From, State) ->
    {reply, length(maps:get(eventos, State)), State};
handle_call(sincronizar, _From, State) ->
    {reply, ok, State};
handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast({publicar, Tipo, Datos}, State) ->
    Evento = #{
        tipo => Tipo,
        ts => p80_util:ahora_ms(),
        datos => Datos
    },
    Max = maps:get(max, State),
    Eventos = lists:sublist([Evento | maps:get(eventos, State)], Max),
    maps:foreach(
        fun(Pid, _Ref) -> Pid ! {p80_evento, Evento} end,
        maps:get(suscriptores, State)
    ),
    {noreply, State#{eventos => Eventos}};
handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Razon}, State) ->
    Suscriptores = maps:remove(Pid, maps:get(suscriptores, State)),
    {noreply, State#{suscriptores => Suscriptores}};
handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    ok.
