%%% @doc Handler de la coleccion de fermentadores.
-module(p80_api_fermentadores_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> listar(Req0, State);
        <<"POST">> -> crear(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"GET">>, <<"POST">>], Req0)
    end.

listar(Req0, _State) ->
    Fermentadores = p80_fermentadores:listar(),
    p80_http_util:respond(200, #{
        fermentadores => Fermentadores,
        total => length(Fermentadores)
    }, Req0).

crear(Req0, _State) ->
    case p80_http_util:leer_json(Req0) of
        {ok, Mapa, Req1} ->
            case p80_fermentadores:crear(Mapa) of
                {ok, Fermentador} ->
                    p80_http_util:respond(201, #{fermentador => Fermentador}, Req1);
                {error, Motivo} ->
                    p80_http_util:error_negocio(Motivo, Req1)
            end;
        {error, _Codigo, Req1} ->
            p80_http_util:error(
                400,
                <<"json_invalido">>,
                <<"El cuerpo de la solicitud no es JSON valido">>,
                Req1
            )
    end.
