%%% @doc Handler de un lote individual y del avance de etapa.
-module(p80_api_lote_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, #{accion := detalle} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> detalle(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end;
init(Req0, #{accion := avanzar} = State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> avanzar(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"POST">>], Req0)
    end.

detalle(Req0, _State) ->
    case p80_http_util:id(Req0) of
        {ok, Id} ->
            case p80_lotes:estado(Id) of
                Lote when is_map(Lote) ->
                    p80_http_util:respond(200, #{lote => Lote}, Req0);
                {error, Motivo} ->
                    p80_http_util:error_negocio(Motivo, Req0)
            end;
        error ->
            p80_http_util:error(
                400,
                <<"solicitud_invalida">>,
                <<"El identificador del lote debe ser un entero positivo">>,
                Req0
            )
    end.

avanzar(Req0, _State) ->
    case p80_http_util:id(Req0) of
        {ok, Id} ->
            case opciones_avance(Req0) of
                {ok, Opciones, Req1} ->
                    case p80_lotes:avanzar(Id, Opciones) of
                        {ok, Lote} ->
                            p80_http_util:respond(200, #{lote => Lote}, Req1);
                        {error, Motivo} ->
                            p80_http_util:error_negocio(Motivo, Req1)
                    end;
                {error, Req1} ->
                    p80_http_util:error(
                        400,
                        <<"solicitud_invalida">>,
                        <<"fermentador_id debe ser un entero positivo">>,
                        Req1
                    )
            end;
        error ->
            p80_http_util:error(
                400,
                <<"solicitud_invalida">>,
                <<"El identificador del lote debe ser un entero positivo">>,
                Req0
            )
    end.

opciones_avance(Req0) ->
    case p80_http_util:leer_json(Req0) of
        {ok, Mapa, Req1} ->
            case p80_util:campo(Mapa, fermentador_id) of
                undefined ->
                    {ok, #{}, Req1};
                null ->
                    {ok, #{}, Req1};
                Valor ->
                    case p80_util:entero_positivo(Valor) of
                        {ok, FermentadorId} ->
                            {ok, #{fermentador_id => FermentadorId}, Req1};
                        error ->
                            {error, Req1}
                    end
            end;
        {error, _Codigo, Req1} ->
            {error, Req1}
    end.
