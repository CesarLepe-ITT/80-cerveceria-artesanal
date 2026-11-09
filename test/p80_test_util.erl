%%% @doc Utilidades comunes para las pruebas EUnit.
-module(p80_test_util).

-export([
    asegurar_app/0,
    esperar/2,
    puerto/0,
    peticion/3,
    unico/1
]).

asegurar_app() ->
    _ = application:load(p80_cerveceria_artesanal),
    application:set_env(p80_cerveceria_artesanal, http_port, 0),
    application:set_env(p80_cerveceria_artesanal, control_temperatura_ms, 60000),
    application:set_env(p80_cerveceria_artesanal, sse_heartbeat_ms, 60000),
    application:set_env(p80_cerveceria_artesanal, max_eventos, 2000),
    {ok, _} = application:ensure_all_started(inets),
    case application:ensure_all_started(p80_cerveceria_artesanal, temporary) of
        {ok, _Iniciadas} -> ok;
        {error, {p80_cerveceria_artesanal, {already_started, _Pid}}} -> ok;
        {error, Motivo} -> error({no_se_pudo_iniciar_aplicacion, Motivo})
    end.

esperar(Fun, Intentos) when is_function(Fun, 0), Intentos > 0 ->
    try Fun() of
        true -> true;
        _ ->
            timer:sleep(50),
            esperar(Fun, Intentos - 1)
    catch
        _:_ ->
            timer:sleep(50),
            esperar(Fun, Intentos - 1)
    end;
esperar(_Fun, 0) ->
    false.

puerto() ->
    p80_http:puerto().

peticion(Metodo, Ruta, Cuerpo) ->
    Url = lists:flatten(io_lib:format("http://127.0.0.1:~p~s", [puerto(), Ruta])),
    Cabeceras = [{"content-type", "application/json"}],
    Solicitud = case Metodo of
        get -> {Url, Cabeceras};
        delete -> {Url, Cabeceras};
        _ -> {Url, Cabeceras, "application/json", Cuerpo}
    end,
    case httpc:request(Metodo, Solicitud, [], [{body_format, binary}]) of
        {ok, {{_Version, Status, _Razon}, _CabecerasRespuesta, CuerpoRespuesta}} ->
            {ok, Status, decodificar(CuerpoRespuesta)};
        {error, Motivo} ->
            {error, Motivo}
    end.

unico(Prefijo) ->
    iolist_to_binary([
        Prefijo,
        <<"-">>,
        integer_to_binary(erlang:unique_integer([positive]))
    ]).

decodificar(<<>>) ->
    #{};
decodificar(Binario) ->
    try
        jsx:decode(Binario, [return_maps, {labels, attempt_atom}])
    catch
        _:_ -> Binario
    end.
