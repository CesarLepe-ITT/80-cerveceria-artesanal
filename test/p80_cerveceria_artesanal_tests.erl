-module(p80_cerveceria_artesanal_tests).
-include_lib("eunit/include/eunit.hrl").

aplicacion_iniciada_test() ->
    p80_test_util:asegurar_app(),
    ?assert(is_pid(whereis(p80_cerveceria_artesanal_sup))),
    ?assert(is_pid(whereis(p80_registro))),
    ?assert(is_pid(whereis(p80_eventos))),
    ?assert(is_pid(whereis(p80_metricas))),
    ?assert(is_pid(whereis(p80_lote_sup))),
    ?assert(is_pid(whereis(p80_fermentador_sup))),
    ?assert(is_pid(whereis(p80_http))).

http_listener_activo_test() ->
    p80_test_util:asegurar_app(),
    Puerto = p80_test_util:puerto(),
    ?assert(is_integer(Puerto)),
    ?assert(Puerto > 0).

modulos_de_dominio_disponibles_test() ->
    p80_test_util:asegurar_app(),
    ?assert(is_list(p80_lotes:listar())),
    ?assert(is_list(p80_fermentadores:listar())),
    ?assert(is_map(p80_metricas:resumen())).
