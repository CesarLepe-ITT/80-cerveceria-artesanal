%%% @doc Fachada publica para fermentadores.
-module(p80_fermentadores).

-export([
    crear/1,
    listar/0,
    estado/1,
    fijar_temperatura_objetivo/2,
    actualizar_temperatura_actual/2,
    asignar/2,
    asignar_automatico/2,
    liberar_lote/2,
    existe/1,
    pid/1
]).

crear(Params) ->
    case p80_util:validar_fermentador(Params) of
        {ok, Datos} ->
            Id = p80_registro:nuevo_id(fermentador),
            case p80_fermentador_sup:iniciar_fermentador(Id, Datos) of
                {ok, _Pid} ->
                    case estado(Id) of
                        Mapa when is_map(Mapa) -> {ok, Mapa};
                        Otro -> Otro
                    end;
                {error, Motivo} -> {error, {inicio_fallido, Motivo}}
            end;
        {error, Motivo} ->
            {error, {validacion, Motivo}}
    end.

listar() ->
    Filas = [
        {Id, Datos}
     || {Id, _Pid, Datos} <- p80_registro:listar_fermentadores(), Datos =/= undefined
    ],
    [Datos || {_Id, Datos} <- lists:keysort(1, Filas)].

estado(Id) ->
    p80_fermentador:estado(Id).

fijar_temperatura_objetivo(Id, Temperatura) ->
    p80_fermentador:fijar_temperatura_objetivo(Id, Temperatura).

actualizar_temperatura_actual(Id, Temperatura) ->
    p80_fermentador:actualizar_temperatura_actual(Id, Temperatura).

asignar(FermentadorId, LoteId) ->
    case p80_fermentador:asignar_lote(FermentadorId, LoteId) of
        {ok, Datos} -> {ok, Datos};
        {error, Motivo} -> {error, Motivo}
    end.

asignar_automatico(LoteId, Litros) ->
    Candidatos = [
        F
     || F <- listar(),
        maps:get(lote_id, F, undefined) =:= undefined,
        maps:get(capacidad_litros, F, 0) >= Litros
    ],
    intentar_asignacion(Candidatos, LoteId).

liberar_lote(FermentadorId, LoteId) ->
    p80_fermentador:liberar_lote(FermentadorId, LoteId).

existe(Id) ->
    p80_registro:datos_fermentador(Id) =/= undefined.

pid(Id) ->
    p80_fermentador:pid(Id).

intentar_asignacion([], _LoteId) ->
    {error, sin_fermentador_disponible};
intentar_asignacion([Fermentador | Resto], LoteId) ->
    Id = maps:get(id, Fermentador),
    case asignar(Id, LoteId) of
        {ok, _Datos} -> {ok, Id};
        {error, fermentador_ocupado} -> intentar_asignacion(Resto, LoteId);
        {error, _} -> intentar_asignacion(Resto, LoteId)
    end.
