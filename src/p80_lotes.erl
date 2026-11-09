%%% @doc Fachada publica para lotes de produccion.
-module(p80_lotes).

-export([
    crear/1,
    listar/0,
    estado/1,
    avanzar/2,
    marcar_en_riesgo/2,
    normalizar_riesgo/2,
    historial/1,
    existe/1,
    pid/1
]).

crear(Params) ->
    case p80_util:validar_lote(Params) of
        {ok, Datos} ->
            case validar_fermentador_preferido(maps:get(fermentador_id, Datos)) of
                ok ->
                    Id = p80_registro:nuevo_id(lote),
                    case p80_lote_sup:iniciar_lote(Id, Datos) of
                        {ok, _Pid} ->
                            case estado(Id) of
                                Mapa when is_map(Mapa) -> {ok, Mapa};
                                Otro -> Otro
                            end;
                        {error, Motivo} -> {error, {inicio_fallido, Motivo}}
                    end;
                {error, Motivo} ->
                    {error, {validacion, Motivo}}
            end;
        {error, Motivo} ->
            {error, {validacion, Motivo}}
    end.

listar() ->
    Filas = [{Id, Datos} || {Id, _Pid, Datos} <- p80_registro:listar_lotes(), Datos =/= undefined],
    [Datos || {_Id, Datos} <- lists:keysort(1, Filas)].

estado(Id) ->
    p80_lote:estado(Id).

avanzar(Id, Opciones) when is_map(Opciones) ->
    p80_lote:avanzar(Id, Opciones).

marcar_en_riesgo(Id, Motivo) ->
    p80_lote:marcar_en_riesgo(Id, Motivo).

normalizar_riesgo(Id, Motivo) ->
    p80_lote:normalizar_riesgo(Id, Motivo).

historial(Id) ->
    p80_lote:historial(Id).

existe(Id) ->
    p80_registro:datos_lote(Id) =/= undefined.

pid(Id) ->
    p80_lote:pid(Id).

validar_fermentador_preferido(undefined) ->
    ok;
validar_fermentador_preferido(Id) ->
    case p80_fermentadores:existe(Id) of
        true -> ok;
        false -> {error, <<"el fermentador indicado no existe">>}
    end.
