%%% @doc Handler de Server-Sent Events para actualizaciones en tiempo real.
-module(p80_sse_h).
-behaviour(cowboy_loop).

-export([init/2, info/3, terminate/3]).

init(Req0, _State) ->
    Cabeceras = #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>
    },
    Req = cowboy_req:stream_reply(200, Cabeceras, Req0),
    ok = p80_eventos:suscribir(self()),
    ok = cowboy_req:stream_body(<<": conectado al bus de eventos\n\n">>, nofin, Req),
    Heartbeat = application:get_env(p80_cerveceria_artesanal, sse_heartbeat_ms, 15000),
    programar_heartbeat(Heartbeat),
    {cowboy_loop, Req, #{heartbeat => Heartbeat}, infinity}.

info({p80_evento, Evento}, Req, State) ->
    Payload = p80_json:encode(Evento),
    ok = cowboy_req:stream_body([<<"data: ">>, Payload, <<"\n\n">>], nofin, Req),
    {ok, Req, State};
info(heartbeat, Req, State) ->
    ok = cowboy_req:stream_body(<<": ping\n\n">>, nofin, Req),
    programar_heartbeat(maps:get(heartbeat, State)),
    {ok, Req, State};
info(_Otro, Req, State) ->
    {ok, Req, State}.

terminate(_Razon, _Req, _State) ->
    p80_eventos:desuscribir(self()),
    ok.

programar_heartbeat(Milisegundos) when is_integer(Milisegundos), Milisegundos > 0 ->
    erlang:send_after(Milisegundos, self(), heartbeat),
    ok;
programar_heartbeat(_) ->
    ok.
