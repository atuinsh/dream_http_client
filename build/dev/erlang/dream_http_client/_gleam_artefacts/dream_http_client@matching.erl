-module(dream_http_client@matching).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/matching.gleam").
-export([match_url_only/0, build_signature/2, requests_match/3]).
-export_type([matching_config/0]).

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
    " Determines if a request matches a recorded request based on configurable\n"
    " matching criteria (method, URL, headers, body).\n"
).

-type matching_config() :: {matching_config,
        boolean(),
        boolean(),
        boolean(),
        boolean()}.

-file("src/dream_http_client/matching.gleam", 95).
?DOC(
    " Default matching configuration: match on method and URL only\n"
    "\n"
    " Creates a `MatchingConfig` that matches requests based on HTTP method and\n"
    " full URL (scheme, host, port, path, query), while ignoring headers and body.\n"
    " This is the recommended configuration for most use cases.\n"
    "\n"
    " ## Why This Default?\n"
    "\n"
    " Headers and bodies often contain dynamic values that change between requests:\n"
    " - Headers: Authorization tokens, timestamps, request IDs, user agents\n"
    " - Bodies: Dynamic IDs, timestamps, session tokens, nonces\n"
    "\n"
    " By ignoring these, recordings remain stable and reusable across different\n"
    " request contexts while still matching on the meaningful request characteristics.\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A `MatchingConfig` with:\n"
    " - `match_method: True`\n"
    " - `match_url: True`\n"
    " - `match_headers: False`\n"
    " - `match_body: False`\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Playback(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),  // Use default matching\n"
    " )\n"
    " ```\n"
).
-spec match_url_only() -> matching_config().
match_url_only() ->
    {matching_config, true, true, false, false}.

-file("src/dream_http_client/matching.gleam", 285).
-spec format_header_pair({binary(), binary()}) -> binary().
format_header_pair(Header) ->
    <<<<(erlang:element(1, Header))/binary, ":"/utf8>>/binary,
        (erlang:element(2, Header))/binary>>.

-file("src/dream_http_client/matching.gleam", 278).
-spec compare_header_names({binary(), binary()}, {binary(), binary()}) -> gleam@order:order().
compare_header_names(Header1, Header2) ->
    gleam@string:compare(erlang:element(1, Header1), erlang:element(1, Header2)).

-file("src/dream_http_client/matching.gleam", 271).
-spec headers_to_string(list({binary(), binary()})) -> binary().
headers_to_string(Headers) ->
    Sorted = gleam@list:sort(Headers, fun compare_header_names/2),
    Header_strings = gleam@list:map(Sorted, fun format_header_pair/1),
    gleam@string:join(Header_strings, <<"|"/utf8>>).

-file("src/dream_http_client/matching.gleam", 264).
-spec scheme_to_string(gleam@http:scheme()) -> binary().
scheme_to_string(Scheme) ->
    case Scheme of
        http ->
            <<"http"/utf8>>;

        https ->
            <<"https"/utf8>>
    end.

-file("src/dream_http_client/matching.gleam", 247).
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

-file("src/dream_http_client/matching.gleam", 232).
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

-file("src/dream_http_client/matching.gleam", 144).
?DOC(
    " Build a request signature for matching\n"
    "\n"
    " Creates a string signature from a request based on the matching configuration.\n"
    " This signature is used as a dictionary key to look up matching recordings.\n"
    " Only the parts of the request specified in the config are included in the signature.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request`: The request to build a signature for\n"
    " - `config`: The matching configuration that determines which parts to include\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A string signature that uniquely identifies the request based on the config.\n"
    " Requests with the same signature will match each other.\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let request = recording.RecordedRequest(\n"
    "   method: http.Get,\n"
    "   scheme: http.Https,\n"
    "   host: \"api.example.com\",\n"
    "   port: option.None,\n"
    "   path: \"/users/123\",\n"
    "   query: option.None,\n"
    "   headers: [#(\"Authorization\", \"Bearer token123\")],\n"
    "   body: \"\",\n"
    " )\n"
    "\n"
    " let config = matching.match_url_only()\n"
    " let signature = matching.build_signature(request, config)\n"
    " // Signature includes method and URL, but not headers or body\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - This function is used internally by the recorder for matching\n"
    " - The signature format is an implementation detail and may change\n"
    " - Headers are sorted alphabetically when included for consistent matching\n"
).
-spec build_signature(
    dream_http_client@recording:recorded_request(),
    matching_config()
) -> binary().
build_signature(Request, Config) ->
    Method_str = case erlang:element(2, Config) of
        true ->
            method_to_string(erlang:element(2, Request));

        false ->
            <<""/utf8>>
    end,
    Url_str = case erlang:element(3, Config) of
        true ->
            build_url(Request);

        false ->
            <<""/utf8>>
    end,
    Headers_str = case erlang:element(4, Config) of
        true ->
            headers_to_string(erlang:element(8, Request));

        false ->
            <<""/utf8>>
    end,
    Body_str = case erlang:element(5, Config) of
        true ->
            erlang:element(9, Request);

        false ->
            <<""/utf8>>
    end,
    <<<<<<Method_str/binary, Url_str/binary>>/binary, Headers_str/binary>>/binary,
        Body_str/binary>>.

-file("src/dream_http_client/matching.gleam", 222).
?DOC(
    " Check if two requests match based on the configuration\n"
    "\n"
    " Determines whether two requests are considered equivalent for the purposes\n"
    " of recording playback. Uses the matching configuration to determine which\n"
    " parts of the requests to compare.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request1`: First request to compare\n"
    " - `request2`: Second request to compare\n"
    " - `config`: Matching configuration that determines which parts to compare\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `True`: Requests match according to the configuration\n"
    " - `False`: Requests do not match\n"
    "\n"
    " ## Examples\n"
    "\n"
    " ```gleam\n"
    " let request1 = recording.RecordedRequest(\n"
    "   method: http.Get,\n"
    "   scheme: http.Https,\n"
    "   host: \"api.example.com\",\n"
    "   port: option.None,\n"
    "   path: \"/users\",\n"
    "   query: option.None,\n"
    "   headers: [#(\"Authorization\", \"Bearer token1\")],\n"
    "   body: \"\",\n"
    " )\n"
    "\n"
    " let request2 = recording.RecordedRequest(\n"
    "   method: http.Get,\n"
    "   scheme: http.Https,\n"
    "   host: \"api.example.com\",\n"
    "   port: option.None,\n"
    "   path: \"/users\",\n"
    "   query: option.None,\n"
    "   headers: [#(\"Authorization\", \"Bearer token2\")],  // Different token\n"
    "   body: \"\",\n"
    " )\n"
    "\n"
    " let config = matching.match_url_only()  // Ignores headers\n"
    " matching.requests_match(request1, request2, config)  // Returns True\n"
    " ```\n"
    "\n"
    " ## Notes\n"
    "\n"
    " - This function is used internally by the recorder\n"
    " - Matching is based on string signatures built from the config\n"
    " - Headers are sorted before comparison for consistent results\n"
).
-spec requests_match(
    dream_http_client@recording:recorded_request(),
    dream_http_client@recording:recorded_request(),
    matching_config()
) -> boolean().
requests_match(Request1, Request2, Config) ->
    Sig1 = build_signature(Request1, Config),
    Sig2 = build_signature(Request2, Config),
    Sig1 =:= Sig2.
