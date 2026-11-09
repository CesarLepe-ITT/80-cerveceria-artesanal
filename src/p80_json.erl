%%% @doc Codificacion JSON con normalizacion previa de terminos Erlang.
-module(p80_json).

-export([encode/1, decode/1, externo/1]).

encode(Termino) ->
    jsx:encode(externo(Termino)).

decode(Binario) when is_binary(Binario) ->
    try
        {ok, jsx:decode(Binario, [return_maps])}
    catch
        _:_ -> {error, json_invalido}
    end;
decode(_) ->
    {error, json_invalido}.

%% @doc Convierte mapas con claves atomo, `undefined', PIDs y tuplas a JSON seguro.
externo(undefined) -> null;
externo(null) -> null;
externo(true) -> true;
externo(false) -> false;
externo(Valor) when is_atom(Valor) -> atom_to_binary(Valor, utf8);
externo(Valor) when is_binary(Valor) -> Valor;
externo(Valor) when is_integer(Valor); is_float(Valor) -> Valor;
externo(Valor) when is_pid(Valor) -> list_to_binary(pid_to_list(Valor));
externo(Valor) when is_reference(Valor) -> list_to_binary(ref_to_list(Valor));
externo(Valor) when is_port(Valor) -> list_to_binary(port_to_list(Valor));
externo(Valor) when is_map(Valor) ->
    maps:from_list([
        {clave_externa(Clave), externo(Contenido)}
     || {Clave, Contenido} <- maps:to_list(Valor)
    ]);
externo(Valor) when is_list(Valor) ->
    [externo(Elemento) || Elemento <- Valor];
externo(Valor) when is_tuple(Valor) ->
    [externo(Elemento) || Elemento <- tuple_to_list(Valor)];
externo(_) ->
    null.

clave_externa(Clave) when is_binary(Clave) -> Clave;
clave_externa(Clave) when is_atom(Clave) -> atom_to_binary(Clave, utf8);
clave_externa(Clave) when is_integer(Clave) -> integer_to_binary(Clave);
clave_externa(Clave) -> iolist_to_binary(io_lib:format("~p", [Clave])).
