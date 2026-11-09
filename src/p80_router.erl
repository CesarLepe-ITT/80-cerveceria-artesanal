%%% @doc Rutas HTTP de la aplicacion.
-module(p80_router).

-export([rutas/0]).

rutas() ->
    [
        {"/", cowboy_static, {priv_file, p80_cerveceria_artesanal, "static/index.html"}},
        {"/static/[...]", cowboy_static, {priv_dir, p80_cerveceria_artesanal, "static"}},
        {"/health", p80_health_h, []},
        {"/metrics", p80_metrics_h, []},
        {"/api/diagnostico", p80_api_diagnostico_h, []},
        {"/api/metricas", p80_api_metricas_h, []},
        {"/api/eventos/sse", p80_sse_h, []},
        {"/api/eventos", p80_api_eventos_h, []},
        {"/api/lotes/:id/avanzar", p80_api_lote_h, #{accion => avanzar}},
        {"/api/lotes/:id", p80_api_lote_h, #{accion => detalle}},
        {"/api/lotes", p80_api_lotes_h, []},
        {"/api/fermentadores/:id/temperatura-actual", p80_api_fermentador_h, #{accion => temperatura_actual}},
        {"/api/fermentadores/:id/temperatura", p80_api_fermentador_h, #{accion => temperatura}},
        {"/api/fermentadores/:id", p80_api_fermentador_h, #{accion => detalle}},
        {"/api/fermentadores", p80_api_fermentadores_h, []}
    ].
