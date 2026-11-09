-module(p80_api_tests).
-include_lib("eunit/include/eunit.hrl").

crear_y_consultar_lote_api_test() ->
    p80_test_util:asegurar_app(),
    Nombre = p80_test_util:unico(<<"Lote API">>),
    {ok, 201, Respuesta} = p80_test_util:peticion(
        post,
        "/api/lotes",
        json(#{nombre => Nombre, receta => <<"IPA">>, litros => 500})
    ),
    #{lote := Lote} = Respuesta,
    Id = maps:get(id, Lote),
    ?assertEqual(<<"molienda">>, maps:get(etapa, Lote)),
    {ok, 200, #{lote := Consulta}} = p80_test_util:peticion(
        get,
        "/api/lotes/" ++ integer_to_list(Id),
        undefined
    ),
    ?assertEqual(Nombre, maps:get(nombre, Consulta)),
    {ok, 200, #{lotes := Lotes}} = p80_test_util:peticion(get, "/api/lotes", undefined),
    ?assert(lists:any(fun(L) -> maps:get(id, L) =:= Id end, Lotes)),
    {ok, 400, _} = p80_test_util:peticion(get, "/api/lotes?etapa=invalida", undefined).

avanzar_lote_api_test() ->
    p80_test_util:asegurar_app(),
    {ok, 201, #{fermentador := Fermentador}} = p80_test_util:peticion(
        post,
        "/api/fermentadores",
        json(#{
            nombre => p80_test_util:unico(<<"Fermentador API">>),
            capacidad_litros => 2000,
            temperatura_objetivo => 18.0
        })
    ),
    FermentadorId = maps:get(id, Fermentador),
    {ok, 201, #{lote := Lote}} = p80_test_util:peticion(
        post,
        "/api/lotes",
        json(#{
            nombre => p80_test_util:unico(<<"Lote avance API">>),
            receta => <<"Pale Ale">>,
            litros => 1000
        })
    ),
    Id = maps:get(id, Lote),
    Ruta = "/api/lotes/" ++ integer_to_list(Id) ++ "/avanzar",
    {ok, 200, #{lote := Lote1}} = p80_test_util:peticion(post, Ruta, json(#{})),
    ?assertEqual(<<"coccion">>, maps:get(etapa, Lote1)),
    {ok, 200, #{lote := Lote2}} = p80_test_util:peticion(
        post,
        Ruta,
        json(#{fermentador_id => FermentadorId})
    ),
    ?assertEqual(<<"fermentacion">>, maps:get(etapa, Lote2)),
    {ok, 405, _} = p80_test_util:peticion(get, Ruta, undefined).

fermentadores_api_test() ->
    p80_test_util:asegurar_app(),
    Nombre = p80_test_util:unico(<<"Fermentador API 2">>),
    {ok, 201, #{fermentador := Fermentador}} = p80_test_util:peticion(
        post,
        "/api/fermentadores",
        json(#{nombre => Nombre, capacidad_litros => 900, temperatura_objetivo => 18.0})
    ),
    Id = maps:get(id, Fermentador),
    Ruta = "/api/fermentadores/" ++ integer_to_list(Id),
    {ok, 200, #{fermentador := Consulta}} = p80_test_util:peticion(get, Ruta, undefined),
    ?assertEqual(Nombre, maps:get(nombre, Consulta)),
    {ok, 200, #{fermentador := Objetivo}} = p80_test_util:peticion(
        put,
        Ruta ++ "/temperatura",
        json(#{temperatura_objetivo => 17.5})
    ),
    ?assertEqual(17.5, maps:get(temperatura_objetivo, Objetivo)),
    {ok, 200, #{fermentador := Caliente}} = p80_test_util:peticion(
        put,
        Ruta ++ "/temperatura-actual",
        json(#{temperatura_actual => 30.0})
    ),
    ?assertEqual(true, maps:get(en_alerta, Caliente)),
    {ok, 200, #{fermentadores := Lista}} = p80_test_util:peticion(
        get,
        "/api/fermentadores",
        undefined
    ),
    ?assert(lists:any(fun(F) -> maps:get(id, F) =:= Id end, Lista)).

metricas_salud_y_diagnostico_test() ->
    p80_test_util:asegurar_app(),
    {ok, 200, #{metricas := Metricas}} = p80_test_util:peticion(
        get,
        "/api/metricas",
        undefined
    ),
    ?assert(is_map(maps:get(lotes_por_etapa, Metricas))),
    ?assert(is_integer(maps:get(litros_producidos, Metricas))),
    {ok, 200, CuerpoMetricas} = p80_test_util:peticion(get, "/metrics", undefined),
    ?assert(is_binary(CuerpoMetricas)),
    ?assert(binary:match(CuerpoMetricas, <<"cerveceria_lotes_por_etapa">>) =/= nomatch),
    {ok, 200, #{estado := <<"ok">>}} = p80_test_util:peticion(get, "/health", undefined),
    {ok, 200, #{diagnostico := Diagnostico}} = p80_test_util:peticion(
        get,
        "/api/diagnostico",
        undefined
    ),
    ?assert(is_list(maps:get(top_memoria, Diagnostico))).

eventos_api_test() ->
    p80_test_util:asegurar_app(),
    p80_eventos:publicar(evento_prueba_api, #{origen => <<"eunit">>}),
    p80_eventos:sincronizar(),
    {ok, 200, #{eventos := Eventos}} = p80_test_util:peticion(
        get,
        "/api/eventos?limite=20",
        undefined
    ),
    ?assert(is_list(Eventos)),
    ?assert(length(Eventos) =< 20),
    {ok, 400, _} = p80_test_util:peticion(get, "/api/eventos?limite=0", undefined).

errores_api_test() ->
    p80_test_util:asegurar_app(),
    {ok, 400, _} = p80_test_util:peticion(post, "/api/lotes", <<"{json invalido">>),
    {ok, 404, _} = p80_test_util:peticion(get, "/api/lotes/999999999", undefined),
    {ok, 404, _} = p80_test_util:peticion(
        get,
        "/api/fermentadores/999999999",
        undefined
    ),
    {ok, 405, _} = p80_test_util:peticion(delete, "/api/lotes", undefined).

json(Mapa) ->
    p80_json:encode(Mapa).
