%%% @doc Handler de la bitacora de eventos.
-module(p80_api_eventos_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> listar(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end.

listar(Req0, _State) ->
    Consulta = cowboy_req:parse_qs(Req0),
    case limite(Consulta, 50) of
        {ok, Limite} ->
            Eventos = p80_eventos:recientes(Limite),
            p80_http_util:respond(200, #{
                eventos => Eventos,
                total => length(Eventos)
            }, Req0);
        error ->
            p80_http_util:error(
                400,
                <<"solicitud_invalida">>,
                <<"limite debe ser un entero positivo menor o igual a 500">>,
                Req0
            )
    end.

limite(Consulta, PorDefecto) ->
    case lists:keyfind(<<"limite">>, 1, Consulta) of
        false ->
            {ok, PorDefecto};
        {_, Valor} ->
            case p80_util:entero_positivo(Valor) of
                {ok, Limite} when Limite =< 500 -> {ok, Limite};
                _ -> error
            end
    end.
