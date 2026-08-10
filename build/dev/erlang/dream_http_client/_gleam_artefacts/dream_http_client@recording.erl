-module(dream_http_client@recording).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/recording.gleam").
-export([encode_recording_file/1, decode_recording_file/1]).
-export_type([recorded_request/0, recorded_response/0, chunk/0, recording/0, recording_file/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Recording format types and JSON codecs\n"
    "\n"
    " Defines the structure for storing HTTP request/response recordings\n"
    " in a custom JSON format that supports both blocking and streaming responses.\n"
).

-type recorded_request() :: {recorded_request,
        gleam@http:method(),
        gleam@http:scheme(),
        binary(),
        gleam@option:option(integer()),
        binary(),
        gleam@option:option(binary()),
        list({binary(), binary()}),
        binary()}.

-type recorded_response() :: {blocking_response,
        integer(),
        list({binary(), binary()}),
        binary()} |
    {streaming_response, integer(), list({binary(), binary()}), list(chunk())}.

-type chunk() :: {chunk, bitstring(), integer()}.

-type recording() :: {recording, recorded_request(), recorded_response()}.

-type recording_file() :: {recording_file, binary(), list(recording())}.

-file("src/dream_http_client/recording.gleam", 217).
-spec identity_json(gleam@json:json()) -> gleam@json:json().
identity_json(Value) ->
    Value.

-file("src/dream_http_client/recording.gleam", 298).
-spec encode_header_pair({binary(), binary()}) -> gleam@json:json().
encode_header_pair(Header) ->
    gleam@json:array(
        [gleam@json:string(erlang:element(1, Header)),
            gleam@json:string(erlang:element(2, Header))],
        fun identity_json/1
    ).

-file("src/dream_http_client/recording.gleam", 293).
-spec encode_headers(list({binary(), binary()})) -> gleam@json:json().
encode_headers(Headers) ->
    Header_arrays = gleam@list:map(Headers, fun encode_header_pair/1),
    gleam@json:array(Header_arrays, fun identity_json/1).

-file("src/dream_http_client/recording.gleam", 270).
-spec encode_chunk(chunk()) -> gleam@json:json().
encode_chunk(Chunk) ->
    Data_str = case gleam@bit_array:to_string(erlang:element(2, Chunk)) of
        {ok, String_value} ->
            String_value;

        {error, Utf8_decode_error} ->
            gleam_stdlib:println_error(
                <<"Failed to encode recording chunk as UTF-8 string: "/utf8,
                    (gleam@string:inspect(Utf8_decode_error))/binary>>
            ),
            <<""/utf8>>
    end,
    gleam@json:object(
        [{<<"data"/utf8>>, gleam@json:string(Data_str)},
            {<<"delay_ms"/utf8>>, gleam@json:int(erlang:element(3, Chunk))}]
    ).

-file("src/dream_http_client/recording.gleam", 249).
-spec encode_recorded_response(recorded_response()) -> gleam@json:json().
encode_recorded_response(Resp) ->
    case Resp of
        {blocking_response, Status, Headers, Body} ->
            gleam@json:object(
                [{<<"mode"/utf8>>, gleam@json:string(<<"blocking"/utf8>>)},
                    {<<"status"/utf8>>, gleam@json:int(Status)},
                    {<<"headers"/utf8>>, encode_headers(Headers)},
                    {<<"body"/utf8>>, gleam@json:string(Body)}]
            );

        {streaming_response, Status@1, Headers@1, Chunks} ->
            Chunks_json = gleam@list:map(Chunks, fun encode_chunk/1),
            gleam@json:object(
                [{<<"mode"/utf8>>, gleam@json:string(<<"streaming"/utf8>>)},
                    {<<"status"/utf8>>, gleam@json:int(Status@1)},
                    {<<"headers"/utf8>>, encode_headers(Headers@1)},
                    {<<"chunks"/utf8>>,
                        gleam@json:array(Chunks_json, fun identity_json/1)}]
            )
    end.

-file("src/dream_http_client/recording.gleam", 321).
-spec encode_scheme(gleam@http:scheme()) -> gleam@json:json().
encode_scheme(Scheme) ->
    Scheme_str = case Scheme of
        http ->
            <<"http"/utf8>>;

        https ->
            <<"https"/utf8>>
    end,
    gleam@json:string(Scheme_str).

-file("src/dream_http_client/recording.gleam", 305).
-spec encode_method(gleam@http:method()) -> gleam@json:json().
encode_method(Method) ->
    Method_str = case Method of
        get ->
            <<"GET"/utf8>>;

        post ->
            <<"POST"/utf8>>;

        put ->
            <<"PUT"/utf8>>;

        delete ->
            <<"DELETE"/utf8>>;

        patch ->
            <<"PATCH"/utf8>>;

        head ->
            <<"HEAD"/utf8>>;

        options ->
            <<"OPTIONS"/utf8>>;

        trace ->
            <<"TRACE"/utf8>>;

        connect ->
            <<"CONNECT"/utf8>>;

        {other, S} ->
            string:uppercase(S)
    end,
    gleam@json:string(Method_str).

-file("src/dream_http_client/recording.gleam", 228).
-spec encode_recorded_request(recorded_request()) -> gleam@json:json().
encode_recorded_request(Req) ->
    Port_json = case erlang:element(5, Req) of
        {some, P} ->
            gleam@json:int(P);

        none ->
            gleam@json:null()
    end,
    Query_json = case erlang:element(7, Req) of
        {some, Q} ->
            gleam@json:string(Q);

        none ->
            gleam@json:null()
    end,
    gleam@json:object(
        [{<<"method"/utf8>>, encode_method(erlang:element(2, Req))},
            {<<"scheme"/utf8>>, encode_scheme(erlang:element(3, Req))},
            {<<"host"/utf8>>, gleam@json:string(erlang:element(4, Req))},
            {<<"port"/utf8>>, Port_json},
            {<<"path"/utf8>>, gleam@json:string(erlang:element(6, Req))},
            {<<"query"/utf8>>, Query_json},
            {<<"headers"/utf8>>, encode_headers(erlang:element(8, Req))},
            {<<"body"/utf8>>, gleam@json:string(erlang:element(9, Req))}]
    ).

-file("src/dream_http_client/recording.gleam", 221).
-spec encode_recording(recording()) -> gleam@json:json().
encode_recording(Recording) ->
    gleam@json:object(
        [{<<"request"/utf8>>,
                encode_recorded_request(erlang:element(2, Recording))},
            {<<"response"/utf8>>,
                encode_recorded_response(erlang:element(3, Recording))}]
    ).

-file("src/dream_http_client/recording.gleam", 209).
?DOC(
    " Encode a `RecordingFile` to JSON\n"
    "\n"
    " Converts an in-memory `RecordingFile` value into a `json.Json` tree that can\n"
    " be rendered to a string and written to disk. This function handles the JSON\n"
    " encoding of all nested types (requests, responses, chunks, etc.).\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `file`: The recording file to encode\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A `json.Json` value representing the recording file structure, ready to be\n"
    " serialized with `json.to_string()`.\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let file = recording.RecordingFile(\n"
    "   version: \"1.0\",\n"
    "   entries: [recording1, recording2],\n"
    " )\n"
    "\n"
    " let json_value = recording.encode_recording_file(file)\n"
    " let json_string = json.to_string(json_value)\n"
    " // Now write json_string to disk\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Most callers should use `storage.save_recordings()` instead of calling this directly\n"
    " - This function is used internally by the storage module\n"
    " - The JSON format includes a version field for future compatibility\n"
).
-spec encode_recording_file(recording_file()) -> gleam@json:json().
encode_recording_file(File) ->
    Entries_json = gleam@list:map(
        erlang:element(3, File),
        fun encode_recording/1
    ),
    gleam@json:object(
        [{<<"version"/utf8>>, gleam@json:string(erlang:element(2, File))},
            {<<"entries"/utf8>>,
                gleam@json:array(Entries_json, fun identity_json/1)}]
    ).

-file("src/dream_http_client/recording.gleam", 414).
-spec format_single_decode_error(gleam@dynamic@decode:decode_error()) -> binary().
format_single_decode_error(Error) ->
    {decode_error, Expected, Found, Path} = Error,
    Field_path = gleam@string:join(Path, <<"."/utf8>>),
    <<<<<<<<<<"Expected "/utf8, Expected/binary>>/binary, ", found "/utf8>>/binary,
                Found/binary>>/binary,
            " at "/utf8>>/binary,
        Field_path/binary>>.

-file("src/dream_http_client/recording.gleam", 399).
-spec format_decode_errors(list(gleam@dynamic@decode:decode_error())) -> binary().
format_decode_errors(Errors) ->
    case gleam@list:first(Errors) of
        {ok, Error} ->
            format_single_decode_error(Error);

        {error, Empty_list_error} ->
            gleam_stdlib:println_error(
                <<"Decode error with no details in recording file: "/utf8,
                    (gleam@string:inspect(Empty_list_error))/binary>>
            ),
            <<"Decode error with no details"/utf8>>
    end.

-file("src/dream_http_client/recording.gleam", 501).
-spec decode_blocking_response_decoder(integer(), list({binary(), binary()})) -> gleam@dynamic@decode:decoder(recorded_response()).
decode_blocking_response_decoder(Status, Headers) ->
    gleam@dynamic@decode:field(
        <<"body"/utf8>>,
        {decoder, fun gleam@dynamic@decode:decode_string/1},
        fun(Body) ->
            gleam@dynamic@decode:success(
                {blocking_response, Status, Headers, Body}
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 521).
-spec decode_chunk_decoder() -> gleam@dynamic@decode:decoder(chunk()).
decode_chunk_decoder() ->
    gleam@dynamic@decode:field(
        <<"data"/utf8>>,
        {decoder, fun gleam@dynamic@decode:decode_string/1},
        fun(Data_str) ->
            gleam@dynamic@decode:field(
                <<"delay_ms"/utf8>>,
                {decoder, fun gleam@dynamic@decode:decode_int/1},
                fun(Delay_ms) ->
                    Data = <<Data_str/binary>>,
                    gleam@dynamic@decode:success({chunk, Data, Delay_ms})
                end
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 509).
-spec decode_streaming_response_decoder(integer(), list({binary(), binary()})) -> gleam@dynamic@decode:decoder(recorded_response()).
decode_streaming_response_decoder(Status, Headers) ->
    gleam@dynamic@decode:field(
        <<"chunks"/utf8>>,
        gleam@dynamic@decode:list(decode_chunk_decoder()),
        fun(Chunks) ->
            gleam@dynamic@decode:success(
                {streaming_response, Status, Headers, Chunks}
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 539).
-spec build_header_pair(binary()) -> fun((binary()) -> {binary(), binary()}).
build_header_pair(Name) ->
    fun(Value) -> {Name, Value} end.

-file("src/dream_http_client/recording.gleam", 534).
-spec build_header_value_decoder(binary()) -> gleam@dynamic@decode:decoder({binary(),
    binary()}).
build_header_value_decoder(Name) ->
    _pipe = gleam@dynamic@decode:at(
        [1],
        {decoder, fun gleam@dynamic@decode:decode_string/1}
    ),
    gleam@dynamic@decode:map(_pipe, build_header_pair(Name)).

-file("src/dream_http_client/recording.gleam", 529).
-spec decode_header_pair_decoder() -> gleam@dynamic@decode:decoder({binary(),
    binary()}).
decode_header_pair_decoder() ->
    _pipe = gleam@dynamic@decode:at(
        [0],
        {decoder, fun gleam@dynamic@decode:decode_string/1}
    ),
    gleam@dynamic@decode:then(_pipe, fun build_header_value_decoder/1).

-file("src/dream_http_client/recording.gleam", 486).
-spec decode_recorded_response_decoder() -> gleam@dynamic@decode:decoder(recorded_response()).
decode_recorded_response_decoder() ->
    gleam@dynamic@decode:field(
        <<"mode"/utf8>>,
        {decoder, fun gleam@dynamic@decode:decode_string/1},
        fun(Mode) ->
            gleam@dynamic@decode:field(
                <<"status"/utf8>>,
                {decoder, fun gleam@dynamic@decode:decode_int/1},
                fun(Status) ->
                    gleam@dynamic@decode:field(
                        <<"headers"/utf8>>,
                        gleam@dynamic@decode:list(decode_header_pair_decoder()),
                        fun(Headers) -> case Mode of
                                <<"blocking"/utf8>> ->
                                    decode_blocking_response_decoder(
                                        Status,
                                        Headers
                                    );

                                <<"streaming"/utf8>> ->
                                    decode_streaming_response_decoder(
                                        Status,
                                        Headers
                                    );

                                _ ->
                                    decode_blocking_response_decoder(
                                        Status,
                                        Headers
                                    )
                            end end
                    )
                end
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 558).
-spec parse_scheme_string(binary()) -> {ok, gleam@http:scheme()} |
    {error, binary()}.
parse_scheme_string(Scheme_str) ->
    case Scheme_str of
        <<"http"/utf8>> ->
            {ok, http};

        <<"https"/utf8>> ->
            {ok, https};

        _ ->
            {error, <<"Unknown scheme: "/utf8, Scheme_str/binary>>}
    end.

-file("src/dream_http_client/recording.gleam", 543).
-spec parse_method_string(binary()) -> {ok, gleam@http:method()} |
    {error, binary()}.
parse_method_string(Method_str) ->
    case string:lowercase(Method_str) of
        <<"get"/utf8>> ->
            {ok, get};

        <<"post"/utf8>> ->
            {ok, post};

        <<"put"/utf8>> ->
            {ok, put};

        <<"delete"/utf8>> ->
            {ok, delete};

        <<"patch"/utf8>> ->
            {ok, patch};

        <<"head"/utf8>> ->
            {ok, head};

        <<"options"/utf8>> ->
            {ok, options};

        <<"trace"/utf8>> ->
            {ok, trace};

        <<"connect"/utf8>> ->
            {ok, connect};

        _ ->
            {ok, {other, Method_str}}
    end.

-file("src/dream_http_client/recording.gleam", 426).
-spec decode_recorded_request_decoder() -> gleam@dynamic@decode:decoder(recorded_request()).
decode_recorded_request_decoder() ->
    gleam@dynamic@decode:field(
        <<"method"/utf8>>,
        {decoder, fun gleam@dynamic@decode:decode_string/1},
        fun(Method_str) ->
            gleam@dynamic@decode:field(
                <<"scheme"/utf8>>,
                {decoder, fun gleam@dynamic@decode:decode_string/1},
                fun(Scheme_str) ->
                    gleam@dynamic@decode:field(
                        <<"host"/utf8>>,
                        {decoder, fun gleam@dynamic@decode:decode_string/1},
                        fun(Host) ->
                            gleam@dynamic@decode:field(
                                <<"port"/utf8>>,
                                gleam@dynamic@decode:optional(
                                    {decoder,
                                        fun gleam@dynamic@decode:decode_int/1}
                                ),
                                fun(Port) ->
                                    gleam@dynamic@decode:field(
                                        <<"path"/utf8>>,
                                        {decoder,
                                            fun gleam@dynamic@decode:decode_string/1},
                                        fun(Path) ->
                                            gleam@dynamic@decode:field(
                                                <<"query"/utf8>>,
                                                gleam@dynamic@decode:optional(
                                                    {decoder,
                                                        fun gleam@dynamic@decode:decode_string/1}
                                                ),
                                                fun(Query) ->
                                                    gleam@dynamic@decode:field(
                                                        <<"headers"/utf8>>,
                                                        gleam@dynamic@decode:list(
                                                            decode_header_pair_decoder(
                                                                
                                                            )
                                                        ),
                                                        fun(Headers) ->
                                                            gleam@dynamic@decode:field(
                                                                <<"body"/utf8>>,
                                                                {decoder,
                                                                    fun gleam@dynamic@decode:decode_string/1},
                                                                fun(Body) ->
                                                                    Method = case parse_method_string(
                                                                        Method_str
                                                                    ) of
                                                                        {ok,
                                                                            Parsed_method} ->
                                                                            Parsed_method;

                                                                        {error,
                                                                            Parse_error} ->
                                                                            gleam_stdlib:println_error(
                                                                                <<"Failed to parse HTTP method in recording: "/utf8,
                                                                                    Parse_error/binary>>
                                                                            ),
                                                                            {other,
                                                                                Method_str}
                                                                    end,
                                                                    case parse_scheme_string(
                                                                        Scheme_str
                                                                    ) of
                                                                        {ok,
                                                                            Scheme} ->
                                                                            gleam@dynamic@decode:success(
                                                                                {recorded_request,
                                                                                    Method,
                                                                                    Scheme,
                                                                                    Host,
                                                                                    Port,
                                                                                    Path,
                                                                                    Query,
                                                                                    Headers,
                                                                                    Body}
                                                                            );

                                                                        {error,
                                                                            Parse_error@1} ->
                                                                            gleam_stdlib:println_error(
                                                                                <<"Unknown scheme in recording; defaulting to http: "/utf8,
                                                                                    Parse_error@1/binary>>
                                                                            ),
                                                                            gleam@dynamic@decode:success(
                                                                                {recorded_request,
                                                                                    Method,
                                                                                    http,
                                                                                    Host,
                                                                                    Port,
                                                                                    Path,
                                                                                    Query,
                                                                                    Headers,
                                                                                    Body}
                                                                            )
                                                                    end
                                                                end
                                                            )
                                                        end
                                                    )
                                                end
                                            )
                                        end
                                    )
                                end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 420).
-spec decode_recording_decoder() -> gleam@dynamic@decode:decoder(recording()).
decode_recording_decoder() ->
    gleam@dynamic@decode:field(
        <<"request"/utf8>>,
        decode_recorded_request_decoder(),
        fun(Request) ->
            gleam@dynamic@decode:field(
                <<"response"/utf8>>,
                decode_recorded_response_decoder(),
                fun(Response) ->
                    gleam@dynamic@decode:success({recording, Request, Response})
                end
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 380).
-spec decode_recording_file_decoder() -> gleam@dynamic@decode:decoder(recording_file()).
decode_recording_file_decoder() ->
    gleam@dynamic@decode:field(
        <<"version"/utf8>>,
        {decoder, fun gleam@dynamic@decode:decode_string/1},
        fun(Version) ->
            gleam@dynamic@decode:field(
                <<"entries"/utf8>>,
                gleam@dynamic@decode:list(decode_recording_decoder()),
                fun(Entries) ->
                    gleam@dynamic@decode:success(
                        {recording_file, Version, Entries}
                    )
                end
            )
        end
    ).

-file("src/dream_http_client/recording.gleam", 389).
-spec format_json_error(gleam@json:decode_error()) -> binary().
format_json_error(Error) ->
    case Error of
        unexpected_end_of_input ->
            <<"Unexpected end of JSON input"/utf8>>;

        {unexpected_byte, Msg} ->
            <<"Unexpected byte: "/utf8, Msg/binary>>;

        {unexpected_sequence, Msg@1} ->
            <<"Unexpected sequence: "/utf8, Msg@1/binary>>;

        {unable_to_decode, Errors} ->
            <<"Unable to decode: "/utf8, (gleam@string:inspect(Errors))/binary>>
    end.

-file("src/dream_http_client/recording.gleam", 369).
?DOC(
    " Decode a JSON string into a `RecordingFile`\n"
    "\n"
    " Parses a JSON string and decodes it into a `RecordingFile` value. This is\n"
    " the inverse of `encode_recording_file()` and is used by the storage module\n"
    " when loading recordings from disk.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `json_string`: The JSON string to decode (typically read from a file)\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(RecordingFile)`: Successfully decoded recording file\n"
    " - `Error(String)`: Human-readable error message describing why decoding failed\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " // Read JSON from an individual recording file\n"
    " let assert Ok(json_content) = simplifile.read(\"mocks/GET_api.example.com_users_a3f5b2.json\")\n"
    "\n"
    " // Decode to RecordingFile (each file contains one entry)\n"
    " case recording.decode_recording_file(json_content) {\n"
    "   Ok(file) -> {\n"
    "     io.println(\"Loaded \" <> int.to_string(list.length(file.entries)) <> \" recording(s)\")\n"
    "   }\n"
    "   Error(reason) -> io.println_error(\"Failed to decode: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Most callers should use `storage.load_recordings()` instead of calling this directly\n"
    " - This function is used internally by the storage module\n"
    " - Error messages include field paths to help identify decoding issues\n"
    " - Handles both blocking and streaming response formats\n"
).
-spec decode_recording_file(binary()) -> {ok, recording_file()} |
    {error, binary()}.
decode_recording_file(Json_string) ->
    gleam@result:'try'(
        begin
            _pipe = gleam@json:parse(
                Json_string,
                {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
            ),
            gleam@result:map_error(_pipe, fun format_json_error/1)
        end,
        fun(Json_value) ->
            _pipe@1 = gleam@dynamic@decode:run(
                Json_value,
                decode_recording_file_decoder()
            ),
            gleam@result:map_error(_pipe@1, fun format_decode_errors/1)
        end
    ).
