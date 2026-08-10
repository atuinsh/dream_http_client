-module(dream_http_client@recorder).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/recorder.gleam").
-export([new/0, directory/2, mode/2, key/2, request_transformer/2, response_transformer/2, start/1, add_recording/2, is_record_mode/1, transform_response/3, find_recording/2, get_recordings/1, stop/1]).
-export_type([recorder/0, recorder_builder/0, recorder_state/0, recorder_mode/0, recorder_message/0, recorder_response/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Recorder process and state management\n"
    "\n"
    " Manages HTTP request/response recordings using a process to store state.\n"
    " Supports recording, playback, and passthrough modes.\n"
).

-opaque recorder() :: {recorder,
        gleam@erlang@process:subject(recorder_message())}.

-type recorder_builder() :: {recorder_builder,
        binary(),
        gleam@option:option(binary()),
        fun((dream_http_client@recording:recorded_request()) -> binary()),
        fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request()),
        fun((dream_http_client@recording:recorded_request(), dream_http_client@recording:recorded_response()) -> dream_http_client@recording:recorded_response())}.

-type recorder_state() :: {recorder_state,
        recorder_mode(),
        binary(),
        fun((dream_http_client@recording:recorded_request()) -> binary()),
        fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request()),
        fun((dream_http_client@recording:recorded_request(), dream_http_client@recording:recorded_response()) -> dream_http_client@recording:recorded_response()),
        gleam@dict:dict(binary(), list(dream_http_client@recording:recording()))}.

-type recorder_mode() :: record | playback | passthrough.

-type recorder_message() :: {add_recording,
        dream_http_client@recording:recording()} |
    {find_recording,
        dream_http_client@recording:recorded_request(),
        gleam@erlang@process:subject(recorder_response())} |
    {get_recordings, gleam@erlang@process:subject(recorder_response())} |
    {check_mode, gleam@erlang@process:subject(recorder_response())} |
    {transform_response,
        dream_http_client@recording:recorded_request(),
        dream_http_client@recording:recorded_response(),
        gleam@erlang@process:subject(recorder_response())} |
    {stop, gleam@erlang@process:subject(recorder_response())}.

-type recorder_response() :: {found_recording,
        {ok, gleam@option:option(dream_http_client@recording:recording())} |
            {error, binary()}} |
    {got_recordings, list(dream_http_client@recording:recording())} |
    {mode_is_record, boolean()} |
    {transformed_response, dream_http_client@recording:recorded_response()} |
    {stopped, {ok, nil} | {error, binary()}}.

-file("src/dream_http_client/recorder.gleam", 220).
-spec identity_response_transformer(
    dream_http_client@recording:recorded_request(),
    dream_http_client@recording:recorded_response()
) -> dream_http_client@recording:recorded_response().
identity_response_transformer(_, Response) ->
    Response.

-file("src/dream_http_client/recorder.gleam", 214).
-spec identity_request_transformer(
    dream_http_client@recording:recorded_request()
) -> dream_http_client@recording:recorded_request().
identity_request_transformer(Request) ->
    Request.

-file("src/dream_http_client/recorder.gleam", 146).
?DOC(
    " Create a new recorder builder with safe defaults.\n"
    "\n"
    " Defaults:\n"
    " - `mode`: `\"passthrough\"`\n"
    " - `directory`: unset\n"
    " - `key`: `matching.request_key(method: True, url: True, headers: False, body: False)`\n"
    " - `request_transformer`: identity\n"
    " - `response_transformer`: identity\n"
).
-spec new() -> recorder_builder().
new() ->
    {recorder_builder,
        <<"passthrough"/utf8>>,
        none,
        dream_http_client@matching:request_key(true, true, false, false),
        fun identity_request_transformer/1,
        fun identity_response_transformer/2}.

-file("src/dream_http_client/recorder.gleam", 165).
?DOC(
    " Set the recording directory used by `\"record\"` and `\"playback\"` modes.\n"
    "\n"
    " The directory is **required** for `\"record\"` and `\"playback\"` (validated in\n"
    " `start()`), and ignored for `\"passthrough\"`.\n"
).
-spec directory(recorder_builder(), binary()) -> recorder_builder().
directory(Builder, Directory) ->
    {recorder_builder,
        erlang:element(2, Builder),
        {some, Directory},
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/dream_http_client/recorder.gleam", 177).
?DOC(
    " Set the recorder mode string.\n"
    "\n"
    " Valid modes (validated in `start()`):\n"
    " - `\"record\"`\n"
    " - `\"playback\"`\n"
    " - `\"passthrough\"`\n"
    "\n"
    " Mode strings are case-sensitive.\n"
).
-spec mode(recorder_builder(), binary()) -> recorder_builder().
mode(Builder, Mode) ->
    {recorder_builder,
        Mode,
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/dream_http_client/recorder.gleam", 188).
?DOC(
    " Set the match key function.\n"
    "\n"
    " The key function determines how requests are grouped for playback lookup.\n"
    " Keys should be stable and should generally **not** include secrets.\n"
    "\n"
    " If two different recordings produce the same key, playback lookup becomes\n"
    " ambiguous and `find_recording()` will return `Error(...)`.\n"
).
-spec key(
    recorder_builder(),
    fun((dream_http_client@recording:recorded_request()) -> binary())
) -> recorder_builder().
key(Builder, Key) ->
    {recorder_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        Key,
        erlang:element(5, Builder),
        erlang:element(6, Builder)}.

-file("src/dream_http_client/recorder.gleam", 196).
?DOC(
    " Set the request transformer.\n"
    "\n"
    " The transformer is applied before keying *and* before persistence, so it’s\n"
    " the right place to normalize requests and scrub secrets.\n"
).
-spec request_transformer(
    recorder_builder(),
    fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request())
) -> recorder_builder().
request_transformer(Builder, Request_transformer) ->
    {recorder_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        Request_transformer,
        erlang:element(6, Builder)}.

-file("src/dream_http_client/recorder.gleam", 207).
?DOC(
    " Set the response transformer.\n"
    "\n"
    " This transformer is applied **only in Record mode** and runs before\n"
    " persistence so recorded fixtures can be safely committed/shared.\n"
).
-spec response_transformer(
    recorder_builder(),
    fun((dream_http_client@recording:recorded_request(), dream_http_client@recording:recorded_response()) -> dream_http_client@recording:recorded_response())
) -> recorder_builder().
response_transformer(Builder, Response_transformer) ->
    {recorder_builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        Response_transformer}.

-file("src/dream_http_client/recorder.gleam", 345).
-spec convert_actor_error(gleam@otp@actor:start_error()) -> binary().
convert_actor_error(Error) ->
    <<"Failed to start recorder: "/utf8, (gleam@string:inspect(Error))/binary>>.

-file("src/dream_http_client/recorder.gleam", 339).
-spec wrap_recorder_subject(
    gleam@otp@actor:started(gleam@erlang@process:subject(recorder_message()))
) -> recorder().
wrap_recorder_subject(Started) ->
    {recorder, erlang:element(3, Started)}.

-file("src/dream_http_client/recorder.gleam", 594).
-spec flatten_recordings(list(list(dream_http_client@recording:recording()))) -> list(dream_http_client@recording:recording()).
flatten_recordings(Lists) ->
    _pipe = gleam@list:fold(
        Lists,
        [],
        fun(Acc, Recs) ->
            gleam@list:fold(Recs, Acc, fun(Acc2, R) -> [R | Acc2] end)
        end
    ),
    lists:reverse(_pipe).

-file("src/dream_http_client/recorder.gleam", 662).
-spec replace_json_string_value(binary(), binary(), binary()) -> binary().
replace_json_string_value(Body, Key, Replacement) ->
    Marker = <<<<"\""/utf8, Key/binary>>/binary, "\":\""/utf8>>,
    case gleam_stdlib:contains_string(Body, Marker) of
        false ->
            Body;

        true ->
            Parts = gleam@string:split(Body, Marker),
            case {gleam@list:first(Parts),
                begin
                    _pipe = gleam@list:drop(Parts, 1),
                    gleam@list:first(_pipe)
                end} of
                {{ok, Prefix}, {ok, Rest}} ->
                    case gleam@string:split(Rest, <<"\""/utf8>>) of
                        [_ | Tail] ->
                            <<<<<<<<Prefix/binary, Marker/binary>>/binary,
                                        Replacement/binary>>/binary,
                                    "\""/utf8>>/binary,
                                (gleam@string:join(Tail, <<"\""/utf8>>))/binary>>;

                        _ ->
                            Body
                    end;

                {_, _} ->
                    Body
            end
    end.

-file("src/dream_http_client/recorder.gleam", 655).
-spec normalize_auth_result_body(binary()) -> binary().
normalize_auth_result_body(Body) ->
    _pipe = Body,
    _pipe@1 = replace_json_string_value(
        _pipe,
        <<"AccessToken"/utf8>>,
        <<"<REDACTED_TOKEN>"/utf8>>
    ),
    _pipe@2 = replace_json_string_value(
        _pipe@1,
        <<"IdToken"/utf8>>,
        <<"<REDACTED_TOKEN>"/utf8>>
    ),
    replace_json_string_value(
        _pipe@2,
        <<"RefreshToken"/utf8>>,
        <<"<REDACTED_TOKEN>"/utf8>>
    ).

-file("src/dream_http_client/recorder.gleam", 648).
-spec response_kind(binary()) -> binary().
response_kind(Body) ->
    case gleam_stdlib:contains_string(Body, <<"AuthenticationResult"/utf8>>) of
        true ->
            <<"auth_result"/utf8>>;

        false ->
            <<"other"/utf8>>
    end.

-file("src/dream_http_client/recorder.gleam", 641).
-spec normalize_body_for_compare(binary()) -> binary().
normalize_body_for_compare(Body) ->
    case response_kind(Body) of
        <<"auth_result"/utf8>> ->
            normalize_auth_result_body(Body);

        _ ->
            Body
    end.

-file("src/dream_http_client/recorder.gleam", 625).
-spec responses_equal(
    dream_http_client@recording:recorded_response(),
    dream_http_client@recording:recorded_response()
) -> boolean().
responses_equal(Left, Right) ->
    case {Left, Right} of
        {{blocking_response, Status_a, Headers_a, Body_a},
            {blocking_response, Status_b, Headers_b, Body_b}} ->
            ((Status_a =:= Status_b) andalso (Headers_a =:= Headers_b)) andalso (normalize_body_for_compare(
                Body_a
            )
            =:= normalize_body_for_compare(Body_b));

        {_, _} ->
            false
    end.

-file("src/dream_http_client/recorder.gleam", 604).
-spec resolve_ambiguous_recordings(
    list(dream_http_client@recording:recording())
) -> {ok, gleam@option:option(dream_http_client@recording:recording())} |
    {error, nil}.
resolve_ambiguous_recordings(Records) ->
    case Records of
        [] ->
            {ok, none};

        [First | Rest] ->
            {recording, _, First_response} = First,
            All_equal = begin
                _pipe = Rest,
                gleam@list:all(
                    _pipe,
                    fun(Rec) ->
                        {recording, _, Response} = Rec,
                        responses_equal(First_response, Response)
                    end
                )
            end,
            case All_equal of
                true ->
                    {ok, {some, First}};

                false ->
                    {ok, none}
            end
    end.

-file("src/dream_http_client/recorder.gleam", 373).
-spec transform_recording_for_persistence(
    dream_http_client@recording:recording(),
    fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request()),
    fun((dream_http_client@recording:recorded_request(), dream_http_client@recording:recorded_response()) -> dream_http_client@recording:recorded_response())
) -> dream_http_client@recording:recording().
transform_recording_for_persistence(
    Rec,
    Request_transformer,
    Response_transformer
) ->
    {recording, Request, Response} = Rec,
    Request2 = Request_transformer(Request),
    Response2 = Response_transformer(Request2, Response),
    {recording, Request2, Response2}.

-file("src/dream_http_client/recorder.gleam", 415).
-spec handle_recorder_message(recorder_state(), recorder_message()) -> gleam@otp@actor:next(recorder_state(), recorder_message()).
handle_recorder_message(State, Message) ->
    case Message of
        {add_recording, Rec} ->
            case erlang:element(2, State) of
                record ->
                    Transformed = transform_recording_for_persistence(
                        Rec,
                        erlang:element(5, State),
                        erlang:element(6, State)
                    ),
                    Key = (erlang:element(4, State))(
                        erlang:element(2, Transformed)
                    ),
                    Should_save = case gleam_stdlib:map_get(
                        erlang:element(7, State),
                        Key
                    ) of
                        {error, _} ->
                            true;

                        {ok, Existing} ->
                            Duplicate = begin
                                _pipe = Existing,
                                gleam@list:any(
                                    _pipe,
                                    fun(Rec@1) ->
                                        {recording, _, Response} = Rec@1,
                                        responses_equal(
                                            Response,
                                            erlang:element(3, Transformed)
                                        )
                                    end
                                )
                            end,
                            case Duplicate of
                                true ->
                                    false;

                                false ->
                                    true
                            end
                    end,
                    New_recordings = case Should_save of
                        true ->
                            case gleam_stdlib:map_get(
                                erlang:element(7, State),
                                Key
                            ) of
                                {ok, Existing@1} ->
                                    gleam@dict:insert(
                                        erlang:element(7, State),
                                        Key,
                                        [Transformed | Existing@1]
                                    );

                                {error, _} ->
                                    gleam@dict:insert(
                                        erlang:element(7, State),
                                        Key,
                                        [Transformed]
                                    )
                            end;

                        false ->
                            erlang:element(7, State)
                    end,
                    New_state = {recorder_state,
                        erlang:element(2, State),
                        erlang:element(3, State),
                        erlang:element(4, State),
                        erlang:element(5, State),
                        erlang:element(6, State),
                        New_recordings},
                    case Should_save of
                        false ->
                            gleam@otp@actor:continue(New_state);

                        true ->
                            case dream_http_client@storage:save_recording_immediately(
                                erlang:element(3, State),
                                Transformed,
                                Key
                            ) of
                                {ok, _} ->
                                    gleam@otp@actor:continue(New_state);

                                {error, Save_error} ->
                                    gleam_stdlib:println_error(
                                        <<"Failed to save recording: "/utf8,
                                            Save_error/binary>>
                                    ),
                                    gleam@otp@actor:continue(New_state)
                            end
                    end;

                _ ->
                    gleam@otp@actor:continue(State)
            end;

        {find_recording, Request, Reply_to} ->
            case erlang:element(2, State) of
                playback ->
                    Transformed_request = (erlang:element(5, State))(Request),
                    Key@1 = (erlang:element(4, State))(Transformed_request),
                    case gleam_stdlib:map_get(erlang:element(7, State), Key@1) of
                        {error, _} ->
                            gleam@erlang@process:send(
                                Reply_to,
                                {found_recording, {ok, none}}
                            ),
                            gleam@otp@actor:continue(State);

                        {ok, []} ->
                            gleam@erlang@process:send(
                                Reply_to,
                                {found_recording, {ok, none}}
                            ),
                            gleam@otp@actor:continue(State);

                        {ok, [Rec@2]} ->
                            gleam@erlang@process:send(
                                Reply_to,
                                {found_recording, {ok, {some, Rec@2}}}
                            ),
                            gleam@otp@actor:continue(State);

                        {ok, Records} ->
                            Count = erlang:length(Records),
                            Resolved = resolve_ambiguous_recordings(Records),
                            case Resolved of
                                {ok, {some, Rec@3}} ->
                                    gleam@erlang@process:send(
                                        Reply_to,
                                        {found_recording, {ok, {some, Rec@3}}}
                                    ),
                                    gleam@otp@actor:continue(State);

                                _ ->
                                    gleam@erlang@process:send(
                                        Reply_to,
                                        {found_recording,
                                            {error,
                                                <<<<<<<<"Ambiguous recording match for key: "/utf8,
                                                                Key@1/binary>>/binary,
                                                            " ("/utf8>>/binary,
                                                        (erlang:integer_to_binary(
                                                            Count
                                                        ))/binary>>/binary,
                                                    " recordings)"/utf8>>}}
                                    ),
                                    gleam@otp@actor:continue(State)
                            end
                    end;

                _ ->
                    gleam@erlang@process:send(
                        Reply_to,
                        {found_recording, {ok, none}}
                    ),
                    gleam@otp@actor:continue(State)
            end;

        {get_recordings, Reply_to@1} ->
            All_recordings = flatten_recordings(
                maps:values(erlang:element(7, State))
            ),
            gleam@erlang@process:send(
                Reply_to@1,
                {got_recordings, All_recordings}
            ),
            gleam@otp@actor:continue(State);

        {check_mode, Reply_to@2} ->
            Is_record = case erlang:element(2, State) of
                record ->
                    true;

                _ ->
                    false
            end,
            gleam@erlang@process:send(Reply_to@2, {mode_is_record, Is_record}),
            gleam@otp@actor:continue(State);

        {transform_response, Request@1, Response@1, Reply_to@3} ->
            Transformed_request@1 = (erlang:element(5, State))(Request@1),
            Transformed@1 = (erlang:element(6, State))(
                Transformed_request@1,
                Response@1
            ),
            gleam@erlang@process:send(
                Reply_to@3,
                {transformed_response, Transformed@1}
            ),
            gleam@otp@actor:continue(State);

        {stop, Reply_to@4} ->
            gleam@erlang@process:send(Reply_to@4, {stopped, {ok, nil}}),
            gleam@otp@actor:stop()
    end.

-file("src/dream_http_client/recorder.gleam", 364).
-spec transform_recording_request(
    dream_http_client@recording:recording(),
    fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request())
) -> dream_http_client@recording:recording().
transform_recording_request(Rec, Request_transformer) ->
    {recording, Request, Response} = Rec,
    Request2 = Request_transformer(Request),
    {recording, Request2, Response}.

-file("src/dream_http_client/recorder.gleam", 349).
-spec build_recordings_map(
    list(dream_http_client@recording:recording()),
    fun((dream_http_client@recording:recorded_request()) -> binary()),
    fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request())
) -> gleam@dict:dict(binary(), list(dream_http_client@recording:recording())).
build_recordings_map(Recordings, Key, Request_transformer) ->
    gleam@list:fold(
        Recordings,
        maps:new(),
        fun(Acc, Rec) ->
            Transformed = transform_recording_request(Rec, Request_transformer),
            Signature = Key(erlang:element(2, Transformed)),
            case gleam_stdlib:map_get(Acc, Signature) of
                {ok, Existing} ->
                    gleam@dict:insert(Acc, Signature, [Transformed | Existing]);

                {error, _} ->
                    gleam@dict:insert(Acc, Signature, [Transformed])
            end
        end
    ).

-file("src/dream_http_client/recorder.gleam", 398).
-spec resolve_directory(
    {ok, recorder_mode()} | {error, binary()},
    gleam@option:option(binary())
) -> {ok, binary()} | {error, binary()}.
resolve_directory(Mode, Directory) ->
    case Mode of
        {error, E} ->
            {error, E};

        {ok, record} ->
            case Directory of
                {some, Dir} ->
                    {ok, Dir};

                none ->
                    {error,
                        <<"Recorder directory is required for record/playback"/utf8>>}
            end;

        {ok, playback} ->
            case Directory of
                {some, Dir} ->
                    {ok, Dir};

                none ->
                    {error,
                        <<"Recorder directory is required for record/playback"/utf8>>}
            end;

        {ok, passthrough} ->
            {ok, <<""/utf8>>}
    end.

-file("src/dream_http_client/recorder.gleam", 384).
-spec parse_mode(binary()) -> {ok, recorder_mode()} | {error, binary()}.
parse_mode(Mode) ->
    case Mode of
        <<"record"/utf8>> ->
            {ok, record};

        <<"playback"/utf8>> ->
            {ok, playback};

        <<"passthrough"/utf8>> ->
            {ok, passthrough};

        _ ->
            {error,
                <<<<"Unknown recorder mode: "/utf8, Mode/binary>>/binary,
                    ". Expected one of: record, playback, passthrough"/utf8>>}
    end.

-file("src/dream_http_client/recorder.gleam", 278).
?DOC(
    " Start a new recorder from a builder.\n"
    "\n"
    " Creates an OTP actor process to manage recorder state. The recorder handles\n"
    " saving recordings to disk (Record mode), loading them for playback (Playback mode),\n"
    " or passing requests through unchanged (Passthrough mode).\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `builder`: Recorder configuration builder\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Recorder)`: Successfully started recorder\n"
    " - `Error(String)`: Error message if startup fails (e.g., cannot load recordings in Playback mode)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks/api\")\n"
    "   |> mode(\"playback\")\n"
    "   |> start()\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - In Playback mode, recordings are loaded from disk at startup\n"
    " - In Record mode, recordings are saved immediately when captured (no need to call `stop()`)\n"
    " - Multiple requests can share the same recorder handle safely\n"
    " - The recorder process runs until `stop()` is called or the VM shuts down\n"
).
-spec start(recorder_builder()) -> {ok, recorder()} | {error, binary()}.
start(Builder) ->
    Mode = parse_mode(erlang:element(2, Builder)),
    Directory = resolve_directory(Mode, erlang:element(3, Builder)),
    case {Mode, Directory} of
        {{error, E}, _} ->
            {error, E};

        {_, {error, E@1}} ->
            {error, E@1};

        {{ok, Parsed_mode}, {ok, Dir}} ->
            Initial_state = {recorder_state,
                Parsed_mode,
                Dir,
                erlang:element(4, Builder),
                erlang:element(5, Builder),
                erlang:element(6, Builder),
                maps:new()},
            case Parsed_mode of
                playback ->
                    case dream_http_client@storage:load_recordings(Dir) of
                        {ok, Loaded} ->
                            Recordings_map = build_recordings_map(
                                Loaded,
                                erlang:element(4, Builder),
                                erlang:element(5, Builder)
                            ),
                            State_with_recordings = {recorder_state,
                                Parsed_mode,
                                Dir,
                                erlang:element(4, Builder),
                                erlang:element(5, Builder),
                                erlang:element(6, Builder),
                                Recordings_map},
                            _pipe = gleam@otp@actor:new(State_with_recordings),
                            _pipe@1 = gleam@otp@actor:on_message(
                                _pipe,
                                fun handle_recorder_message/2
                            ),
                            _pipe@2 = gleam@otp@actor:start(_pipe@1),
                            _pipe@3 = gleam@result:map(
                                _pipe@2,
                                fun wrap_recorder_subject/1
                            ),
                            gleam@result:map_error(
                                _pipe@3,
                                fun convert_actor_error/1
                            );

                        {error, Load_error} ->
                            {error,
                                <<"Failed to load recordings in playback mode: "/utf8,
                                    Load_error/binary>>}
                    end;

                _ ->
                    _pipe@4 = gleam@otp@actor:new(Initial_state),
                    _pipe@5 = gleam@otp@actor:on_message(
                        _pipe@4,
                        fun handle_recorder_message/2
                    ),
                    _pipe@6 = gleam@otp@actor:start(_pipe@5),
                    _pipe@7 = gleam@result:map(
                        _pipe@6,
                        fun wrap_recorder_subject/1
                    ),
                    gleam@result:map_error(_pipe@7, fun convert_actor_error/1)
            end
    end.

-file("src/dream_http_client/recorder.gleam", 729).
?DOC(
    " Add a recording to the recorder\n"
    "\n"
    " Manually adds a recording to the recorder's in-memory state and saves it to disk\n"
    " immediately if in Record mode. This function is typically called automatically\n"
    " by the HTTP client when a request completes, but can be used directly for testing\n"
    " or manual recording creation.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to add the recording to\n"
    " - `rec`: The recording (request/response pair) to add\n"
    "\n"
    " ## Behavior by Mode\n"
    "\n"
    " - **Record mode**: Adds to in-memory state and saves to disk immediately\n"
    " - **Playback mode**: No-op (recordings loaded from disk at startup)\n"
    " - **Passthrough mode**: No-op (no recording functionality)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " // Manually add a recording\n"
    " let manual_recording = recording.Recording(\n"
    "   request: create_test_request(),\n"
    "   response: create_test_response(),\n"
    " )\n"
    " recorder.add_recording(rec, manual_recording)\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Recordings are saved immediately in Record mode (no need to call `stop()`)\n"
    " - If save fails, error is logged but recording remains in memory\n"
    " - If multiple recordings share the same match key, they are all stored\n"
    "   (playback lookup will error if that makes the key ambiguous)\n"
).
-spec add_recording(recorder(), dream_http_client@recording:recording()) -> nil.
add_recording(Recorder, Rec) ->
    {recorder, Subject} = Recorder,
    gleam@erlang@process:send(Subject, {add_recording, Rec}).

-file("src/dream_http_client/recorder.gleam", 833).
-spec identity_recorder_response(recorder_response()) -> recorder_response().
identity_recorder_response(Response) ->
    Response.

-file("src/dream_http_client/recorder.gleam", 768).
?DOC(
    " Check if recorder is in Record mode\n"
    "\n"
    " Determines whether the recorder is configured to capture and save real HTTP\n"
    " requests/responses. Useful for conditional logic that only applies during recording.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to check\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `True`: Recorder is in Record mode\n"
    " - `False`: Recorder is in Playback or Passthrough mode\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " if recorder.is_record_mode(rec) {\n"
    "   io.println(\"Recording mode active\")\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Returns `False` if the recorder process doesn't respond (safe default)\n"
    " - Timeout is 1 second - recorder should respond quickly\n"
).
-spec is_record_mode(recorder()) -> boolean().
is_record_mode(Recorder) ->
    {recorder, Subject} = Recorder,
    Reply_subject = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subject, {check_mode, Reply_subject}),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        gleam@erlang@process:select_map(
            _pipe,
            Reply_subject,
            fun identity_recorder_response/1
        )
    end,
    case gleam_erlang_ffi:select(Selector, 1000) of
        {ok, {mode_is_record, Is_record}} ->
            Is_record;

        {ok, Unexpected_message} ->
            gleam_stdlib:println_error(
                <<"Recorder returned unexpected response to CheckMode: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>
            ),
            false;

        {error, Timeout_error} ->
            gleam_stdlib:println_error(
                <<"Recorder did not respond to CheckMode within 1 second: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>
            ),
            false
    end.

-file("src/dream_http_client/recorder.gleam", 801).
?DOC(" Apply the recorder's response transformer to a response.\n").
-spec transform_response(
    recorder(),
    dream_http_client@recording:recorded_request(),
    dream_http_client@recording:recorded_response()
) -> dream_http_client@recording:recorded_response().
transform_response(Recorder, Request, Response) ->
    {recorder, Subject} = Recorder,
    Reply_subject = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(
        Subject,
        {transform_response, Request, Response, Reply_subject}
    ),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        gleam@erlang@process:select_map(
            _pipe,
            Reply_subject,
            fun identity_recorder_response/1
        )
    end,
    case gleam_erlang_ffi:select(Selector, 1000) of
        {ok, {transformed_response, Transformed}} ->
            Transformed;

        {ok, Unexpected_message} ->
            gleam_stdlib:println_error(
                <<"Recorder returned unexpected response to TransformResponse: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>
            ),
            Response;

        {error, Timeout_error} ->
            gleam_stdlib:println_error(
                <<"Recorder did not respond to TransformResponse within 1 second: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>
            ),
            Response
    end.

-file("src/dream_http_client/recorder.gleam", 891).
?DOC(
    " Find a matching recording for a request\n"
    "\n"
    " Searches for a recording that matches the given request based on the recorder's\n"
    " configured match key and request transformer. This is used internally by the HTTP client\n"
    " during playback, but can be called directly to check if a recording exists.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to search in\n"
    " - `request`: The request to find a matching recording for\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Some(Recording))`: Matching recording found (unambiguous)\n"
    " - `Ok(None)`: No matching recording found (or not in Playback mode)\n"
    " - `Error(String)`: Playback lookup was ambiguous (multiple recordings share the same key)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    " import gleam/http\n"
    " import gleam/option\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"playback\")\n"
    "   |> start()\n"
    "\n"
    " let request = recording.RecordedRequest(\n"
    "   method: http.Get,\n"
    "   scheme: http.Https,\n"
    "   host: \"api.example.com\",\n"
    "   port: option.None,\n"
    "   path: \"/users\",\n"
    "   query: option.None,\n"
    "   headers: [],\n"
    "   body: \"\",\n"
    " )\n"
    "\n"
    " case recorder.find_recording(rec, request) {\n"
    "   Ok(option.Some(_recording)) -> io.println(\"Found recording\")\n"
    "   Ok(option.None) -> io.println(\"No recording found\")\n"
    "   Error(reason) -> io.println_error(\"Ambiguous match: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Only works in Playback mode (returns `None` in other modes)\n"
    " - Matching uses the recorder's configured key + request transformer\n"
    " - Returns `None` if recorder doesn't respond (safe default)\n"
    " - Timeout is 1 second - recorder should respond quickly\n"
).
-spec find_recording(recorder(), dream_http_client@recording:recorded_request()) -> {ok,
        gleam@option:option(dream_http_client@recording:recording())} |
    {error, binary()}.
find_recording(Recorder, Request) ->
    {recorder, Subject} = Recorder,
    Reply_subject = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subject, {find_recording, Request, Reply_subject}),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        gleam@erlang@process:select_map(
            _pipe,
            Reply_subject,
            fun identity_recorder_response/1
        )
    end,
    case gleam_erlang_ffi:select(Selector, 1000) of
        {ok, {found_recording, Result}} ->
            Result;

        {ok, Unexpected_message} ->
            gleam_stdlib:println_error(
                <<"Recorder returned unexpected response to FindRecording: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>
            ),
            {ok, none};

        {error, Timeout_error} ->
            gleam_stdlib:println_error(
                <<"Recorder did not respond to FindRecording within 1 second: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>
            ),
            {ok, none}
    end.

-file("src/dream_http_client/recorder.gleam", 962).
?DOC(
    " Get all recordings from the recorder\n"
    "\n"
    " Retrieves all recordings currently stored in the recorder's in-memory state.\n"
    " In Playback mode, this returns all recordings loaded from disk at startup.\n"
    " In Record mode, this returns all recordings captured so far (including unsaved ones).\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to get recordings from\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `List(Recording)`: All recordings in the recorder (empty list if none or error)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " // Make some requests...\n"
    "\n"
    " let recordings = recorder.get_recordings(rec)\n"
    " io.println(\"Captured \" <> int.to_string(list.length(recordings)) <> \" recordings\")\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Returns empty list if recorder doesn't respond (safe default)\n"
    " - In Record mode, includes recordings that may not yet be saved to disk\n"
    " - Timeout is 1 second - recorder should respond quickly\n"
).
-spec get_recordings(recorder()) -> list(dream_http_client@recording:recording()).
get_recordings(Recorder) ->
    {recorder, Subject} = Recorder,
    Reply_subject = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subject, {get_recordings, Reply_subject}),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        gleam@erlang@process:select_map(
            _pipe,
            Reply_subject,
            fun identity_recorder_response/1
        )
    end,
    case gleam_erlang_ffi:select(Selector, 1000) of
        {ok, {got_recordings, Recordings}} ->
            Recordings;

        {ok, Unexpected_message} ->
            gleam_stdlib:println_error(
                <<"Recorder returned unexpected response to GetRecordings: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>
            ),
            [];

        {error, Timeout_error} ->
            gleam_stdlib:println_error(
                <<"Recorder did not respond to GetRecordings within 1 second: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>
            ),
            []
    end.

-file("src/dream_http_client/recorder.gleam", 1036).
?DOC(
    " Stop the recorder and cleanup\n"
    "\n"
    " Stops the recorder's OTP actor process and releases resources. In Record mode,\n"
    " recordings are already saved to disk immediately when captured, so this function\n"
    " only performs cleanup. Calling `stop()` is optional but recommended for proper\n"
    " resource management.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to stop\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Nil)`: Successfully stopped the recorder\n"
    " - `Error(String)`: Error message if the recorder doesn't respond within 5 seconds\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " // Use recorder...\n"
    "\n"
    " // Cleanup (optional - recordings already saved)\n"
    " case recorder.stop(rec) {\n"
    "   Ok(_) -> io.println(\"Recorder stopped\")\n"
    "   Error(reason) -> io.println_error(\"Failed to stop: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Recordings are saved immediately when captured - `stop()` is not required for persistence\n"
    " - This function is optional but recommended for proper resource cleanup\n"
    " - Timeout is 5 seconds - recorder should stop quickly\n"
    " - After calling `stop()`, the recorder handle is no longer valid\n"
).
-spec stop(recorder()) -> {ok, nil} | {error, binary()}.
stop(Recorder) ->
    {recorder, Subject} = Recorder,
    Reply_subject = gleam@erlang@process:new_subject(),
    gleam@erlang@process:send(Subject, {stop, Reply_subject}),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        gleam@erlang@process:select_map(
            _pipe,
            Reply_subject,
            fun identity_recorder_response/1
        )
    end,
    case gleam_erlang_ffi:select(Selector, 5000) of
        {ok, {stopped, Result}} ->
            Result;

        {ok, Unexpected_message} ->
            {error,
                <<"Unexpected response from recorder: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>};

        {error, Timeout_error} ->
            {error,
                <<"Recorder did not respond within 5 seconds: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>}
    end.
