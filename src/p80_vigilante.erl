%%% @doc Vigilante del proceso de control de temperatura.
%%%
%%% Se coloca antes que el control en el arbol de supervision. Si el control
%%% cae, este proceso sobrevive, registra la alerta, marca los lotes asociados
%%% como en riesgo y espera a que el supervisor levante el nuevo control.
-module(p80_vigilante).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! reanudar_monitor,
    {ok, #{ref => undefined, control => undefined}}.

handle_call(_Solicitud, _From, State) ->
    {reply, {error, desconocido}, State}.

handle_cast(_Mensaje, State) ->
    {noreply, State}.

handle_info({control_iniciado, Pid}, #{ref := undefined} = State) when is_pid(Pid) ->
    Ref = erlang:monitor(process, Pid),
    {noreply, State#{ref => Ref, control => Pid}};
handle_info({control_iniciado, _Pid}, State) ->
    {noreply, State};
handle_info(reanudar_monitor, #{ref := Ref} = State) when is_reference(Ref) ->
    {noreply, State};
handle_info(reanudar_monitor, State) ->
    case whereis(p80_control_temperatura) of
        undefined ->
            erlang:send_after(200, self(), reanudar_monitor),
            {noreply, State#{ref => undefined, control => undefined}};
        Pid ->
            Ref = erlang:monitor(process, Pid),
            {noreply, State#{ref => Ref, control => Pid}}
    end;
handle_info({'DOWN', Ref, process, Pid, Razon}, #{ref := Ref, control := Pid} = State) ->
    p80_metricas:inc(caidas_control_temperatura),
    p80_eventos:publicar(control_temperatura_caido, #{
        pid => Pid,
        razon => Razon,
        severidad => alta
    }),
    marcar_lotes_en_riesgo(
        <<"Control de temperatura caido; lecturas no confiables">>
    ),
    erlang:send_after(200, self(), reanudar_monitor),
    {noreply, State#{ref => undefined, control => undefined}};
handle_info({'DOWN', _Ref, process, _Pid, _Razon}, State) ->
    {noreply, State};
handle_info(_Informacion, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    ok.

marcar_lotes_en_riesgo(Motivo) ->
    Fermentadores = p80_fermentadores:listar(),
    Lotes = [
        {maps:get(id, F), maps:get(lote_id, F)}
     || F <- Fermentadores,
        maps:get(lote_id, F, undefined) =/= undefined
    ],
    lists:foreach(
        fun({_FermentadorId, LoteId}) ->
            catch p80_lotes:marcar_en_riesgo(LoteId, Motivo)
        end,
        Lotes
    ),
    p80_eventos:publicar(riesgo_por_fallo_control, #{
        motivo => Motivo,
        lotes => [LoteId || {_FermentadorId, LoteId} <- Lotes]
    }).
