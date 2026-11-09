-module(p80_caos_tests).
-include_lib("eunit/include/eunit.hrl").

caida_del_control_de_temperatura_test() ->
    p80_test_util:asegurar_app(),
    timer:sleep(100),

    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => p80_test_util:unico(<<"Fermentador caos">>),
        capacidad_litros => 2000,
        temperatura_objetivo => 18.0,
        tolerancia => 1.0
    }),
    FermentadorId = maps:get(id, Fermentador),

    {ok, Lote0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote caos">>),
        receta => <<"IPA">>,
        litros => 1000
    }),
    LoteId = maps:get(id, Lote0),
    {ok, _} = p80_lotes:avanzar(LoteId, #{}),
    {ok, Lote2} = p80_lotes:avanzar(LoteId, #{fermentador_id => FermentadorId}),
    ?assertEqual(fermentacion, maps:get(etapa, Lote2)),

    Control1 = whereis(p80_control_temperatura),
    Vigilante1 = whereis(p80_vigilante),
    ?assert(is_pid(Control1)),
    ?assert(is_pid(Vigilante1)),
    Caidas1 = maps:get(caidas_control_temperatura, p80_metricas:resumen()),

    exit(Control1, kill),

    ?assert(p80_test_util:esperar(
        fun() ->
            case whereis(p80_control_temperatura) of
                Pid when is_pid(Pid), Pid =/= Control1 -> true;
                _ -> false
            end
        end,
        100
    )),
    ?assertEqual(Vigilante1, whereis(p80_vigilante)),

    ?assert(p80_test_util:esperar(
        fun() ->
            case p80_lotes:estado(LoteId) of
                #{en_riesgo := true} -> true;
                _ -> false
            end
        end,
        100
    )),
    ?assert(p80_test_util:esperar(
        fun() ->
            maps:get(caidas_control_temperatura, p80_metricas:resumen()) > Caidas1
        end,
        100
    )),

    p80_eventos:sincronizar(),
    Eventos = p80_eventos:recientes(500),
    ?assert(lists:any(
        fun(#{tipo := control_temperatura_caido}) -> true; (_) -> false end,
        Eventos
    )),
    ?assert(lists:any(
        fun(#{tipo := riesgo_por_fallo_control}) -> true; (_) -> false end,
        Eventos
    )),

    {ok, _} = p80_fermentadores:actualizar_temperatura_actual(FermentadorId, 30.0),
    FermentadorCaliente = p80_fermentadores:estado(FermentadorId),
    ?assertEqual(true, maps:get(en_alerta, FermentadorCaliente)),

    {ok, 200, #{lotes := _}} = p80_test_util:peticion(get, "/api/lotes", undefined),
    ?assert(is_pid(whereis(p80_control_temperatura))).
