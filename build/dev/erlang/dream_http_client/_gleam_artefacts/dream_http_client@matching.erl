-module(dream_http_client@matching).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/matching.gleam").
-export([request_key/4]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Request matching logic\n"
    "\n"
    " Provides helpers for building stable request match keys.\n"
    "\n"
    " A match key is a function that converts a `recording.RecordedRequest` into a\n"
    " string. Requests that produce the same key are considered equivalent for\n"
    " recording lookup and playback.\n"
    "\n"
    " ## Keys + transformers\n"
    "\n"
    " For many use cases, a key alone is enough. For cases like “ignore one query\n"
    " parameter” or “scrub secrets but still match”, pair a key with a\n"
    " `recorder.request_transformer(...)` so both matching and persistence see the same\n"
    " normalized request.\n"
).

-file("src/dream_http_client/matching.gleam", 177).
-spec format_header_pair({binary(), binary()}) -> binary().
format_header_pair(Header) ->
    <<<<(erlang:element(1, Header))/binary, ":"/utf8>>/binary,
        (erlang:element(2, Header))/binary>>.

-file("src/dream_http_client/matching.gleam", 170).
-spec compare_header_names({binary(), binary()}, {binary(), binary()}) -> gleam@order:order().
compare_header_names(Header1, Header2) ->
    gleam@string:compare(erlang:element(1, Header1), erlang:element(1, Header2)).

-file("src/dream_http_client/matching.gleam", 163).
-spec headers_to_string(list({binary(), binary()})) -> binary().
headers_to_string(Headers) ->
    Sorted = gleam@list:sort(Headers, fun compare_header_names/2),
    Header_strings = gleam@list:map(Sorted, fun format_header_pair/1),
    gleam@string:join(Header_strings, <<"|"/utf8>>).

-file("src/dream_http_client/matching.gleam", 156).
-spec scheme_to_string(gleam@http:scheme()) -> binary().
scheme_to_string(Scheme) ->
    case Scheme of
        http ->
            <<"http"/utf8>>;

        https ->
            <<"https"/utf8>>
    end.

-file("src/dream_http_client/matching.gleam", 139).
-spec build_url(dream_http_client@recording:recorded_request()) -> binary().
build_url(Request) ->
    Port_string = case erlang:element(5, Request) of
        {some, Port} ->
            <<":"/utf8, (erlang:integer_to_binary(Port))/binary>>;

        none ->
            <<""/utf8>>
    end,
    Query_string = case erlang:element(7, Request) of
        {some, Query} ->
            <<"?"/utf8, Query/binary>>;

        none ->
            <<""/utf8>>
    end,
    <<<<<<<<<<(scheme_to_string(erlang:element(3, Request)))/binary,
                        "://"/utf8>>/binary,
                    (erlang:element(4, Request))/binary>>/binary,
                Port_string/binary>>/binary,
            (erlang:element(6, Request))/binary>>/binary,
        Query_string/binary>>.

-file("src/dream_http_client/matching.gleam", 124).
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

-file("src/dream_http_client/matching.gleam", 93).
?DOC(
    " Create a request key function from simple include/exclude flags.\n"
    "\n"
    " This is intended for the most common matching policies. For more advanced\n"
    " matching (ignore specific headers, normalize paths, drop query params, etc.)\n"
    " compose a `recorder.request_transformer(...)` with a custom key function.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `method`: Include the HTTP method in the key\n"
    " - `url`: Include the full URL (scheme + host + port + path + query) in the key\n"
    " - `headers`: Include request headers in the key (sorted by header name)\n"
    " - `body`: Include the request body in the key\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A `MatchKey` function.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/matching\n"
    " import dream_http_client/recording\n"
    " import dream_http_client/recorder.{directory, key, mode, request_transformer, start}\n"
    " import gleam/list\n"
    "\n"
    " // Build a key that ignores headers and body.\n"
    " let key =\n"
    "   matching.request_key(method: True, url: True, headers: False, body: False)\n"
    "\n"
    " // Drop Authorization before keying and before writing to disk.\n"
    " fn drop_auth(req: recording.RecordedRequest) -> recording.RecordedRequest {\n"
    "   let headers =\n"
    "     req.headers\n"
    "     |> list.filter(fn(h) { h.0 != \"Authorization\" })\n"
    "   recording.RecordedRequest(..req, headers: headers)\n"
    " }\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> mode(\"record\")\n"
    "   |> directory(\"mocks/api\")\n"
    "   |> key(key)\n"
    "   |> request_transformer(drop_auth)\n"
    "   |> start()\n"
    " ```\n"
).
-spec request_key(boolean(), boolean(), boolean(), boolean()) -> fun((dream_http_client@recording:recorded_request()) -> binary()).
request_key(Method, Url, Headers, Body) ->
    fun(Request) ->
        Method_str = case Method of
            true ->
                method_to_string(erlang:element(2, Request));

            false ->
                <<""/utf8>>
        end,
        Url_str = case Url of
            true ->
                build_url(Request);

            false ->
                <<""/utf8>>
        end,
        Headers_str = case Headers of
            true ->
                headers_to_string(erlang:element(8, Request));

            false ->
                <<""/utf8>>
        end,
        Body_str = case Body of
            true ->
                erlang:element(9, Request);

            false ->
                <<""/utf8>>
        end,
        <<<<<<Method_str/binary, Url_str/binary>>/binary, Headers_str/binary>>/binary,
            Body_str/binary>>
    end.
