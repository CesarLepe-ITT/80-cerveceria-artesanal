%%% @doc Handler de diagnostico con integracion a recon.
-module(p80_api_diagnostico_h).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Diagnostico = diagnostico(),
            p80_http_util:respond(200, #{diagnostico => Diagnostico}, Req0);
        _ ->
            p80_http_util:metodo_no_permitido([<<"GET">>], Req0)
    end.

diagnostico() ->
    #{
        otp => list_to_binary(erlang:system_info(otp_release)),
        procesos => erlang:system_info(process_count),
        limite_procesos => erlang:system_info(process_limit),
        memoria => maps:from_list(erlang:memory()),
        uptime_ms => uptime_ms(),
        top_memoria => top_procesos(memory, 5),
        top_reducciones => top_procesos(reductions, 5),
        control_temperatura => whereis(p80_control_temperatura)
    }.

uptime_ms() ->
    case erlang:statistics(wall_clock) of
        {Total, _DesdeUltima} -> Total
    end.

top_procesos(Atributo, Cantidad) ->
    try recon:proc_count(Atributo, Cantidad) of
        Procesos ->
            [
                #{
                    pid => list_to_binary(pid_to_list(Pid)),
                    valor => Valor
                }
             || {Pid, Valor, _Info} <- Procesos
            ]
    catch
        _:_ -> []
    end.
