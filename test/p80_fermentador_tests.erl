-module(p80_fermentador_tests).
-include_lib("eunit/include/eunit.hrl").

creacion_y_consulta_test() ->
    p80_test_util:asegurar_app(),
    Nombre = p80_test_util:unico(<<"Fermentador creacion">>),
    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => Nombre,
        capacidad_litros => 1200,
        temperatura_objetivo => 19.0,
        temperatura_actual => 19.2,
        tolerancia => 1.0
    }),
    Id = maps:get(id, Fermentador),
    ?assertEqual(Nombre, maps:get(nombre, Fermentador)),
    ?assertEqual(1200, maps:get(capacidad_litros, Fermentador)),
    Consulta = p80_fermentadores:estado(Id),
    ?assertEqual(19.0, maps:get(temperatura_objetivo, Consulta)),
    ?assertEqual(false, maps:get(en_alerta, Consulta)),
    ?assert(lists:any(fun(F) -> maps:get(id, F) =:= Id end, p80_fermentadores:listar())).

actualizacion_temperatura_objetivo_test() ->
    p80_test_util:asegurar_app(),
    Id = crear_fermentador(800, 18.0),
    {ok, Fermentador} = p80_fermentadores:fijar_temperatura_objetivo(Id, 20.5),
    ?assertEqual(20.5, maps:get(temperatura_objetivo, Fermentador)),
    Consulta = p80_fermentadores:estado(Id),
    ?assertEqual(20.5, maps:get(temperatura_objetivo, Consulta)).

deteccion_y_normalizacion_de_desviacion_test() ->
    p80_test_util:asegurar_app(),
    Id = crear_fermentador(900, 18.0),
    {ok, Normal} = p80_fermentadores:actualizar_temperatura_actual(Id, 18.4),
    ?assertEqual(false, maps:get(en_alerta, Normal)),
    {ok, Caliente} = p80_fermentadores:actualizar_temperatura_actual(Id, 25.0),
    ?assertEqual(true, maps:get(en_alerta, Caliente)),
    ?assertEqual(7.0, maps:get(desviacion, Caliente)),
    p80_eventos:sincronizar(),
    Eventos = p80_eventos:recientes(500),
    ?assert(lists:any(
        fun(#{tipo := alerta_temperatura}) -> true; (_) -> false end,
        Eventos
    )),
    {ok, Frio} = p80_fermentadores:actualizar_temperatura_actual(Id, 18.5),
    ?assertEqual(false, maps:get(en_alerta, Frio)),
    p80_eventos:sincronizar(),
    Eventos2 = p80_eventos:recientes(500),
    ?assert(lists:any(
        fun(#{tipo := temperatura_normalizada}) -> true; (_) -> false end,
        Eventos2
    )).

asignacion_y_liberacion_test() ->
    p80_test_util:asegurar_app(),
    Id = crear_fermentador(1000, 18.0),
    {ok, Lote} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote asignacion">>),
        receta => <<"Saison">>,
        litros => 500
    }),
    LoteId = maps:get(id, Lote),
    {ok, Asignado} = p80_fermentadores:asignar(Id, LoteId),
    ?assertEqual(LoteId, maps:get(lote_id, Asignado)),
    ?assertEqual(true, maps:get(activo, Asignado)),
    ok = p80_fermentadores:liberar_lote(Id, LoteId),
    Liberado = p80_fermentadores:estado(Id),
    ?assertEqual(undefined, maps:get(lote_id, Liberado)),
    ?assertEqual(false, maps:get(activo, Liberado)).

fermentador_inexistente_test() ->
    p80_test_util:asegurar_app(),
    ?assertEqual({error, no_encontrado}, p80_fermentadores:estado(999999999)).

crear_fermentador(Capacidad, Objetivo) ->
    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => p80_test_util:unico(<<"Fermentador pruebas">>),
        capacidad_litros => Capacidad,
        temperatura_objetivo => Objetivo
    }),
    maps:get(id, Fermentador).
