-module(p80_supervision_tests).
-include_lib("eunit/include/eunit.hrl").

fermentador_se_recupera_test() ->
    p80_test_util:asegurar_app(),
    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => p80_test_util:unico(<<"Fermentador supervision">>),
        capacidad_litros => 1000,
        temperatura_objetivo => 18.0
    }),
    Id = maps:get(id, Fermentador),
    Pid1 = p80_fermentadores:pid(Id),
    ?assert(is_pid(Pid1)),
    exit(Pid1, kill),
    ?assert(p80_test_util:esperar(
        fun() ->
            case p80_fermentadores:pid(Id) of
                Pid when is_pid(Pid), Pid =/= Pid1 -> true;
                _ -> false
            end
        end,
        100
    )),
    Recuperado = p80_fermentadores:estado(Id),
    ?assertEqual(18.0, maps:get(temperatura_objetivo, Recuperado)).

lote_se_recupera_con_estado_test() ->
    p80_test_util:asegurar_app(),
    {ok, Fermentador} = p80_fermentadores:crear(#{
        nombre => p80_test_util:unico(<<"Fermentador lote">>),
        capacidad_litros => 2000,
        temperatura_objetivo => 18.0
    }),
    FermentadorId = maps:get(id, Fermentador),
    {ok, Lote0} = p80_lotes:crear(#{
        nombre => p80_test_util:unico(<<"Lote supervision">>),
        receta => <<"IPA">>,
        litros => 1000
    }),
    Id = maps:get(id, Lote0),
    {ok, _} = p80_lotes:avanzar(Id, #{}),
    {ok, Lote2} = p80_lotes:avanzar(Id, #{fermentador_id => FermentadorId}),
    ?assertEqual(fermentacion, maps:get(etapa, Lote2)),
    Pid1 = p80_lotes:pid(Id),
    ?assert(is_pid(Pid1)),
    exit(Pid1, kill),
    ?assert(p80_test_util:esperar(
        fun() ->
            case p80_lotes:pid(Id) of
                Pid when is_pid(Pid), Pid =/= Pid1 -> true;
                _ -> false
            end
        end,
        100
    )),
    Recuperado = p80_lotes:estado(Id),
    ?assertEqual(fermentacion, maps:get(etapa, Recuperado)),
    ?assertEqual(FermentadorId, maps:get(fermentador_id, Recuperado)).

control_se_recupera_y_vigilante_sobrevive_test() ->
    p80_test_util:asegurar_app(),
    timer:sleep(100),
    Control1 = whereis(p80_control_temperatura),
    Vigilante1 = whereis(p80_vigilante),
    ?assert(is_pid(Control1)),
    ?assert(is_pid(Vigilante1)),
    Inicios1 = maps:get(inicios_control_temperatura, p80_metricas:resumen()),
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
    Inicios2 = maps:get(inicios_control_temperatura, p80_metricas:resumen()),
    ?assert(Inicios2 > Inicios1).
