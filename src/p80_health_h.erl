%%% @doc Handler de salud del sistema.
-module(p80_health_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Procesos = procesos(),
            TodosVivos = lists:all(fun(#{vivo := Vivo}) -> Vivo end, Procesos),
            {Status, Estado} = case TodosVivos of
                true -> {200, <<"ok">>};
                false -> {503, <<"degradado">>}
            end,
            p80_http_util:respond(Status, #{
                estado => Estado,
                version => version(),
                uptime_segundos => uptime_segundos(),
                procesos => Procesos
            }, Req0);
        _ ->
            p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end.

procesos() ->
    [
        #{
            nombre => atom_to_binary(Modulo, utf8),
            vivo => is_pid(whereis(Modulo))
        }
     || Modulo <- [
            p80_registro,
            p80_eventos,
            p80_metricas,
            p80_vigilante,
            p80_control_temperatura,
            p80_http
        ]
    ].

version() ->
    case application:get_key(p80_cerveceria_artesanal, vsn) of
        {ok, Vsn} -> list_to_binary(Vsn);
        _ -> <<"desconocida">>
    end.

uptime_segundos() ->
    case erlang:statistics(wall_clock) of
        {Total, _DesdeUltima} -> Total div 1000
    end.
