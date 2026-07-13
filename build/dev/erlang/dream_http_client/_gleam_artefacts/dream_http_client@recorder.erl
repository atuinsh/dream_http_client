-module(dream_http_client@recorder).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/recorder.gleam").
-export([start/2, add_recording/2, is_record_mode/1, find_recording/2, get_recordings/1, stop/1]).
-export_type([recorder/0, mode/0, recorder_state/0, recorder_message/0, recorder_response/0]).

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

-type mode() :: {record, binary()} | {playback, binary()} | passthrough.

-type recorder_state() :: {recorder_state,
        mode(),
        binary(),
        dream_http_client@matching:matching_config(),
        gleam@dict:dict(binary(), dream_http_client@recording:recording())}.

-type recorder_message() :: {add_recording,
        dream_http_client@recording:recording()} |
    {find_recording,
        dream_http_client@recording:recorded_request(),
        gleam@erlang@process:subject(recorder_response())} |
    {get_recordings, gleam@erlang@process:subject(recorder_response())} |
    {check_mode, gleam@erlang@process:subject(recorder_response())} |
    {stop, gleam@erlang@process:subject(recorder_response())}.

-type recorder_response() :: {found_recording,
        gleam@option:option(dream_http_client@recording:recording())} |
    {got_recordings, list(dream_http_client@recording:recording())} |
    {mode_is_record, boolean()} |
    {stopped, {ok, nil} | {error, binary()}}.

-file("src/dream_http_client/recorder.gleam", 193).
-spec convert_actor_error(gleam@otp@actor:start_error()) -> binary().
convert_actor_error(Error) ->
    <<"Failed to start recorder: "/utf8, (gleam@string:inspect(Error))/binary>>.

-file("src/dream_http_client/recorder.gleam", 187).
-spec wrap_recorder_subject(
    gleam@otp@actor:started(gleam@erlang@process:subject(recorder_message()))
) -> recorder().
wrap_recorder_subject(Started) ->
    {recorder, erlang:element(3, Started)}.

-file("src/dream_http_client/recorder.gleam", 215).
-spec handle_recorder_message(recorder_state(), recorder_message()) -> gleam@otp@actor:next(recorder_state(), recorder_message()).
handle_recorder_message(State, Message) ->
    case Message of
        {add_recording, Rec} ->
            Signature = dream_http_client@matching:build_signature(
                erlang:element(2, Rec),
                erlang:element(4, State)
            ),
            New_recordings = gleam@dict:insert(
                erlang:element(5, State),
                Signature,
                Rec
            ),
            New_state = {recorder_state,
                erlang:element(2, State),
                erlang:element(3, State),
                erlang:element(4, State),
                New_recordings},
            case erlang:element(2, State) of
                {record, Dir} ->
                    case dream_http_client@storage:save_recording_immediately(
                        Dir,
                        Rec,
                        erlang:element(4, State)
                    ) of
                        {ok, _} ->
                            gleam@otp@actor:continue(New_state);

                        {error, Save_error} ->
                            gleam_stdlib:println_error(
                                <<"Failed to save recording: "/utf8,
                                    Save_error/binary>>
                            ),
                            gleam@otp@actor:continue(New_state)
                    end;

                _ ->
                    gleam@otp@actor:continue(New_state)
            end;

        {find_recording, Request, Reply_to} ->
            Signature@1 = dream_http_client@matching:build_signature(
                Request,
                erlang:element(4, State)
            ),
            case gleam_stdlib:map_get(erlang:element(5, State), Signature@1) of
                {ok, Recording_value} ->
                    gleam@erlang@process:send(
                        Reply_to,
                        {found_recording, {some, Recording_value}}
                    ),
                    gleam@otp@actor:continue(State);

                {error, Not_found} ->
                    _ = Not_found,
                    gleam@erlang@process:send(Reply_to, {found_recording, none}),
                    gleam@otp@actor:continue(State)
            end;

        {get_recordings, Reply_to@1} ->
            All_recordings = maps:values(erlang:element(5, State)),
            gleam@erlang@process:send(
                Reply_to@1,
                {got_recordings, All_recordings}
            ),
            gleam@otp@actor:continue(State);

        {check_mode, Reply_to@2} ->
            Is_record = case erlang:element(2, State) of
                {record, _} ->
                    true;

                _ ->
                    false
            end,
            gleam@erlang@process:send(Reply_to@2, {mode_is_record, Is_record}),
            gleam@otp@actor:continue(State);

        {stop, Reply_to@3} ->
            gleam@erlang@process:send(Reply_to@3, {stopped, {ok, nil}}),
            gleam@otp@actor:stop()
    end.

-file("src/dream_http_client/recorder.gleam", 205).
-spec build_recordings_map(
    list(dream_http_client@recording:recording()),
    dream_http_client@matching:matching_config()
) -> gleam@dict:dict(binary(), dream_http_client@recording:recording()).
build_recordings_map(Recordings, Config) ->
    gleam@list:fold(
        Recordings,
        maps:new(),
        fun(Acc, Rec) ->
            Signature = dream_http_client@matching:build_signature(
                erlang:element(2, Rec),
                Config
            ),
            gleam@dict:insert(Acc, Signature, Rec)
        end
    ).

-file("src/dream_http_client/recorder.gleam", 197).
-spec get_directory(mode()) -> binary().
get_directory(Mode) ->
    case Mode of
        {record, Dir} ->
            Dir;

        {playback, Dir@1} ->
            Dir@1;

        passthrough ->
            <<""/utf8>>
    end.

-file("src/dream_http_client/recorder.gleam", 140).
?DOC(
    " Start a new recorder in the specified mode\n"
    "\n"
    " Creates an OTP actor process to manage recorder state. The recorder handles\n"
    " saving recordings to disk (Record mode), loading them for playback (Playback mode),\n"
    " or passing requests through unchanged (Passthrough mode).\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `mode`: The operating mode (Record, Playback, or Passthrough)\n"
    " - `matching_config`: Configuration for matching requests to recordings\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Recorder)`: Successfully started recorder\n"
    " - `Error(String)`: Error message if startup fails (e.g., cannot load recordings in Playback mode)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " // Record mode - captures and saves requests/responses\n"
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks/api\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
    "\n"
    " // Playback mode - returns recorded responses\n"
    " let assert Ok(playback_rec) = recorder.start(\n"
    "   mode: recorder.Playback(directory: \"mocks/api\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
    "\n"
    " // Passthrough mode - no recording or playback\n"
    " let assert Ok(passthrough_rec) = recorder.start(\n"
    "   mode: recorder.Passthrough,\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - In Playback mode, recordings are loaded from disk at startup\n"
    " - In Record mode, recordings are saved immediately when captured (no need to call `stop()`)\n"
    " - Multiple requests can share the same recorder handle safely\n"
    " - The recorder process runs until `stop()` is called or the VM shuts down\n"
).
-spec start(mode(), dream_http_client@matching:matching_config()) -> {ok,
        recorder()} |
    {error, binary()}.
start(Mode, Matching_config) ->
    Directory = get_directory(Mode),
    Initial_state = {recorder_state,
        Mode,
        Directory,
        Matching_config,
        maps:new()},
    case Mode of
        {playback, Dir} ->
            case dream_http_client@storage:load_recordings(Dir) of
                {ok, Loaded} ->
                    Recordings_map = build_recordings_map(
                        Loaded,
                        Matching_config
                    ),
                    State_with_recordings = {recorder_state,
                        Mode,
                        Dir,
                        Matching_config,
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
                    gleam@result:map_error(_pipe@3, fun convert_actor_error/1);

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
            _pipe@7 = gleam@result:map(_pipe@6, fun wrap_recorder_subject/1),
            gleam@result:map_error(_pipe@7, fun convert_actor_error/1)
    end.

-file("src/dream_http_client/recorder.gleam", 340).
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
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
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
    " - Duplicate recordings (same signature) overwrite previous ones\n"
).
-spec add_recording(recorder(), dream_http_client@recording:recording()) -> nil.
add_recording(Recorder, Rec) ->
    {recorder, Subject} = Recorder,
    gleam@erlang@process:send(Subject, {add_recording, Rec}).

-file("src/dream_http_client/recorder.gleam", 408).
-spec identity_recorder_response(recorder_response()) -> recorder_response().
identity_recorder_response(Response) ->
    Response.

-file("src/dream_http_client/recorder.gleam", 376).
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
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
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

-file("src/dream_http_client/recorder.gleam", 459).
?DOC(
    " Find a matching recording for a request\n"
    "\n"
    " Searches for a recording that matches the given request based on the recorder's\n"
    " matching configuration. This is used internally by the HTTP client during playback,\n"
    " but can be called directly to check if a recording exists.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `recorder`: The recorder to search in\n"
    " - `request`: The request to find a matching recording for\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Some(Recording)`: Matching recording found\n"
    " - `None`: No matching recording found (or not in Playback mode)\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Playback(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
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
    "   Some(recording) -> io.println(\"Found recording\")\n"
    "   None -> io.println(\"No recording found\")\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Only works in Playback mode (returns `None` in other modes)\n"
    " - Matching uses the recorder's `MatchingConfig` (method, URL, headers, body)\n"
    " - Returns `None` if recorder doesn't respond (safe default)\n"
    " - Timeout is 1 second - recorder should respond quickly\n"
).
-spec find_recording(recorder(), dream_http_client@recording:recorded_request()) -> gleam@option:option(dream_http_client@recording:recording()).
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
        {ok, {found_recording, Rec_opt}} ->
            Rec_opt;

        {ok, Unexpected_message} ->
            gleam_stdlib:println_error(
                <<"Recorder returned unexpected response to FindRecording: "/utf8,
                    (gleam@string:inspect(Unexpected_message))/binary>>
            ),
            none;

        {error, Timeout_error} ->
            gleam_stdlib:println_error(
                <<"Recorder did not respond to FindRecording within 1 second: "/utf8,
                    (gleam@string:inspect(Timeout_error))/binary>>
            ),
            none
    end.

-file("src/dream_http_client/recorder.gleam", 527).
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
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
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

-file("src/dream_http_client/recorder.gleam", 598).
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
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
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
