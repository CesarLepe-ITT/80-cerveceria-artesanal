%%% @doc Handler de la coleccion de lotes.
-module(p80_api_lotes_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> listar(Req0, State);
        <<"POST">> -> crear(Req0, State);
        _ -> p80_http_util:metodo_no_permitido([<<"GET">>, <<"POST">>], Req0)
    end.

listar(Req0, _State) ->
    case filtrar(Req0) of
        {ok, Lotes, Req1} ->
            p80_http_util:respond(200, #{
                lotes => Lotes,
                total => length(Lotes)
            }, Req1);
        {error, Req1} ->
            p80_http_util:error(
                400,
                <<"solicitud_invalida">>,
                <<"La etapa indicada no es valida">>,
                Req1
            )
    end.

filtrar(Req0) ->
    Consulta = cowboy_req:parse_qs(Req0),
    case lists:keyfind(<<"etapa">>, 1, Consulta) of
        false ->
            {ok, p80_lotes:listar(), Req0};
        {_, EtapaBin} ->
            case p80_util:etapa_valida(EtapaBin) of
                true ->
                    Filtrados = [
                        L
                     || L <- p80_lotes:listar(),
                        atom_to_binary(maps:get(etapa, L), utf8) =:= EtapaBin
                    ],
                    {ok, Filtrados, Req0};
                false ->
                    {error, Req0}
            end
    end.

crear(Req0, _State) ->
    case p80_http_util:leer_json(Req0) of
        {ok, Mapa, Req1} ->
            case p80_lotes:crear(Mapa) of
                {ok, Lote} ->
                    p80_http_util:respond(201, #{lote => Lote}, Req1);
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
