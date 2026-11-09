-module(p80_lote_tests).
-include_lib("eunit/include/eunit.hrl").

creacion_de_lote_test() ->
    p80_test_util:asegurar_app(),
    Nombre = p80_test_util:unico(<<"Lote creacion">>),
    {ok, Lote} = p80_lotes:crear(#{
        nombre => Nombre,
        receta => <<"IPA">>,
        litros => 500
    }),
    ?assertMatch(#{etapa := molienda}, Lote),
    ?assertEqual(false, maps:get(en_riesgo, Lote)),
    ?assertEqual(500, maps:get(litros, Lote)),
    ?assertEqual(Nombre, maps:get(nombre, Lote)),
    ?assert(length(maps:get(historial, Lote)) >= 1).

transiciones_validas_test() ->
    p80_test_util:asegurar_app(),
    FermentadorId = crear_fermentador(2000),
    {ok, Lote0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote transiciones">>),
        receta => <<"Pale Ale">>,
        litros => 1000
    }),
    Id = maps:get(id, Lote0),
    {ok, Lote1} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(coccion, maps:get(etapa, Lote1)),
    {ok, Lote2} = p80_lotes:avanzar(Id, #{fermentador_id => FermentadorId}),
    ?assertEqual(fermentacion, maps:get(etapa, Lote2)),
    ?assertEqual(FermentadorId, maps:get(fermentador_id, Lote2)),
    {ok, Lote3} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(maduracion, maps:get(etapa, Lote3)),
    {ok, Lote4} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(envasado, maps:get(etapa, Lote4)),
    {ok, Lote5} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(terminado, maps:get(etapa, Lote5)),
    ?assertEqual({error, lote_terminado}, p80_lotes:avanzar(Id, #{})).

transicion_sin_fermentador_test() ->
    p80_test_util:asegurar_app(),
    {ok, Lote0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote sin fermentador">>),
        receta => <<"Stout">>,
        litros => 999999999
    }),
    Id = maps:get(id, Lote0),
    {ok, _Lote1} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(
        {error, sin_fermentador_disponible},
        p80_lotes:avanzar(Id, #{})
    ).

fermentador_preferido_test() ->
    p80_test_util:asegurar_app(),
    FermentadorId = crear_fermentador(5000),
    {ok, Lote0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote preferido">>),
        receta => <<"Amber Ale">>,
        litros => 1000,
        fermentador_id => FermentadorId
    }),
    Id = maps:get(id, Lote0),
    ?assertEqual(FermentadorId, maps:get(fermentador_id, Lote0)),
    {ok, _} = p80_lotes:avanzar(Id, #{}),
    {ok, Lote2} = p80_lotes:avanzar(Id, #{}),
    ?assertEqual(fermentacion, maps:get(etapa, Lote2)),
    ?assertEqual(FermentadorId, maps:get(fermentador_id, Lote2)).

fermentador_ocupado_test() ->
    p80_test_util:asegurar_app(),
    FermentadorId = crear_fermentador(100000),
    {ok, LoteA0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote A">>),
        receta => <<"Lager">>,
        litros => 1000
    }),
    IdA = maps:get(id, LoteA0),
    {ok, _} = p80_lotes:avanzar(IdA, #{}),
    {ok, LoteA2} = p80_lotes:avanzar(IdA, #{fermentador_id => FermentadorId}),
    ?assertEqual(fermentacion, maps:get(etapa, LoteA2)),
    {ok, LoteB0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote B">>),
        receta => <<"Lager">>,
        litros => 1000
    }),
    IdB = maps:get(id, LoteB0),
    {ok, _} = p80_lotes:avanzar(IdB, #{}),
    ?assertEqual(
        {error, fermentador_ocupado},
        p80_lotes:avanzar(IdB, #{fermentador_id => FermentadorId})
    ),
    LoteB2 = p80_lotes:estado(IdB),
    ?assertEqual(coccion, maps:get(etapa, LoteB2)).

lote_inexistente_test() ->
    p80_test_util:asegurar_app(),
    ?assertEqual({error, no_encontrado}, p80_lotes:estado(999999999)),
    ?assertEqual({error, no_encontrado}, p80_lotes:avanzar(999999999, #{})).

crear_fermentador(Capacidad) ->
    Nombre = p80_test_util:unico(<<"Fermentador pruebas">>),
    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => Nombre,
        capacidad_litros => Capacidad,
        temperatura_objetivo => 18.0
    }),
    maps:get(id, Fermentador).
