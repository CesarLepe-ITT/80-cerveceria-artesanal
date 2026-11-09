%%% @doc Arranque y parada del listener HTTP de Cowboy.
-module(p80_http).
-behaviour(gen_server).

-export([start_link/0, puerto/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(LISTENER, p80_http_listener).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Devuelve el puerto real del listener (util cuando se configura 0).
puerto() ->
    gen_server:call(?MODULE, puerto).

init([]) ->
    Puerto = application:get_env(p80_cerveceria_artesanal, http_port, 8080),
    Dispatch = cowboy_router:compile([{'_', p80_router:rutas()}]),
    Opciones = #{env => #{dispatch => Dispatch}},
    case cowboy:start_clear(?LISTENER, [{port, Puerto}], Opciones) of
        {ok, _Pid} ->
            {ok, #{puerto => Puerto}};
        {error, {already_started, _Pid}} ->
            {ok, #{puerto => Puerto}};
        {error, Motivo} ->
            {stop, {no_se_pudo_iniciar_http, Motivo}}
    end.

handle_call(puerto, _From, State) ->
    case catch ranch:get_port(?LISTENER) of
        Puerto when is_integer(Puerto) -> {reply, Puerto, State};
        _ -> {reply, maps:get(puerto, State), State}
    end;
handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    catch cowboy:stop_listener(?LISTENER),
    ok.
