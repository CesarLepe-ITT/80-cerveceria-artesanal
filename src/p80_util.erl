%%% @doc Utilidades de validacion, conversion y dominio compartidas.
-module(p80_util).

-export([
    campo/2,
    texto/1,
    texto/2,
    entero/1,
    entero_positivo/1,
    numero/1,
    redondear/1,
    ahora_ms/0,
    etapas/0,
    etapa_valida/1,
    validar_lote/1,
    validar_fermentador/1,
    motivo_bin/1
]).

-define(TEMP_MIN, -20.0).
-define(TEMP_MAX, 120.0).
-define(TOLERANCIA_MIN, 0.1).
-define(TOLERANCIA_MAX, 30.0).

%% @doc Busca un campo aceptando tanto claves binarias (JSON) como atomos (Erlang).
campo(Mapa, Clave) when is_map(Mapa), is_atom(Clave) ->
    Binaria = atom_to_binary(Clave, utf8),
    case maps:find(Clave, Mapa) of
        {ok, Valor} -> Valor;
        error -> maps:get(Binaria, Mapa, undefined)
    end;
campo(_, _) ->
    undefined.

texto(Valor) when is_binary(Valor) ->
    case string:trim(Valor) of
        <<>> -> error;
        Texto -> {ok, Texto}
    end;
texto(Valor) when is_list(Valor) ->
    try
        texto(unicode:characters_to_binary(Valor))
    catch
        _:_ -> error
    end;
texto(_) ->
    error.

texto(Valor, PorDefecto) ->
    case texto(Valor) of
        {ok, Texto} -> Texto;
        error -> PorDefecto
    end.

entero(Valor) when is_integer(Valor) ->
    {ok, Valor};
entero(Valor) when is_binary(Valor) ->
    try
        {ok, binary_to_integer(string:trim(Valor))}
    catch
        _:_ -> error
    end;
entero(_) ->
    error.

entero_positivo(Valor) ->
    case entero(Valor) of
        {ok, Numero} when Numero > 0 -> {ok, Numero};
        _ -> error
    end.

numero(Valor) when is_integer(Valor) ->
    {ok, float(Valor)};
numero(Valor) when is_float(Valor) ->
    {ok, Valor};
numero(Valor) when is_binary(Valor) ->
    Texto = string:trim(Valor),
    try
        {ok, binary_to_float(Texto)}
    catch
        _:_ ->
            try
                {ok, float(binary_to_integer(Texto))}
            catch
                _:_ -> error
            end
    end;
numero(_) ->
    error.

redondear(Valor) when is_number(Valor) ->
    round(Valor * 100) / 100.

ahora_ms() ->
    erlang:system_time(millisecond).

etapas() ->
    [molienda, coccion, fermentacion, maduracion, envasado, terminado].

etapa_valida(Etapa) when is_atom(Etapa) ->
    lists:member(Etapa, etapas());
etapa_valida(Etapa) when is_binary(Etapa) ->
    etapa_valida(binario_a_etapa(Etapa));
etapa_valida(_) ->
    false.

binario_a_etapa(<<"molienda">>) -> molienda;
binario_a_etapa(<<"coccion">>) -> coccion;
binario_a_etapa(<<"fermentacion">>) -> fermentacion;
binario_a_etapa(<<"maduracion">>) -> maduracion;
binario_a_etapa(<<"envasado">>) -> envasado;
binario_a_etapa(<<"terminado">>) -> terminado;
binario_a_etapa(_) -> invalida.

%% @doc Normaliza y valida los datos de entrada de un lote.
validar_lote(Params) ->
    case texto(campo(Params, nombre)) of
        {ok, Nombre} ->
            Receta = texto(campo(Params, receta), <<"Sin receta">>),
            case entero_positivo(campo(Params, litros)) of
                {ok, Litros} ->
                    case validar_fermentador_opcional(campo(Params, fermentador_id)) of
                        {ok, FermentadorId} ->
                            {ok, #{
                                nombre => Nombre,
                                receta => Receta,
                                litros => Litros,
                                fermentador_id => FermentadorId
                            }};
                        error ->
                            {error, <<"fermentador_id debe ser un entero positivo">>}
                    end;
                error ->
                    {error, <<"litros debe ser un entero positivo">>}
            end;
        error ->
            {error, <<"nombre es obligatorio">>}
    end.

validar_fermentador_opcional(undefined) ->
    {ok, undefined};
validar_fermentador_opcional(null) ->
    {ok, undefined};
validar_fermentador_opcional(Valor) ->
    case entero_positivo(Valor) of
        {ok, Id} -> {ok, Id};
        error -> error
    end.

%% @doc Normaliza y valida los datos de entrada de un fermentador.
validar_fermentador(Params) ->
    case texto(campo(Params, nombre)) of
        {ok, Nombre} ->
            case entero_positivo(campo(Params, capacidad_litros)) of
                {ok, Capacidad} ->
                    validar_temperaturas(Params, Nombre, Capacidad);
                error ->
                    {error, <<"capacidad_litros debe ser un entero positivo">>}
            end;
        error ->
            {error, <<"nombre es obligatorio">>}
    end.

validar_temperaturas(Params, Nombre, Capacidad) ->
    Objetivo = campo(Params, temperatura_objetivo),
    Actual = campo(Params, temperatura_actual),
    Tolerancia = campo(Params, tolerancia),
    case numero_por_defecto(Objetivo, 20.0) of
        {ok, TempObjetivo} when TempObjetivo >= ?TEMP_MIN, TempObjetivo =< ?TEMP_MAX ->
            case numero_por_defecto(Actual, TempObjetivo) of
                {ok, TempActual} when TempActual >= ?TEMP_MIN, TempActual =< ?TEMP_MAX ->
                    case numero_por_defecto(Tolerancia, tolerancia_configurada()) of
                        {ok, Tol} when Tol >= ?TOLERANCIA_MIN, Tol =< ?TOLERANCIA_MAX ->
                            {ok, #{
                                nombre => Nombre,
                                capacidad_litros => Capacidad,
                                temperatura_objetivo => redondear(TempObjetivo),
                                temperatura_actual => redondear(TempActual),
                                tolerancia => redondear(Tol)
                            }};
                        {ok, _} ->
                            {error, <<"tolerancia debe estar entre 0.1 y 30.0">>};
                        error ->
                            {error, <<"tolerancia debe ser numerica">>}
                    end;
                {ok, _} ->
                    {error, <<"temperatura_actual fuera de rango (-20 a 120 C)">>};
                error ->
                    {error, <<"temperatura_actual debe ser numerica">>}
            end;
        {ok, _} ->
            {error, <<"temperatura_objetivo fuera de rango (-20 a 120 C)">>};
        error ->
            {error, <<"temperatura_objetivo debe ser numerica">>}
    end.

numero_por_defecto(undefined, PorDefecto) ->
    {ok, PorDefecto};
numero_por_defecto(null, PorDefecto) ->
    {ok, PorDefecto};
numero_por_defecto(Valor, _PorDefecto) ->
    numero(Valor).

tolerancia_configurada() ->
    application:get_env(p80_cerveceria_artesanal, tolerancia_temperatura, 1.0).

%% @doc Convierte motivos internos en mensajes legibles para la API.
motivo_bin(no_encontrado) -> <<"el recurso no existe">>;
motivo_bin(transicion_invalida) -> <<"la transicion solicitada no es valida">>;
motivo_bin(lote_terminado) -> <<"el lote ya termino su ciclo de produccion">>;
motivo_bin(sin_fermentador_disponible) -> <<"no hay fermentadores libres con capacidad suficiente">>;
motivo_bin(fermentador_ocupado) -> <<"el fermentador ya tiene un lote asignado">>;
motivo_bin(fermentador_no_encontrado) -> <<"el fermentador no existe">>;
motivo_bin(capacidad_insuficiente) -> <<"la capacidad del fermentador es insuficiente">>;
motivo_bin(lote_no_asignado) -> <<"el lote no esta asignado a ese fermentador">>;
motivo_bin(json_invalido) -> <<"el cuerpo JSON no es valido">>;
motivo_bin({validacion, Mensaje}) -> Mensaje;
motivo_bin({inicio_fallido, _}) -> <<"no fue posible iniciar el proceso de dominio">>;
motivo_bin(Otro) when is_binary(Otro) -> Otro;
motivo_bin(Otro) -> iolist_to_binary(io_lib:format("~p", [Otro])).
