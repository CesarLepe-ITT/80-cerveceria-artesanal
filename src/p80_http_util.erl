%%% @doc Utilidades compartidas por los handlers HTTP.
-module(p80_http_util).

-export([
    respond/3,
    respond/4,
    error/4,
    error_negocio/2,
    leer_json/1,
    id/1,
    metodo_no_permitido/2
]).

respond(Status, Cuerpo, Req) ->
    respond(Status, Cuerpo, #{}, Req).

respond(Status, Cuerpo, CabecerasExtra, Req) ->
    CabecerasBase = #{
        <<"content-type">> => <<"application/json; charset=utf-8">>,
        <<"cache-control">> => <<"no-store">>,
        <<"access-control-allow-origin">> => <<"*">>
    },
    Cabeceras = maps:merge(CabecerasBase, CabecerasExtra),
    Req2 = cowboy_req:reply(Status, Cabeceras, p80_json:encode(Cuerpo), Req),
    {ok, Req2, undefined}.

error(Status, Codigo, Mensaje, Req) ->
    respond(Status, #{
        error => #{
            codigo => Codigo,
            mensaje => Mensaje
        }
    }, Req).

%% @doc Traduce errores de negocio a codigos HTTP y mensajes en espanol.
error_negocio(Motivo, Req) ->
    {Status, Codigo} = case Motivo of
        no_encontrado -> {404, <<"no_encontrado">>};
        transicion_invalida -> {409, <<"transicion_invalida">>};
        lote_terminado -> {409, <<"lote_terminado">>};
        sin_fermentador_disponible -> {409, <<"sin_fermentador_disponible">>};
        fermentador_ocupado -> {409, <<"fermentador_ocupado">>};
        fermentador_no_encontrado -> {404, <<"fermentador_no_encontrado">>};
        capacidad_insuficiente -> {409, <<"capacidad_insuficiente">>};
        lote_no_asignado -> {409, <<"lote_no_asignado">>};
        {validacion, _} -> {400, <<"solicitud_invalida">>};
        {inicio_fallido, _} -> {500, <<"error_interno">>};
        _ -> {500, <<"error_interno">>}
    end,
    error(Status, Codigo, p80_util:motivo_bin(Motivo), Req).

%% @doc Lee y decodifica el cuerpo JSON. Un cuerpo vacio se interpreta como `#{}'.
leer_json(Req0) ->
    case cowboy_req:read_body(Req0, #{length => 1048576, period => 5000}) of
        {ok, <<>>, Req1} ->
            {ok, #{}, Req1};
        {ok, Binario, Req1} ->
            case p80_json:decode(Binario) of
                {ok, Mapa} when is_map(Mapa) -> {ok, Mapa, Req1};
                {ok, _Otro} -> {error, cuerpo_invalido, Req1};
                {error, _Motivo} -> {error, json_invalido, Req1}
            end;
        {more, _Parcial, Req1} ->
            {error, cuerpo_demasiado_grande, Req1}
    end.

%% @doc Extrae y valida el parametro de ruta `id'.
id(Req) ->
    case cowboy_req:binding(id, Req) of
        undefined ->
            error;
        Binario ->
            p80_util:entero_positivo(Binario)
    end.

metodo_no_permitido(Permitidos, Req) ->
    Allow = iolist_to_binary(lists:join(<<", ">>, Permitidos)),
    respond(405, #{
        error => #{
            codigo => <<"metodo_no_permitido">>,
            mensaje => <<"Metodo HTTP no permitido para este recurso">>,
            permitidos => Allow
        }
    }, #{<<"allow">> => Allow}, Req).
