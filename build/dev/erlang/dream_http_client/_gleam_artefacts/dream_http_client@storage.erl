-module(dream_http_client@storage).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/storage.gleam").
-export([load_recordings/1, save_recording_immediately/3, save_recordings/3]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " File I/O for recordings\n"
    "\n"
    " Handles loading and saving recording files to/from the filesystem.\n"
).

-file("src/dream_http_client/storage.gleam", 48).
?DOC(
    " Load recordings from a directory\n"
    "\n"
    " Scans the directory for all `.json` files and loads them as individual recordings.\n"
    " This function is used internally by the recorder when starting in Playback mode, but\n"
    " can also be called directly to inspect or manipulate recordings.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `directory`: The directory containing individual recording files\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(List(Recording))`: Successfully loaded recordings (empty list if directory doesn't exist)\n"
    " - `Error(String)`: Error message if directory exists but files cannot be read or decoded\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " // Load recordings for inspection\n"
    " case storage.load_recordings(\"mocks/api\") {\n"
    "   Ok(recordings) -> {\n"
    "     io.println(\"Loaded \" <> int.to_string(list.length(recordings)) <> \" recordings\")\n"
    "   }\n"
    "   Error(reason) -> io.println_error(\"Failed to load: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Returns an empty list (not an error) if the directory doesn't exist\n"
    " - This is the expected behavior for Playback mode when no recordings have been created yet\n"
    " - Each file contains a single recording in the versioned JSON format\n"
).
-spec load_recordings(binary()) -> {ok,
        list(dream_http_client@recording:recording())} |
    {error, binary()}.
load_recordings(Directory) ->
    case simplifile_erl:read_directory(Directory) of
        {ok, Files} ->
            Json_files = gleam@list:filter(
                Files,
                fun(File) ->
                    gleam_stdlib:string_ends_with(File, <<".json"/utf8>>)
                end
            ),
            _pipe = Json_files,
            gleam@list:try_map(
                _pipe,
                fun(Filename) ->
                    File_path = <<<<Directory/binary, "/"/utf8>>/binary,
                        Filename/binary>>,
                    case simplifile:read(File_path) of
                        {ok, Content} ->
                            case dream_http_client@recording:decode_recording_file(
                                Content
                            ) of
                                {ok, File@1} ->
                                    case gleam@list:first(
                                        erlang:element(3, File@1)
                                    ) of
                                        {ok, Entry} ->
                                            {ok, Entry};

                                        {error, _} ->
                                            {error,
                                                <<"Recording file contains no entries: "/utf8,
                                                    File_path/binary>>}
                                    end;

                                {error, Reason} ->
                                    {error,
                                        <<<<<<"Failed to decode "/utf8,
                                                    File_path/binary>>/binary,
                                                ": "/utf8>>/binary,
                                            Reason/binary>>}
                            end;

                        {error, Read_error} ->
                            {error,
                                <<<<<<"Failed to read "/utf8, File_path/binary>>/binary,
                                        ": "/utf8>>/binary,
                                    (gleam@string:inspect(Read_error))/binary>>}
                    end
                end
            );

        {error, enoent} ->
            {ok, []};

        {error, Read_error@1} ->
            {error,
                <<<<<<"Failed to read directory "/utf8, Directory/binary>>/binary,
                        ": "/utf8>>/binary,
                    (gleam@string:inspect(Read_error@1))/binary>>}
    end.

-file("src/dream_http_client/storage.gleam", 408).
?DOC(" Generate a hash from a string\n").
-spec generate_hash(binary()) -> binary().
generate_hash(Input) ->
    Bits = gleam_stdlib:identity(Input),
    Hash_bits = gleam@crypto:hash(sha256, Bits),
    _pipe = gleam_stdlib:base16_encode(Hash_bits),
    string:lowercase(_pipe).

-file("src/dream_http_client/storage.gleam", 400).
?DOC(" Truncate a string to a maximum length\n").
-spec truncate_string(binary(), integer()) -> binary().
truncate_string(Input, Max_length) ->
    case string:length(Input) > Max_length of
        true ->
            gleam@string:slice(Input, 0, Max_length);

        false ->
            Input
    end.

-file("src/dream_http_client/storage.gleam", 334).
?DOC(
    " Sanitize a string to be safe for use in filenames\n"
    "\n"
    " Replaces characters that are problematic in filenames with underscores.\n"
    " Allows alphanumeric, hyphens, periods, and underscores.\n"
).
-spec sanitize_for_filename(binary()) -> binary().
sanitize_for_filename(Input) ->
    _pipe = Input,
    _pipe@1 = gleam@string:to_graphemes(_pipe),
    _pipe@2 = gleam@list:map(_pipe@1, fun(Char) -> case Char of
                <<"a"/utf8>> ->
                    Char;

                <<"b"/utf8>> ->
                    Char;

                <<"c"/utf8>> ->
                    Char;

                <<"d"/utf8>> ->
                    Char;

                <<"e"/utf8>> ->
                    Char;

                <<"f"/utf8>> ->
                    Char;

                <<"g"/utf8>> ->
                    Char;

                <<"h"/utf8>> ->
                    Char;

                <<"i"/utf8>> ->
                    Char;

                <<"j"/utf8>> ->
                    Char;

                <<"k"/utf8>> ->
                    Char;

                <<"l"/utf8>> ->
                    Char;

                <<"m"/utf8>> ->
                    Char;

                <<"n"/utf8>> ->
                    Char;

                <<"o"/utf8>> ->
                    Char;

                <<"p"/utf8>> ->
                    Char;

                <<"q"/utf8>> ->
                    Char;

                <<"r"/utf8>> ->
                    Char;

                <<"s"/utf8>> ->
                    Char;

                <<"t"/utf8>> ->
                    Char;

                <<"u"/utf8>> ->
                    Char;

                <<"v"/utf8>> ->
                    Char;

                <<"w"/utf8>> ->
                    Char;

                <<"x"/utf8>> ->
                    Char;

                <<"y"/utf8>> ->
                    Char;

                <<"z"/utf8>> ->
                    Char;

                <<"A"/utf8>> ->
                    Char;

                <<"B"/utf8>> ->
                    Char;

                <<"C"/utf8>> ->
                    Char;

                <<"D"/utf8>> ->
                    Char;

                <<"E"/utf8>> ->
                    Char;

                <<"F"/utf8>> ->
                    Char;

                <<"G"/utf8>> ->
                    Char;

                <<"H"/utf8>> ->
                    Char;

                <<"I"/utf8>> ->
                    Char;

                <<"J"/utf8>> ->
                    Char;

                <<"K"/utf8>> ->
                    Char;

                <<"L"/utf8>> ->
                    Char;

                <<"M"/utf8>> ->
                    Char;

                <<"N"/utf8>> ->
                    Char;

                <<"O"/utf8>> ->
                    Char;

                <<"P"/utf8>> ->
                    Char;

                <<"Q"/utf8>> ->
                    Char;

                <<"R"/utf8>> ->
                    Char;

                <<"S"/utf8>> ->
                    Char;

                <<"T"/utf8>> ->
                    Char;

                <<"U"/utf8>> ->
                    Char;

                <<"V"/utf8>> ->
                    Char;

                <<"W"/utf8>> ->
                    Char;

                <<"X"/utf8>> ->
                    Char;

                <<"Y"/utf8>> ->
                    Char;

                <<"Z"/utf8>> ->
                    Char;

                <<"0"/utf8>> ->
                    Char;

                <<"1"/utf8>> ->
                    Char;

                <<"2"/utf8>> ->
                    Char;

                <<"3"/utf8>> ->
                    Char;

                <<"4"/utf8>> ->
                    Char;

                <<"5"/utf8>> ->
                    Char;

                <<"6"/utf8>> ->
                    Char;

                <<"7"/utf8>> ->
                    Char;

                <<"8"/utf8>> ->
                    Char;

                <<"9"/utf8>> ->
                    Char;

                <<"-"/utf8>> ->
                    Char;

                <<"."/utf8>> ->
                    Char;

                <<"_"/utf8>> ->
                    Char;

                _ ->
                    <<"_"/utf8>>
            end end),
    gleam@string:join(_pipe@2, <<""/utf8>>).

-file("src/dream_http_client/storage.gleam", 315).
-spec method_to_string(gleam@http:method()) -> binary().
method_to_string(Method) ->
    case Method of
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
    end.

-file("src/dream_http_client/storage.gleam", 282).
?DOC(
    " Build a unique filename for a recording based on the request\n"
    "\n"
    " Creates a filename with the format:\n"
    "\n"
    " `{method}_{host}_{path}_{key_hash}_{content_hash}.json`\n"
    "\n"
    " - `key_hash` groups recordings by match key\n"
    " - `content_hash` prevents overwrites when multiple recordings share the same key\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request`: The request to generate a filename for\n"
    " - `key`: The match key string used for grouping\n"
    " - `content`: The JSON file content (used for the content hash)\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A safe filename string ending in `.json`\n"
    "\n"
    " ## Examples\n"
    "\n"
    " - `GET_api.example.com_users_a3f5b2.json`\n"
    " - `POST_api.example.com_users_c7d8e9.json`\n"
    " - `GET_localhost_text_f1a2b3.json`\n"
).
-spec build_filename(
    dream_http_client@recording:recorded_request(),
    binary(),
    binary()
) -> binary().
build_filename(Request, Key, Content) ->
    Method_part = sanitize_for_filename(
        method_to_string(erlang:element(2, Request))
    ),
    Host_part = sanitize_for_filename(erlang:element(4, Request)),
    Path_part = begin
        _pipe = erlang:element(6, Request),
        _pipe@1 = gleam@string:replace(_pipe, <<"/"/utf8>>, <<"_"/utf8>>),
        _pipe@2 = sanitize_for_filename(_pipe@1),
        truncate_string(_pipe@2, 50)
    end,
    Key_hash_short = gleam@string:slice(generate_hash(Key), 0, 6),
    Content_hash_short = gleam@string:slice(generate_hash(Content), 0, 6),
    <<<<<<<<<<<<<<<<<<Method_part/binary, "_"/utf8>>/binary, Host_part/binary>>/binary,
                                "_"/utf8>>/binary,
                            Path_part/binary>>/binary,
                        "_"/utf8>>/binary,
                    Key_hash_short/binary>>/binary,
                "_"/utf8>>/binary,
            Content_hash_short/binary>>/binary,
        ".json"/utf8>>.

-file("src/dream_http_client/storage.gleam", 141).
?DOC(
    " Save a single recording immediately to its own file\n"
    "\n"
    " Writes a single recording to an individual file.\n"
    "\n"
    " The filename includes human-readable parts (method/host/path) plus a short\n"
    " hash of the **match key** and a short hash of the **file content**. This\n"
    " avoids overwriting when multiple recordings share the same key.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `directory`: The directory where the recording file will be written\n"
    " - `rec`: The recording to save\n"
    " - `key`: The match key string for this request (should match the recorder's key function)\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Nil)`: Successfully saved the recording\n"
    " - `Error(String)`: Error message if directory creation or file write fails\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let rec = recording.Recording(request: req, response: resp)\n"
    "\n"
    " // Compute a key string using the same key policy you use for playback:\n"
    " let key_fn = matching.request_key(method: True, url: True, headers: False, body: False)\n"
    " let key = key_fn(rec.request)\n"
    "\n"
    " case storage.save_recording_immediately(\"mocks/api\", rec, key) {\n"
    "   Ok(_) -> io.println(\"Saved recording\")\n"
    "   Error(reason) -> io.println_error(\"Failed to save: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Each recording is saved to its own file for O(1) write performance\n"
    " - Filenames include human-readable parts (method, host, path) plus a hash for uniqueness\n"
    " - Concurrent tests can record safely without file contention\n"
).
-spec save_recording_immediately(
    binary(),
    dream_http_client@recording:recording(),
    binary()
) -> {ok, nil} | {error, binary()}.
save_recording_immediately(Directory, Rec, Key) ->
    _pipe = case simplifile:create_directory_all(Directory) of
        {ok, nil} ->
            {ok, nil};

        {error, eexist} ->
            {ok, nil};

        {error, Directory_error} ->
            {error,
                <<<<<<"Failed to create directory "/utf8, Directory/binary>>/binary,
                        ": "/utf8>>/binary,
                    (gleam@string:inspect(Directory_error))/binary>>}
    end,
    gleam@result:'try'(
        _pipe,
        fun(_) ->
            Recording_file = {recording_file, <<"1.0"/utf8>>, [Rec]},
            Json_value = dream_http_client@recording:encode_recording_file(
                Recording_file
            ),
            Json_string = gleam@json:to_string(Json_value),
            Filename = build_filename(erlang:element(2, Rec), Key, Json_string),
            File_path = <<<<Directory/binary, "/"/utf8>>/binary,
                Filename/binary>>,
            case dream_http_client_fs_shim:atomic_write(File_path, Json_string) of
                {ok, nil} ->
                    {ok, nil};

                {error, Write_error} ->
                    {error,
                        <<<<<<"Failed to write recording file "/utf8,
                                    File_path/binary>>/binary,
                                ": "/utf8>>/binary,
                            (gleam@string:inspect(Write_error))/binary>>}
            end
        end
    ).

-file("src/dream_http_client/storage.gleam", 227).
?DOC(
    " Save multiple recordings to individual files\n"
    "\n"
    " Writes each recording to its own file in the directory. Creates the directory if it\n"
    " doesn't exist. Each file is named based on the request signature for easy identification.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `directory`: The directory where recording files will be written\n"
    " - `recordings`: List of recordings to save\n"
    " - `key_fn`: Match key function used to compute each recording's key string\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(Nil)`: Successfully saved all recordings\n"
    " - `Error(String)`: Error message if directory creation or file write fails\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let recordings = [\n"
    "   create_test_recording(),\n"
    "   create_another_recording(),\n"
    " ]\n"
    " let key_fn = matching.request_key(method: True, url: True, headers: False, body: False)\n"
    "\n"
    " case storage.save_recordings(\"mocks/api\", recordings, key_fn) {\n"
    "   Ok(_) -> io.println(\"Saved recordings successfully\")\n"
    "   Error(reason) -> io.println_error(\"Failed to save: \" <> reason)\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - Directory is created automatically if it doesn't exist\n"
    " - Each recording is saved to its own file (no file contention)\n"
    " - Existing files with the same name are overwritten\n"
).
-spec save_recordings(
    binary(),
    list(dream_http_client@recording:recording()),
    fun((dream_http_client@recording:recorded_request()) -> binary())
) -> {ok, nil} | {error, binary()}.
save_recordings(Directory, Recordings, Key_fn) ->
    _pipe = case simplifile:create_directory_all(Directory) of
        {ok, nil} ->
            {ok, nil};

        {error, eexist} ->
            {ok, nil};

        {error, Directory_error} ->
            {error,
                <<<<<<"Failed to create directory "/utf8, Directory/binary>>/binary,
                        ": "/utf8>>/binary,
                    (gleam@string:inspect(Directory_error))/binary>>}
    end,
    gleam@result:'try'(_pipe, fun(_) -> _pipe@1 = Recordings,
            gleam@list:try_each(
                _pipe@1,
                fun(Rec) ->
                    Key = Key_fn(erlang:element(2, Rec)),
                    save_recording_immediately(Directory, Rec, Key)
                end
            ) end).
