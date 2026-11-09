%%% @doc Punto de entrada de la aplicacion OTP.
-module(p80_cerveceria_artesanal_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_TipoArranque, _Argumentos) ->
    logger:info("Iniciando Cerveceria Artesanal", #{aplicacion => ?MODULE}),
    p80_cerveceria_artesanal_sup:start_link().

stop(_Estado) ->
    logger:info("Deteniendo Cerveceria Artesanal", #{aplicacion => ?MODULE}),
    ok.
