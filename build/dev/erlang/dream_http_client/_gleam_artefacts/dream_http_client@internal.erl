-module(dream_http_client@internal).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/internal.gleam").
-export([atomize_method/1, start_httpc_stream/2, extract_owner_pid/1, receive_next/2, start_stream_messages/6, cancel_stream_internal/1, cancel_stream_by_string/1, receive_stream_message/1, decode_stream_message_for_selector/1]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(false).

-file("src/dream_http_client/internal.gleam", 49).
?DOC(false).
-spec atomize_method(gleam@http:method()) -> gleam@erlang@atom:atom_().
atomize_method(Method) ->
    case Method of
        get ->
            erlang:binary_to_atom(<<"get"/utf8>>);

        post ->
            erlang:binary_to_atom(<<"post"/utf8>>);

        put ->
            erlang:binary_to_atom(<<"put"/utf8>>);

        delete ->
            erlang:binary_to_atom(<<"delete"/utf8>>);

        patch ->
            erlang:binary_to_atom(<<"patch"/utf8>>);

        head ->
            erlang:binary_to_atom(<<"head"/utf8>>);

        options ->
            erlang:binary_to_atom(<<"options"/utf8>>);

        trace ->
            erlang:binary_to_atom(<<"trace"/utf8>>);

        connect ->
            erlang:binary_to_atom(<<"connect"/utf8>>);

        {other, Method_string} ->
            erlang:binary_to_atom(string:lowercase(Method_string))
    end.

-file("src/dream_http_client/internal.gleam", 80).
?DOC(false).
-spec start_httpc_stream(gleam@http@request:request(binary()), integer()) -> gleam@dynamic:dynamic_().
start_httpc_stream(Request, Timeout_ms) ->
    Port_string = case erlang:element(7, Request) of
        {some, Port} ->
            <<":"/utf8, (erlang:integer_to_binary(Port))/binary>>;

        none ->
            <<""/utf8>>
    end,
    Url = <<<<<<<<(gleam@http:scheme_to_string(erlang:element(5, Request)))/binary,
                    "://"/utf8>>/binary,
                (erlang:element(6, Request))/binary>>/binary,
            Port_string/binary>>/binary,
        (erlang:element(8, Request))/binary>>,
    Method_atom = atomize_method(erlang:element(2, Request)),
    Body = <<(erlang:element(4, Request))/binary>>,
    Receiver = erlang:self(),
    dream_httpc_shim:request_stream(
        Method_atom,
        Url,
        erlang:element(3, Request),
        Body,
        Receiver,
        Timeout_ms
    ).

-file("src/dream_http_client/internal.gleam", 114).
?DOC(false).
-spec extract_owner_pid(gleam@dynamic:dynamic_()) -> gleam@dynamic:dynamic_().
extract_owner_pid(Request_result) ->
    case gleam@dynamic@decode:run(
        Request_result,
        gleam@dynamic@decode:at(
            [1],
            {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
        )
    ) of
        {ok, Pid} ->
            Pid;

        {error, Decode_errors} ->
            Error_details = gleam@string:inspect(Decode_errors),
            gleam_stdlib:println_error(
                <<"WARNING: Failed to extract owner PID - this should not happen. Error: "/utf8,
                    Error_details/binary>>
            ),
            Request_result
    end.

-file("src/dream_http_client/internal.gleam", 175).
?DOC(false).
-spec convert_to_atom(gleam@dynamic:dynamic_()) -> {ok,
        gleam@erlang@atom:atom_()} |
    {error, any()}.
convert_to_atom(Dyn) ->
    {ok, gleam_erlang_ffi:identity(Dyn)}.

-file("src/dream_http_client/internal.gleam", 149).
?DOC(false).
-spec receive_next(gleam@dynamic:dynamic_(), integer()) -> {ok,
        gleam@option:option(bitstring())} |
    {error, binary()}.
receive_next(Owner, Timeout_ms) ->
    Resp = dream_httpc_shim:fetch_next(Owner, Timeout_ms),
    Tag = begin
        _pipe = gleam@dynamic@decode:run(
            Resp,
            gleam@dynamic@decode:at(
                [0],
                {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
            )
        ),
        _pipe@1 = gleam@result:'try'(_pipe, fun convert_to_atom/1),
        _pipe@2 = gleam@result:unwrap(
            _pipe@1,
            erlang:binary_to_atom(<<""/utf8>>)
        ),
        erlang:atom_to_binary(_pipe@2)
    end,
    case Tag of
        <<"chunk"/utf8>> ->
            Bin = begin
                _pipe@3 = gleam@dynamic@decode:run(
                    Resp,
                    gleam@dynamic@decode:at(
                        [1],
                        {decoder, fun gleam@dynamic@decode:decode_bit_array/1}
                    )
                ),
                gleam@result:unwrap(_pipe@3, <<>>)
            end,
            {ok, {some, Bin}};

        <<"finished"/utf8>> ->
            {ok, none};

        <<"error"/utf8>> ->
            Reason = begin
                _pipe@4 = gleam@dynamic@decode:run(
                    Resp,
                    gleam@dynamic@decode:at(
                        [1],
                        {decoder, fun gleam@dynamic@decode:decode_string/1}
                    )
                ),
                gleam@result:unwrap(_pipe@4, <<"Unknown stream error"/utf8>>)
            end,
            {error, Reason};

        _ ->
            {error, <<"Unexpected stream message tag: "/utf8, Tag/binary>>}
    end.

-file("src/dream_http_client/internal.gleam", 213).
?DOC(false).
-spec start_stream_messages(
    gleam@erlang@atom:atom_(),
    binary(),
    list({binary(), binary()}),
    bitstring(),
    gleam@erlang@process:pid_(),
    integer()
) -> gleam@dynamic:dynamic_().
start_stream_messages(Method, Url, Headers, Body, Receiver, Timeout_ms) ->
    dream_httpc_shim:request_stream_messages(
        Method,
        Url,
        Headers,
        Body,
        Receiver,
        Timeout_ms
    ).

-file("src/dream_http_client/internal.gleam", 240).
?DOC(false).
-spec cancel_stream_internal(gleam@dynamic:dynamic_()) -> nil.
cancel_stream_internal(Request_id) ->
    dream_httpc_shim:cancel_stream(Request_id).

-file("src/dream_http_client/internal.gleam", 260).
?DOC(false).
-spec cancel_stream_by_string(binary()) -> nil.
cancel_stream_by_string(Request_id_string) ->
    dream_httpc_shim:cancel_stream_by_string(Request_id_string).

-file("src/dream_http_client/internal.gleam", 286).
?DOC(false).
-spec receive_stream_message(integer()) -> gleam@dynamic:dynamic_().
receive_stream_message(Timeout_ms) ->
    dream_httpc_shim:receive_stream_message(Timeout_ms).

-file("src/dream_http_client/internal.gleam", 314).
?DOC(false).
-spec decode_stream_message_for_selector(gleam@dynamic:dynamic_()) -> gleam@dynamic:dynamic_().
decode_stream_message_for_selector(Message) ->
    dream_httpc_shim:decode_stream_message_for_selector(Message).
