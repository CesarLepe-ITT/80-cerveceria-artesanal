%%% @doc Escenario de demostracion y utilidades para pruebas manuales.
%%%
%%% Ejecutar desde una shell limpia:
%%%   p80_demo:escenario().
%%%   p80_demo:perder_frio(1, 5.0).
-module(p80_demo).

-export([escenario/0, perder_frio/2]).

escenario() ->
    Fermentadores = crear_fermentadores(),
    Lotes = crear_lotes(),
    Avances = [
        {1, 5}, {2, 5}, {3, 5},
        {4, 2}, {5, 2}, {6, 2}, {7, 2},
        {8, 3}, {9, 3},
        {10, 1}, {11, 1},
        {12, 0}
    ],
    lists:foreach(
        fun({Indice, Veces}) ->
            case lists:nth(Indice, Lotes) of
                {ok, Lote} -> avanzar_n(maps:get(id, Lote), Veces);
                _ -> ok
            end
        end,
        Avances
    ),
    #{
        fermentadores => [maps:get(id, F) || {ok, F} <- Fermentadores],
        lotes => [maps:get(id, L) || {ok, L} <- Lotes],
        resumen => p80_metricas:resumen()
    }.

perder_frio(FermentadorId, Grados) ->
    p80_control_temperatura:simular_desviacion(FermentadorId, Grados).

crear_fermentadores() ->
    Definiciones = [
        {<<"Fermentador A">>, 2000, 20.0},
        {<<"Fermentador B">>, 1500, 19.0},
        {<<"Fermentador C">>, 1200, 18.0},
        {<<"Fermentador D">>, 1000, 12.0},
        {<<"Fermentador E">>, 800, 20.0},
        {<<"Fermentador F">>, 600, 18.0}
    ],
    [
        p80_fermentadores:crear(#{
            nombre => Nombre,
            capacidad_litros => Capacidad,
            temperatura_objetivo => Objetivo
        })
     || {Nombre, Capacidad, Objetivo} <- Definiciones
    ].

crear_lotes() ->
    Recetas = [
        <<"IPA Tijuana">>,
        <<"Pale Ale Baja">>,
        <<"Stout Frontera">>,
        <<"Lager Pacifico">>,
        <<"Saison Valle">>
    ],
    Litros = [1000, 800, 600, 500, 450, 400, 350, 300, 250, 220, 200, 180],
    [
        begin
            Receta = lists:nth(((Indice - 1) rem length(Recetas)) + 1, Recetas),
            p80_lotes:crear(#{
                nombre => iolist_to_binary([Receta, " #", integer_to_list(Indice)]),
                receta => Receta,
                litros => lists:nth(Indice, Litros)
            })
        end
     || Indice <- lists:seq(1, 12)
    ].

avanzar_n(_Id, 0) ->
    ok;
avanzar_n(Id, Veces) ->
    case p80_lotes:avanzar(Id, #{}) of
        {ok, _Lote} -> avanzar_n(Id, Veces - 1);
        {error, _Motivo} -> ok
    end.
