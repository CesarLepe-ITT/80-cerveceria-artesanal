%%% @doc Handler de un fermentador y de sus temperaturas.
-module(p80_api_fermentador_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, #{accion := detalle} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> detalle(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end;
init(Req0, #{accion := temperatura} = State) ->
    case cowboy_req:method(Req0) of
        <<"PUT">> -> actualizar_temperatura(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"PUT">>], Req0)
    end;
init(Req0, #{accion := temperatura_actual} = State) ->
    case cowboy_req:method(Req0) of
        <<"PUT">> -> actualizar_temperatura_actual(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"PUT">>], Req0)
    end.

detalle(Req0, _State) ->
    case p80_http_util:id(Req0) of
        {ok, Id} ->
            case p80_fermentadores:estado(Id) of
                Fermentador when is_map(Fermentador) ->
                    p80_http_util:respond(200, #{fermentador => Fermentador}, Req0);
                {error, Motivo} ->
                    p80_http_util:error_negocio(Motivo, Req0)
            end;
        error ->
            id_invalido(Req0)
    end.

actualizar_temperatura(Req0, _State) ->
    with_id_y_campo(Req0, temperatura_objetivo, fun(Id, Temperatura, Req1) ->
        case p80_fermentadores:fijar_temperatura_objetivo(Id, Temperatura) of
            {ok, Fermentador} ->
                p80_http_util:respond(200, #{fermentador => Fermentador}, Req1);
            {error, Motivo} ->
                p80_http_util:error_negocio(Motivo, Req1)
        end
    end).

actualizar_temperatura_actual(Req0, _State) ->
    with_id_y_campo(Req0, temperatura_actual, fun(Id, Temperatura, Req1) ->
        case p80_fermentadores:actualizar_temperatura_actual(Id, Temperatura) of
            {ok, Fermentador} ->
                p80_http_util:respond(200, #{fermentador => Fermentador}, Req1);
            {error, Motivo} ->
                p80_http_util:error_negocio(Motivo, Req1)
        end
    end).

with_id_y_campo(Req0, Campo, Continuacion) ->
    case p80_http_util:id(Req0) of
        {ok, Id} ->
            case p80_http_util:leer_json(Req0) of
                {ok, Mapa, Req1} ->
                    case p80_util:campo(Mapa, Campo) of
                        undefined ->
                            campo_requerido(Campo, Req1);
                        Valor ->
                            Continuacion(Id, Valor, Req1)
                    end;
                {error, _Codigo, Req1} ->
                    p80_http_util:error(
                        400,
                        <<"json_invalido">>,
                        <<"El cuerpo de la solicitud no es JSON valido">>,
                        Req1
                    )
            end;
        error ->
            id_invalido(Req0)
    end.

campo_requerido(Campo, Req) ->
    Nombre = atom_to_binary(Campo, utf8),
    p80_http_util:error(
        400,
        <<"solicitud_invalida">>,
        <<"El campo ", Nombre/binary, " es obligatorio">>,
        Req
    ).

id_invalido(Req) ->
    p80_http_util:error(
        400,
        <<"solicitud_invalida">>,
        <<"El identificador del fermentador debe ser un entero positivo">>,
        Req
    ).
