%%% @doc Handler de metricas en formato JSON.
-module(p80_api_metricas_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            p80_http_util:respond(200, #{metricas => p80_metricas:resumen()}, Req0);
        _ ->
            p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end.
