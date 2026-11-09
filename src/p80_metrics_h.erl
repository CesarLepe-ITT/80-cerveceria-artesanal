%%% @doc Handler de metricas en formato Prometheus.
-module(p80_metrics_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Cabeceras = #{
                <<"content-type">> => <<"text/plain; version=0.0.4; charset=utf-8">>,
                <<"cache-control">> => <<"no-store">>,
                <<"access-control-allow-origin">> => <<"*">>
            },
            Req1 = cowboy_req:reply(200, Cabeceras, p80_metricas:prometheus(), Req0),
            {ok, Req1, undefined};
        _ ->
            p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end.
