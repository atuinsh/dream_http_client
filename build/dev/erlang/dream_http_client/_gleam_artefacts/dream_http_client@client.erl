-module(dream_http_client@client).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/client.gleam").
-export([new/0, method/2, scheme/2, host/2, port/2, path/2, 'query'/2, headers/2, body/2, recorder/2, timeout/2, on_stream_start/2, on_stream_chunk/2, on_stream_end/2, on_stream_error/2, add_header/3, get_method/1, get_scheme/1, get_host/1, get_port/1, get_path/1, get_query/1, get_headers/1, get_body/1, get_timeout/1, get_recorder/1, send/1, stream_yielder/1, start_stream/1, cancel_stream_handle/1, is_stream_active/1, await_stream/1, cancel_stream/1]).
-export_type([header/0, http_response/0, send_error/0, client_request/0, request_id/0, stream_message/0, stream_handle/0, yielder_state/0, recording_yielder_state/0, message_stream_recorder_state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Type-safe HTTP client with recording + streaming support\n"
    "\n"
    " Gleam doesn't ship with an HTTPS client, so this module wraps Erlang's\n"
    " battle‑hardened `httpc` and adds a friendly builder API, streaming helpers,\n"
    " and optional record/playback via `dream_http_client/recorder`.\n"
    "\n"
    " ## Quick Example — blocking request\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{add_header, host, path, send}\n"
    "\n"
    " pub fn call_api(token: String) -> Result(String, String) {\n"
    "   client.new()\n"
    "   |> host(\"api.example.com\")\n"
    "   |> path(\"/users/123\")\n"
    "   |> add_header(\"Authorization\", \"Bearer \" <> token)\n"
    "   |> send()\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Execution modes\n"
    "\n"
    " You can execute the same `ClientRequest` in three ways:\n"
    "\n"
    " - **Blocking**: `send()` returns the full response body.\n"
    " - **Pull streaming**: `stream_yielder()` returns a `yielder.Yielder` of chunks.\n"
    " - **Callback streaming**: `start_stream()` spawns a stream process and calls\n"
    "   your callbacks (`on_stream_*`) as events arrive.\n"
    "\n"
    " The “right” choice is mostly about concurrency:\n"
    "\n"
    " - Use `send()` for normal JSON APIs.\n"
    " - Use `stream_yielder()` for scripts/one‑offs where blocking is fine.\n"
    " - Use `start_stream()` when you need non‑blocking streaming in OTP code.\n"
    "\n"
    " ## Recording and playback\n"
    "\n"
    " Attach a recorder with `recorder()` to record real HTTP traffic to disk, or\n"
    " to play back recordings without network calls. All three execution modes\n"
    " (`send()`, `stream_yielder()`, `start_stream()`) fully support both\n"
    " recording and playback.\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, recorder, send}\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks/api\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " let assert Ok(body) =\n"
    "   client.new()\n"
    "   |> host(\"api.example.com\")\n"
    "   |> path(\"/users/123\")\n"
    "   |> recorder(rec)\n"
    "   |> send()\n"
    " ```\n"
    "\n"
    " ## Inspecting requests\n"
    "\n"
    " `ClientRequest` is opaque to keep the public API stable; use the `get_*`\n"
    " functions for logging/testing.\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{get_host, get_path, host, path}\n"
    " import gleam/io\n"
    "\n"
    " let req = client.new() |> host(\"api.example.com\") |> path(\"/users/123\")\n"
    " io.println(\"Calling: \" <> get_host(req) <> get_path(req))\n"
    " ```\n"
).

-type header() :: {header, binary(), binary()}.

-type http_response() :: {http_response, integer(), list(header()), binary()}.

-type send_error() :: {response_error, http_response()} |
    {request_error, binary()}.

-opaque client_request() :: {client_request,
        gleam@http:method(),
        gleam@http:scheme(),
        binary(),
        gleam@option:option(integer()),
        binary(),
        gleam@option:option(binary()),
        list(header()),
        binary(),
        gleam@option:option(integer()),
        gleam@option:option(dream_http_client@recorder:recorder()),
        gleam@option:option(fun((list(header())) -> nil)),
        gleam@option:option(fun((bitstring()) -> nil)),
        gleam@option:option(fun((list(header())) -> nil)),
        gleam@option:option(fun((binary()) -> nil))}.

-opaque request_id() :: {request_id, binary()}.

-type stream_message() :: {stream_start, request_id(), list(header())} |
    {chunk, request_id(), bitstring()} |
    {stream_end, request_id(), list(header())} |
    {stream_error, request_id(), binary()} |
    {decode_error, binary()}.

-opaque stream_handle() :: {stream_handle, gleam@erlang@process:pid_()}.

-type yielder_state() :: {yielder_state,
        gleam@option:option(gleam@dynamic:dynamic_()),
        gleam@http@request:request(binary()),
        integer()}.

-type recording_yielder_state() :: {recording_yielder_state,
        gleam@option:option(gleam@dynamic:dynamic_()),
        gleam@http@request:request(binary()),
        integer(),
        dream_http_client@recorder:recorder(),
        dream_http_client@recording:recorded_request(),
        list({binary(), binary()}),
        list(dream_http_client@recording:chunk()),
        gleam@option:option(integer())}.

-type message_stream_recorder_state() :: {message_stream_recorder_state,
        dream_http_client@recorder:recorder(),
        dream_http_client@recording:recorded_request(),
        list({binary(), binary()}),
        list(dream_http_client@recording:chunk()),
        gleam@option:option(integer())}.

-file("src/dream_http_client/client.gleam", 258).
?DOC(
    " Default client request configuration\n"
    "\n"
    " Creates a new `ClientRequest` with sensible defaults:\n"
    " - Method: GET\n"
    " - Scheme: HTTPS\n"
    " - Host: \"localhost\"\n"
    " - Port: None (uses default for scheme)\n"
    " - Path: \"\" (empty)\n"
    " - Query: None\n"
    " - Headers: [] (empty)\n"
    " - Body: \"\" (empty)\n"
    " - Timeout: None (uses default 30000ms)\n"
    "\n"
    " Use this as the starting point for building requests with the builder pattern.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, method, new, path}\n"
    " import gleam/http.{Get}\n"
    "\n"
    " new()\n"
    " |> host(\"api.example.com\")\n"
    " |> path(\"/users/123\")\n"
    " |> method(Get)\n"
    " ```\n"
).
-spec new() -> client_request().
new() ->
    {client_request,
        get,
        https,
        <<"localhost"/utf8>>,
        none,
        <<""/utf8>>,
        none,
        [],
        <<""/utf8>>,
        none,
        none,
        none,
        none,
        none,
        none}.

-file("src/dream_http_client/client.gleam", 299).
?DOC(
    " Set the HTTP method for the request\n"
    "\n"
    " Configures the HTTP method (GET, POST, PUT, DELETE, etc.) for the request.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `method_value`: The HTTP method to use\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the method updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/http\n"
    "\n"
    " client.new()\n"
    " |> client.method(http.Post)\n"
    " ```\n"
).
-spec method(client_request(), gleam@http:method()) -> client_request().
method(Client_request, Method_value) ->
    {client_request,
        Method_value,
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 328).
?DOC(
    " Set the scheme (protocol) for the request\n"
    "\n"
    " Configures whether to use HTTP or HTTPS. Defaults to HTTPS for security.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `scheme_value`: The protocol scheme (`http.Http` or `http.Https`)\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the scheme updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/http\n"
    "\n"
    " client.new()\n"
    " |> client.scheme(http.Http)  // Use HTTP instead of HTTPS\n"
    " ```\n"
).
-spec scheme(client_request(), gleam@http:scheme()) -> client_request().
scheme(Client_request, Scheme_value) ->
    {client_request,
        erlang:element(2, Client_request),
        Scheme_value,
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 356).
?DOC(
    " Set the host for the request\n"
    "\n"
    " Sets the server hostname or IP address. This is required for all requests.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `host_value`: The hostname (e.g., \"api.example.com\" or \"192.168.1.1\")\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the host updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.host(\"api.example.com\")\n"
    " ```\n"
).
-spec host(client_request(), binary()) -> client_request().
host(Client_request, Host_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        Host_value,
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 383).
?DOC(
    " Set the port for the request\n"
    "\n"
    " Sets a custom port number. If not set, defaults to 80 for HTTP and 443\n"
    " for HTTPS. Only set this if you're using a non-standard port.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `port_value`: The port number (e.g., 8080, 3000)\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the port updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.host(\"localhost\")\n"
    " |> client.port(3000)  // Use port 3000 instead of default\n"
    " ```\n"
).
-spec port(client_request(), integer()) -> client_request().
port(Client_request, Port_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        {some, Port_value},
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 408).
?DOC(
    " Set the path for the request\n"
    "\n"
    " Sets the request path. Should start with \"/\" for absolute paths.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `path_value`: The path (e.g., \"/api/users\" or \"/api/users/123\")\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the path updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.path(\"/api/users/123\")\n"
    " ```\n"
).
-spec path(client_request(), binary()) -> client_request().
path(Client_request, Path_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        Path_value,
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 434).
?DOC(
    " Set the query string for the request\n"
    "\n"
    " Sets the query string portion of the URL. Do not include the leading \"?\".\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `query_value`: The query string (e.g., \"page=1&limit=10\")\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the query string updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.path(\"/api/users\")\n"
    " |> client.query(\"page=1&limit=10\")\n"
    " ```\n"
).
-spec 'query'(client_request(), binary()) -> client_request().
'query'(Client_request, Query_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        {some, Query_value},
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 466).
?DOC(
    " Set the headers for the request\n"
    "\n"
    " Replaces all existing headers with the provided list. Use `add_header()`\n"
    " to add a single header without replacing existing ones.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `headers_value`: List of header tuples `#(name, value)`\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with headers replaced.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.headers([\n"
    "   #(\"Authorization\", \"Bearer \" <> token),\n"
    "   #(\"Content-Type\", \"application/json\"),\n"
    " ])\n"
    " ```\n"
).
-spec headers(client_request(), list(header())) -> client_request().
headers(Client_request, Headers_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        Headers_value,
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 502).
?DOC(
    " Set the body for the request\n"
    "\n"
    " Sets the request body as a string. Typically used for POST, PUT, and PATCH\n"
    " requests. For JSON, serialize your data first.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `body_value`: The request body as a string\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the body updated.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/json\n"
    "\n"
    " let json_body = json.object([\n"
    "   #(\"name\", json.string(\"Alice\")),\n"
    "   #(\"email\", json.string(\"alice@example.com\")),\n"
    " ])\n"
    "\n"
    " client.new()\n"
    " |> client.method(http.Post)\n"
    " |> client.body(json.to_string(json_body))\n"
    " ```\n"
).
-spec body(client_request(), binary()) -> client_request().
body(Client_request, Body_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        Body_value,
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 535).
?DOC(
    " Set the recorder for the request\n"
    "\n"
    " Attaches a recorder to the request for recording or playback.\n"
    " The recorder must be started with `recorder.start()` before use.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `recorder_value`: The recorder to attach\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the recorder attached.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import dream_http_client/client.{host, recorder}\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    "\n"
    " client.new() |> host(\"api.example.com\") |> recorder(rec)\n"
    " ```\n"
).
-spec recorder(client_request(), dream_http_client@recorder:recorder()) -> client_request().
recorder(Client_request, Recorder_value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        {some, Recorder_value},
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 560).
?DOC(
    " Set the timeout for the request in milliseconds\n"
    "\n"
    " Sets how long to wait for a response before timing out. If not set,\n"
    " defaults to 30000ms (30 seconds).\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `timeout_ms`: Timeout duration in milliseconds\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, timeout}\n"
    "\n"
    " client.new()\n"
    " |> host(\"slow-api.example.com\")\n"
    " |> timeout(60_000)  // 60 second timeout\n"
    " ```\n"
).
-spec timeout(client_request(), integer()) -> client_request().
timeout(Client_request, Timeout_ms) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        {some, Timeout_ms},
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 584).
?DOC(
    " Set callback for stream start event\n"
    "\n"
    " Sets a function to be called when a stream starts and headers are received.\n"
    " Optional - if not set, stream start is ignored.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `callback`: Function called with response headers when stream starts\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " client.new()\n"
    " |> client.host(\"api.example.com\")\n"
    " |> client.on_stream_start(fn(headers) {\n"
    "   io.println(\"Stream started with \" <> int.to_string(list.length(headers)) <> \" headers\")\n"
    " })\n"
    " |> client.start_stream()\n"
    " ```\n"
).
-spec on_stream_start(client_request(), fun((list(header())) -> nil)) -> client_request().
on_stream_start(Client_request, Callback) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        {some, Callback},
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 612).
?DOC(
    " Set callback for stream chunk event\n"
    "\n"
    " Sets a function to be called for each data chunk received from the stream.\n"
    " This is where you process the actual response data.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `callback`: Function called with each chunk of data\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " client.new()\n"
    " |> client.host(\"api.openai.com\")\n"
    " |> client.on_stream_chunk(fn(data) {\n"
    "   let text = bytes_tree.from_bit_array(data) |> bytes_tree.to_string\n"
    "   io.print(text)\n"
    " })\n"
    " |> client.start_stream()\n"
    " ```\n"
).
-spec on_stream_chunk(client_request(), fun((bitstring()) -> nil)) -> client_request().
on_stream_chunk(Client_request, Callback) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        {some, Callback},
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 639).
?DOC(
    " Set callback for stream end event\n"
    "\n"
    " Sets a function to be called when a stream completes successfully.\n"
    " Optional - if not set, stream completion is ignored.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `callback`: Function called with trailing headers when stream completes\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " client.new()\n"
    " |> client.host(\"api.example.com\")\n"
    " |> client.on_stream_end(fn(_headers) {\n"
    "   io.println(\"Stream completed\")\n"
    " })\n"
    " |> client.start_stream()\n"
    " ```\n"
).
-spec on_stream_end(client_request(), fun((list(header())) -> nil)) -> client_request().
on_stream_end(Client_request, Callback) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        {some, Callback},
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 666).
?DOC(
    " Set callback for stream error event\n"
    "\n"
    " Sets a function to be called if the stream fails with an error.\n"
    " Handles both HTTP errors and network errors.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `callback`: Function called with error reason if stream fails\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " client.new()\n"
    " |> client.host(\"api.example.com\")\n"
    " |> client.on_stream_error(fn(reason) {\n"
    "   io.println_error(\"Stream failed: \" <> reason)\n"
    " })\n"
    " |> client.start_stream()\n"
    " ```\n"
).
-spec on_stream_error(client_request(), fun((binary()) -> nil)) -> client_request().
on_stream_error(Client_request, Callback) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        erlang:element(8, Client_request),
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        {some, Callback}}.

-file("src/dream_http_client/client.gleam", 698).
?DOC(
    " Add a header to the request\n"
    "\n"
    " Adds a single header to the existing headers list without replacing them.\n"
    " The new header is prepended to the list, so it will take precedence if\n"
    " there's a duplicate header name.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The request to modify\n"
    " - `name`: The header name (e.g., \"Authorization\", \"Content-Type\")\n"
    " - `value`: The header value\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A new `ClientRequest` with the header added.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " client.new()\n"
    " |> client.add_header(\"Authorization\", \"Bearer \" <> token)\n"
    " |> client.add_header(\"Content-Type\", \"application/json\")\n"
    " ```\n"
).
-spec add_header(client_request(), binary(), binary()) -> client_request().
add_header(Client_request, Name, Value) ->
    {client_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        [{header, Name, Value} | erlang:element(8, Client_request)],
        erlang:element(9, Client_request),
        erlang:element(10, Client_request),
        erlang:element(11, Client_request),
        erlang:element(12, Client_request),
        erlang:element(13, Client_request),
        erlang:element(14, Client_request),
        erlang:element(15, Client_request)}.

-file("src/dream_http_client/client.gleam", 727).
?DOC(
    " Get the HTTP method from a request\n"
    "\n"
    " Returns the HTTP method (GET, POST, etc.) configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/http.{Post}\n"
    "\n"
    " let req = client.new() |> client.method(Post)\n"
    " let method = client.get_method(req)\n"
    " // method == Post\n"
    " ```\n"
).
-spec get_method(client_request()) -> gleam@http:method().
get_method(Client_request) ->
    erlang:element(2, Client_request).

-file("src/dream_http_client/client.gleam", 745).
?DOC(
    " Get the URI scheme from a request\n"
    "\n"
    " Returns the scheme (HTTP or HTTPS) configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/http.{Http}\n"
    "\n"
    " let req = client.new() |> client.scheme(Http)\n"
    " let scheme = client.get_scheme(req)\n"
    " // scheme == Http\n"
    " ```\n"
).
-spec get_scheme(client_request()) -> gleam@http:scheme().
get_scheme(Client_request) ->
    erlang:element(3, Client_request).

-file("src/dream_http_client/client.gleam", 762).
?DOC(
    " Get the host from a request\n"
    "\n"
    " Returns the hostname configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.host(\"api.example.com\")\n"
    " let host = client.get_host(req)\n"
    " // host == \"api.example.com\"\n"
    " ```\n"
).
-spec get_host(client_request()) -> binary().
get_host(Client_request) ->
    erlang:element(4, Client_request).

-file("src/dream_http_client/client.gleam", 780).
?DOC(
    " Get the port from a request\n"
    "\n"
    " Returns the optional port number configured for the request.\n"
    " If None, the default port for the scheme will be used (80 for HTTP, 443 for HTTPS).\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.port(8080)\n"
    " let port = client.get_port(req)\n"
    " // port == Some(8080)\n"
    " ```\n"
).
-spec get_port(client_request()) -> gleam@option:option(integer()).
get_port(Client_request) ->
    erlang:element(5, Client_request).

-file("src/dream_http_client/client.gleam", 797).
?DOC(
    " Get the path from a request\n"
    "\n"
    " Returns the request path configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.path(\"/api/users\")\n"
    " let path = client.get_path(req)\n"
    " // path == \"/api/users\"\n"
    " ```\n"
).
-spec get_path(client_request()) -> binary().
get_path(Client_request) ->
    erlang:element(6, Client_request).

-file("src/dream_http_client/client.gleam", 814).
?DOC(
    " Get the query string from a request\n"
    "\n"
    " Returns the optional query string configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.query(\"page=1&limit=10\")\n"
    " let query = client.get_query(req)\n"
    " // query == Some(\"page=1&limit=10\")\n"
    " ```\n"
).
-spec get_query(client_request()) -> gleam@option:option(binary()).
get_query(Client_request) ->
    erlang:element(7, Client_request).

-file("src/dream_http_client/client.gleam", 833).
?DOC(
    " Get the headers from a request\n"
    "\n"
    " Returns the list of headers configured for the request.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new()\n"
    "   |> client.add_header(\"Authorization\", \"Bearer token\")\n"
    "   |> client.add_header(\"Content-Type\", \"application/json\")\n"
    " let headers = client.get_headers(req)\n"
    " // headers == [Header(\"Content-Type\", \"application/json\"), Header(\"Authorization\", \"Bearer token\")]\n"
    " ```\n"
).
-spec get_headers(client_request()) -> list(header()).
get_headers(Client_request) ->
    erlang:element(8, Client_request).

-file("src/dream_http_client/client.gleam", 850).
?DOC(
    " Get the body from a request\n"
    "\n"
    " Returns the request body as a string.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.body(\"{\\\"name\\\": \\\"Alice\\\"}\")\n"
    " let body = client.get_body(req)\n"
    " // body == \"{\\\"name\\\": \\\"Alice\\\"}\"\n"
    " ```\n"
).
-spec get_body(client_request()) -> binary().
get_body(Client_request) ->
    erlang:element(9, Client_request).

-file("src/dream_http_client/client.gleam", 868).
?DOC(
    " Get the timeout from a request\n"
    "\n"
    " Returns the optional timeout in milliseconds configured for the request.\n"
    " If None, the default timeout (30000ms) will be used.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    "\n"
    " let req = client.new() |> client.timeout(5000)\n"
    " let timeout = client.get_timeout(req)\n"
    " // timeout == Some(5000)\n"
    " ```\n"
).
-spec get_timeout(client_request()) -> gleam@option:option(integer()).
get_timeout(Client_request) ->
    erlang:element(10, Client_request).

-file("src/dream_http_client/client.gleam", 891).
?DOC(
    " Get the recorder from a request\n"
    "\n"
    " Returns the optional recorder attached to the request for recording or playback.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import dream_http_client/recorder.{directory, mode, start}\n"
    "\n"
    " let assert Ok(rec) =\n"
    "   recorder.new()\n"
    "   |> directory(\"mocks\")\n"
    "   |> mode(\"record\")\n"
    "   |> start()\n"
    " let req = client.new() |> client.recorder(rec)\n"
    " let recorder_opt = client.get_recorder(req)\n"
    " // recorder_opt == Some(rec)\n"
    " ```\n"
).
-spec get_recorder(client_request()) -> gleam@option:option(dream_http_client@recorder:recorder()).
get_recorder(Client_request) ->
    erlang:element(11, Client_request).

-file("src/dream_http_client/client.gleam", 1493).
-spec tuples_to_headers(list({binary(), binary()})) -> list(header()).
tuples_to_headers(Tuples) ->
    gleam@list:map(
        Tuples,
        fun(T) -> {header, erlang:element(1, T), erlang:element(2, T)} end
    ).

-file("src/dream_http_client/client.gleam", 1497).
-spec response_result(integer(), list({binary(), binary()}), binary()) -> {ok,
        http_response()} |
    {error, send_error()}.
response_result(Status, Headers, Body) ->
    Response = {http_response, Status, tuples_to_headers(Headers), Body},
    case Status >= 400 of
        true ->
            {error, {response_error, Response}};

        false ->
            {ok, Response}
    end.

-file("src/dream_http_client/client.gleam", 1206).
-spec convert_string_error(nil) -> binary().
convert_string_error(_) ->
    <<"Failed to convert response to string"/utf8>>.

-file("src/dream_http_client/client.gleam", 1212).
-spec resolve_timeout(client_request()) -> integer().
resolve_timeout(Client_request) ->
    case erlang:element(10, Client_request) of
        {some, Timeout_value} ->
            Timeout_value;

        none ->
            30000
    end.

-file("src/dream_http_client/client.gleam", 1781).
-spec build_url(gleam@http@request:request(binary())) -> binary().
build_url(Request) ->
    Port_string = case erlang:element(7, Request) of
        {some, Port} ->
            <<":"/utf8, (erlang:integer_to_binary(Port))/binary>>;

        none ->
            <<""/utf8>>
    end,
    Query_string = case erlang:element(9, Request) of
        {some, Query} ->
            <<"?"/utf8, Query/binary>>;

        none ->
            <<""/utf8>>
    end,
    <<<<<<<<<<(gleam@http:scheme_to_string(erlang:element(5, Request)))/binary,
                        "://"/utf8>>/binary,
                    (erlang:element(6, Request))/binary>>/binary,
                Port_string/binary>>/binary,
            (erlang:element(8, Request))/binary>>/binary,
        Query_string/binary>>.

-file("src/dream_http_client/client.gleam", 1489).
-spec headers_to_tuples(list(header())) -> list({binary(), binary()}).
headers_to_tuples(Headers) ->
    gleam@list:map(
        Headers,
        fun(H) -> {erlang:element(2, H), erlang:element(3, H)} end
    ).

-file("src/dream_http_client/client.gleam", 1476).
-spec to_http_request(client_request()) -> gleam@http@request:request(binary()).
to_http_request(Client_request) ->
    {request,
        erlang:element(2, Client_request),
        headers_to_tuples(erlang:element(8, Client_request)),
        erlang:element(9, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request)}.

-file("src/dream_http_client/client.gleam", 1168).
-spec send_client_request_to_httpc_with_meta(client_request()) -> {ok,
        {integer(), list({binary(), binary()}), binary()}} |
    {error, binary()}.
send_client_request_to_httpc_with_meta(Client_request) ->
    Http_request = to_http_request(Client_request),
    Url = build_url(Http_request),
    Method_atom = dream_http_client@internal:atomize_method(
        erlang:element(2, Http_request)
    ),
    Method_dynamic = gleam_erlang_ffi:identity(Method_atom),
    Body = <<(erlang:element(4, Http_request))/binary>>,
    Timeout_value = resolve_timeout(Client_request),
    case dream_httpc_shim:request_sync(
        Method_dynamic,
        Url,
        erlang:element(3, Http_request),
        Body,
        Timeout_value
    ) of
        {ok, {Status, Headers, Response_body}} ->
            _pipe = Response_body,
            _pipe@1 = gleam@bit_array:to_string(_pipe),
            _pipe@2 = gleam@result:map_error(
                _pipe@1,
                fun convert_string_error/1
            ),
            gleam@result:map(
                _pipe@2,
                fun(Body_str) -> {Status, Headers, Body_str} end
            );

        {error, Error_message} ->
            {error, Error_message}
    end.

-file("src/dream_http_client/client.gleam", 1159).
-spec send_client_request_to_httpc(client_request()) -> {ok, http_response()} |
    {error, send_error()}.
send_client_request_to_httpc(Client_request) ->
    case send_client_request_to_httpc_with_meta(Client_request) of
        {ok, {Status, Headers, Body}} ->
            response_result(Status, Headers, Body);

        {error, Error_message} ->
            {error, {request_error, Error_message}}
    end.

-file("src/dream_http_client/client.gleam", 1077).
-spec send_without_recorder(client_request()) -> {ok, http_response()} |
    {error, send_error()}.
send_without_recorder(Client_request) ->
    send_client_request_to_httpc(Client_request).

-file("src/dream_http_client/client.gleam", 1144).
-spec record_response_if_needed(
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request(),
    dream_http_client@recording:recorded_response()
) -> nil.
record_response_if_needed(Recorder_instance, Recorded_request, Response) ->
    case dream_http_client@recorder:is_record_mode(Recorder_instance) of
        true ->
            Recorder_entry = {recording, Recorded_request, Response},
            dream_http_client@recorder:add_recording(
                Recorder_instance,
                Recorder_entry
            );

        false ->
            nil
    end.

-file("src/dream_http_client/client.gleam", 1111).
-spec send_and_maybe_record(
    client_request(),
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request()
) -> {ok, http_response()} | {error, send_error()}.
send_and_maybe_record(Client_request, Recorder_instance, Recorded_request) ->
    case send_client_request_to_httpc_with_meta(Client_request) of
        {ok, {Status, Headers, Body}} ->
            Recorded_response = {blocking_response, Status, Headers, Body},
            Response_for_recording = case dream_http_client@recorder:is_record_mode(
                Recorder_instance
            ) of
                true ->
                    dream_http_client@recorder:transform_response(
                        Recorder_instance,
                        Recorded_request,
                        Recorded_response
                    );

                false ->
                    Recorded_response
            end,
            record_response_if_needed(
                Recorder_instance,
                Recorded_request,
                Response_for_recording
            ),
            response_result(Status, Headers, Body);

        {error, Error_message} ->
            {error, {request_error, Error_message}}
    end.

-file("src/dream_http_client/client.gleam", 1098).
-spec handle_recorded_blocking_response(
    dream_http_client@recording:recorded_response()
) -> {ok, http_response()} | {error, send_error()}.
handle_recorded_blocking_response(Response) ->
    case Response of
        {blocking_response, Status, Headers, Body} ->
            response_result(Status, Headers, Body);

        {streaming_response, _, _, _} ->
            {error,
                {request_error,
                    <<"Recording contains streaming response, use stream_yielder() instead"/utf8>>}}
    end.

-file("src/dream_http_client/client.gleam", 1191).
-spec client_request_to_recorded_request(client_request()) -> dream_http_client@recording:recorded_request().
client_request_to_recorded_request(Client_request) ->
    {recorded_request,
        erlang:element(2, Client_request),
        erlang:element(3, Client_request),
        erlang:element(4, Client_request),
        erlang:element(5, Client_request),
        erlang:element(6, Client_request),
        erlang:element(7, Client_request),
        headers_to_tuples(erlang:element(8, Client_request)),
        erlang:element(9, Client_request)}.

-file("src/dream_http_client/client.gleam", 1083).
-spec send_with_recorder(
    client_request(),
    dream_http_client@recorder:recorder()
) -> {ok, http_response()} | {error, send_error()}.
send_with_recorder(Client_request, Recorder_instance) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    case dream_http_client@recorder:find_recording(
        Recorder_instance,
        Recorded_request
    ) of
        {ok, {some, {recording, _, Response}}} ->
            handle_recorded_blocking_response(Response);

        {ok, none} ->
            send_and_maybe_record(
                Client_request,
                Recorder_instance,
                Recorded_request
            );

        {error, Reason} ->
            {error, {request_error, Reason}}
    end.

-file("src/dream_http_client/client.gleam", 1069).
?DOC(
    " Make a blocking HTTP request and get the complete response\n"
    "\n"
    " Sends an HTTP request and collects all response chunks, returning the\n"
    " complete response with status code, headers, and body. This is ideal for:\n"
    "\n"
    " - JSON API responses\n"
    " - Small files or documents\n"
    " - Any case where you need the full response before processing\n"
    "\n"
    " For large responses or when you need non-blocking streaming, use\n"
    " `stream_yielder()` or `start_stream()` instead.\n"
    "\n"
    " ## Recording and Playback\n"
    "\n"
    " When a recorder is attached (via `recorder()`), this function fully supports\n"
    " both recording and playback. In record mode, the real response is persisted\n"
    " to disk. In playback mode, the recorded response is returned without making\n"
    " a network call.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The configured HTTP request\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(HttpResponse)`: Successful response (status < 400) with status, headers, and body\n"
    " - `Error(ResponseError(response))`: HTTP error response (status >= 400) with full response\n"
    " - `Error(RequestError(message))`: Connection failure, timeout, or other transport error\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{\n"
    "   HttpResponse, RequestError, ResponseError,\n"
    "   host, path, add_header, send,\n"
    " }\n"
    "\n"
    " let result = client.new()\n"
    "   |> host(\"api.example.com\")\n"
    "   |> path(\"/users/123\")\n"
    "   |> add_header(\"Authorization\", \"Bearer \" <> token)\n"
    "   |> send()\n"
    "\n"
    " case result {\n"
    "   Ok(HttpResponse(body: body, ..)) -> {\n"
    "     case json.decode(body, user_decoder) {\n"
    "       Ok(user) -> Ok(user)\n"
    "       Error(json_error) ->\n"
    "         Error(\"Invalid JSON: \" <> string.inspect(json_error))\n"
    "     }\n"
    "   }\n"
    "   Error(ResponseError(response)) ->\n"
    "     Error(\"HTTP \" <> int.to_string(response.status) <> \": \" <> response.body)\n"
    "   Error(RequestError(message)) ->\n"
    "     Error(\"Request failed: \" <> message)\n"
    " }\n"
    " ```\n"
).
-spec send(client_request()) -> {ok, http_response()} | {error, send_error()}.
send(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            send_with_recorder(Client_request, Recorder_instance);

        none ->
            send_without_recorder(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 1531).
-spec handle_yielder_next_with_state(gleam@dynamic:dynamic_(), yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, yielder_state()).
handle_yielder_next_with_state(Owner, State) ->
    case dream_http_client@internal:receive_next(
        Owner,
        erlang:element(4, State)
    ) of
        {ok, {some, Bin}} ->
            {next, {ok, gleam@bytes_tree:from_bit_array(Bin)}, State};

        {ok, none} ->
            done;

        {error, Error_reason} ->
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1514).
-spec handle_yielder_start_with_state(yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, yielder_state()).
handle_yielder_start_with_state(State) ->
    Request_result = dream_http_client@internal:start_httpc_stream(
        erlang:element(3, State),
        erlang:element(4, State)
    ),
    Owner = dream_http_client@internal:extract_owner_pid(Request_result),
    case dream_http_client@internal:receive_next(
        Owner,
        erlang:element(4, State)
    ) of
        {ok, {some, Bin}} ->
            {next,
                {ok, gleam@bytes_tree:from_bit_array(Bin)},
                {yielder_state,
                    {some, Owner},
                    erlang:element(3, State),
                    erlang:element(4, State)}};

        {ok, none} ->
            done;

        {error, Error_reason} ->
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1467).
-spec handle_yielder_unfold_with_deps(yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, yielder_state()).
handle_yielder_unfold_with_deps(State) ->
    case erlang:element(2, State) of
        none ->
            handle_yielder_start_with_state(State);

        {some, Owner} ->
            handle_yielder_next_with_state(Owner, State)
    end.

-file("src/dream_http_client/client.gleam", 1421).
-spec create_plain_yielder(gleam@http@request:request(binary()), integer()) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_plain_yielder(Http_request, Timeout_value) ->
    Initial_state = {yielder_state, none, Http_request, Timeout_value},
    gleam@yielder:unfold(Initial_state, fun handle_yielder_unfold_with_deps/1).

-file("src/dream_http_client/client.gleam", 1651).
-spec save_streaming_recording(
    recording_yielder_state(),
    list(dream_http_client@recording:chunk())
) -> nil.
save_streaming_recording(State, Chunks) ->
    Ordered_chunks = lists:reverse(Chunks),
    Status = case gleam@list:any(
        erlang:element(7, State),
        fun(H) ->
            string:lowercase(erlang:element(1, H)) =:= <<"content-range"/utf8>>
        end
    ) of
        true ->
            206;

        false ->
            200
    end,
    Response = {streaming_response,
        Status,
        erlang:element(7, State),
        Ordered_chunks},
    Rec = {recording, erlang:element(6, State), Response},
    dream_http_client@recorder:add_recording(erlang:element(5, State), Rec).

-file("src/dream_http_client/client.gleam", 1547).
-spec get_time_ms() -> integer().
get_time_ms() ->
    Native = erlang:monotonic_time(),
    erlang:convert_time_unit(
        Native,
        erlang:binary_to_atom(<<"native"/utf8>>),
        erlang:binary_to_atom(<<"millisecond"/utf8>>)
    ).

-file("src/dream_http_client/client.gleam", 1614).
-spec handle_recording_yielder_next(
    gleam@dynamic:dynamic_(),
    recording_yielder_state()
) -> gleam@yielder:step({ok, gleam@bytes_tree:bytes_tree()} | {error, binary()}, recording_yielder_state()).
handle_recording_yielder_next(Owner, State) ->
    Now = get_time_ms(),
    case dream_http_client@internal:receive_next(
        Owner,
        erlang:element(4, State)
    ) of
        {ok, {some, Bin}} ->
            Delay = case erlang:element(9, State) of
                {some, Last_time} ->
                    Now - Last_time;

                none ->
                    0
            end,
            Chunk = {chunk, Bin, Delay},
            New_state = {recording_yielder_state,
                erlang:element(2, State),
                erlang:element(3, State),
                erlang:element(4, State),
                erlang:element(5, State),
                erlang:element(6, State),
                erlang:element(7, State),
                [Chunk | erlang:element(8, State)],
                {some, Now}},
            {next, {ok, gleam@bytes_tree:from_bit_array(Bin)}, New_state};

        {ok, none} ->
            save_streaming_recording(State, erlang:element(8, State)),
            done;

        {error, Error_reason} ->
            save_streaming_recording(State, erlang:element(8, State)),
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1566).
-spec handle_recording_yielder_start(recording_yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, recording_yielder_state()).
handle_recording_yielder_start(State) ->
    Request_result = dream_http_client@internal:start_httpc_stream(
        erlang:element(3, State),
        erlang:element(4, State)
    ),
    Owner = dream_http_client@internal:extract_owner_pid(Request_result),
    Start_headers = case dream_http_client@internal:get_stream_start_headers(
        Owner,
        erlang:element(4, State)
    ) of
        {ok, Headers} ->
            Headers;

        {error, Reason} ->
            gleam_stdlib:println_error(
                <<"Failed to fetch stream_start headers for recording: "/utf8,
                    Reason/binary>>
            ),
            []
    end,
    Now = get_time_ms(),
    case dream_http_client@internal:receive_next(
        Owner,
        erlang:element(4, State)
    ) of
        {ok, {some, Bin}} ->
            Chunk = {chunk, Bin, 0},
            New_state = {recording_yielder_state,
                {some, Owner},
                erlang:element(3, State),
                erlang:element(4, State),
                erlang:element(5, State),
                erlang:element(6, State),
                Start_headers,
                [Chunk],
                {some, Now}},
            {next, {ok, gleam@bytes_tree:from_bit_array(Bin)}, New_state};

        {ok, none} ->
            save_streaming_recording(
                {recording_yielder_state,
                    erlang:element(2, State),
                    erlang:element(3, State),
                    erlang:element(4, State),
                    erlang:element(5, State),
                    erlang:element(6, State),
                    Start_headers,
                    erlang:element(8, State),
                    erlang:element(9, State)},
                []
            ),
            done;

        {error, Error_reason} ->
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1557).
-spec handle_recording_yielder_unfold(recording_yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, recording_yielder_state()).
handle_recording_yielder_unfold(State) ->
    case erlang:element(2, State) of
        none ->
            handle_recording_yielder_start(State);

        {some, Owner} ->
            handle_recording_yielder_next(Owner, State)
    end.

-file("src/dream_http_client/client.gleam", 1392).
-spec stream_yielder_with_record_mode(
    client_request(),
    dream_http_client@recorder:recorder(),
    gleam@http@request:request(binary()),
    integer()
) -> gleam@yielder:yielder({ok, gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
stream_yielder_with_record_mode(
    Client_request,
    Recorder_instance,
    Http_request,
    Timeout_value
) ->
    case dream_http_client@recorder:is_record_mode(Recorder_instance) of
        true ->
            Recorded_request = client_request_to_recorded_request(
                Client_request
            ),
            Initial_state = {recording_yielder_state,
                none,
                Http_request,
                Timeout_value,
                Recorder_instance,
                Recorded_request,
                [],
                [],
                none},
            gleam@yielder:unfold(
                Initial_state,
                fun handle_recording_yielder_unfold/1
            );

        false ->
            create_plain_yielder(Http_request, Timeout_value)
    end.

-file("src/dream_http_client/client.gleam", 1374).
-spec create_stream_yielder_from_client_request(client_request()) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_stream_yielder_from_client_request(Client_request) ->
    Http_request = to_http_request(Client_request),
    Timeout_value = resolve_timeout(Client_request),
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            stream_yielder_with_record_mode(
                Client_request,
                Recorder_instance,
                Http_request,
                Timeout_value
            );

        none ->
            create_plain_yielder(Http_request, Timeout_value)
    end.

-file("src/dream_http_client/client.gleam", 1438).
-spec convert_chunk_to_result(dream_http_client@recording:chunk()) -> {ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}.
convert_chunk_to_result(Chunk) ->
    Data = gleam@bytes_tree:from_bit_array(erlang:element(2, Chunk)),
    {ok, Data}.

-file("src/dream_http_client/client.gleam", 1430).
-spec create_yielder_from_chunks(list(dream_http_client@recording:chunk())) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_yielder_from_chunks(Chunks) ->
    _pipe = Chunks,
    _pipe@1 = gleam@yielder:from_list(_pipe),
    gleam@yielder:map(_pipe@1, fun convert_chunk_to_result/1).

-file("src/dream_http_client/client.gleam", 1360).
-spec create_yielder_from_recorded_response(
    dream_http_client@recording:recorded_response()
) -> gleam@yielder:yielder({ok, gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_yielder_from_recorded_response(Response) ->
    case Response of
        {streaming_response, _, _, Chunks} ->
            create_yielder_from_chunks(Chunks);

        {blocking_response, _, _, Body} ->
            Chunk = gleam@bytes_tree:from_bit_array(<<Body/binary>>),
            gleam@yielder:single({ok, Chunk})
    end.

-file("src/dream_http_client/client.gleam", 1346).
-spec stream_yielder_with_recorder(
    client_request(),
    dream_http_client@recorder:recorder()
) -> gleam@yielder:yielder({ok, gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
stream_yielder_with_recorder(Client_request, Recorder_instance) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    case dream_http_client@recorder:find_recording(
        Recorder_instance,
        Recorded_request
    ) of
        {ok, {some, {recording, _, Response}}} ->
            create_yielder_from_recorded_response(Response);

        {ok, none} ->
            create_stream_yielder_from_client_request(Client_request);

        {error, Reason} ->
            gleam@yielder:single({error, Reason})
    end.

-file("src/dream_http_client/client.gleam", 1336).
?DOC(
    " Stream HTTP response chunks using a yielder\n"
    "\n"
    " Sends an HTTP request and returns a yielder that produces chunks of the\n"
    " response body as they arrive from the server. This allows you to process\n"
    " large responses incrementally without loading the entire response into memory.\n"
    "\n"
    " **Use this for simple sequential streaming:**\n"
    " - AI/LLM inference endpoints (stream tokens)\n"
    " - Simple file downloads\n"
    " - Scripts or one-off operations\n"
    "\n"
    " **For OTP actors with concurrency, use `start_stream()` instead.**\n"
    "\n"
    " ## Recording and Playback\n"
    "\n"
    " When a recorder is attached (via `recorder()`), this function fully supports\n"
    " both recording and playback:\n"
    "\n"
    " - **Record mode**: Streams from the real server and records chunks to disk,\n"
    "   capturing timing information between chunks for realistic replay.\n"
    " - **Playback mode**: Yields recorded chunks from the fixture file. No network\n"
    "   calls are made.\n"
    "\n"
    " The same `StreamingResponse` fixture format is shared with `start_stream()`,\n"
    " so recordings made with either function can be played back by both.\n"
    "\n"
    " ## Error Semantics\n"
    "\n"
    " The yielder produces `Result(BytesTree, String)` for each chunk:\n"
    " - `Ok(chunk)` - Successful chunk, more may follow\n"
    " - `Error(reason)` - **Terminal error**, stream is done\n"
    "\n"
    " After an `Error`, the yielder immediately returns `Done` on the next call.\n"
    " This design reflects that HTTP stream errors (timeouts, connection drops,\n"
    " etc.) are **not recoverable** - you cannot continue reading from a broken stream.\n"
    "\n"
    " **Normal stream completion**: When the stream finishes successfully, the yielder\n"
    " returns `Done` (no more items). The stream does NOT yield an error for normal completion.\n"
    "\n"
    " Possible error reasons (actual errors only):\n"
    " - `\"timeout\"` - Request timed out\n"
    " - Connection errors from `httpc`\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The configured HTTP request\n"
    "\n"
    " ## Returns\n"
    "\n"
    " A `Yielder` that produces `Result(BytesTree, String)`. Always check each\n"
    " result - errors are terminal and mean the stream has ended.\n"
    "\n"
    " ## Examples\n"
    "\n"
    " **Streaming and processing chunks as they arrive:**\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, stream_yielder}\n"
    " import gleam/yielder.{each}\n"
    " import gleam/bytes_tree.{to_string}\n"
    " import gleam/io.{print, println_error}\n"
    "\n"
    " client.new()\n"
    "   |> host(\"api.openai.com\")\n"
    "   |> path(\"/v1/chat/completions\")\n"
    "   |> stream_yielder()\n"
    "   |> each(fn(result) {\n"
    "     case result {\n"
    "       Ok(chunk) -> print(to_string(chunk))\n"
    "       Error(error_reason) -> {\n"
    "         println_error(\"Stream error: \" <> error_reason)\n"
    "         // Stream is now done, no more chunks will arrive\n"
    "       }\n"
    "     }\n"
    "   })\n"
    " ```\n"
    "\n"
    " **Collecting all chunks into a list:**\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, stream_yielder}\n"
    " import gleam/yielder\n"
    " import gleam/list\n"
    " import gleam/bytes_tree\n"
    " import gleam/string\n"
    "\n"
    " // The stream automatically completes when done - no need to use take()!\n"
    " let chunks = \n"
    "   client.new()\n"
    "   |> host(\"example.com\")\n"
    "   |> path(\"/data\")\n"
    "   |> stream_yielder()\n"
    "   |> yielder.to_list()\n"
    "\n"
    " // Handle results\n"
    " case list.try_map(chunks, fn(result) { result }) {\n"
    "   Ok(chunk_list) -> {\n"
    "     // Concatenate all chunks\n"
    "     let body = \n"
    "       chunk_list\n"
    "       |> list.map(bytes_tree.to_string)\n"
    "       |> list.map(fn(chunk_result) { result.unwrap(chunk_result, \"\") })\n"
    "       |> string.join(\"\")\n"
    "     Ok(body)\n"
    "   }\n"
    "   Error(error_reason) -> Error(\"Stream failed: \" <> error_reason)\n"
    " }\n"
    " ```\n"
).
-spec stream_yielder(client_request()) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
stream_yielder(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            stream_yielder_with_recorder(Client_request, Recorder_instance);

        none ->
            create_stream_yielder_from_client_request(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 2452).
-spec store_message_stream_recorder(
    request_id(),
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request()
) -> nil.
store_message_stream_recorder(Request_id, Rec, Recorded_req) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_insert(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id,
        Rec,
        Recorded_req,
        [],
        [],
        none
    ).

-file("src/dream_http_client/client.gleam", 1760).
-spec record_message_stream_if_needed(
    request_id(),
    gleam@option:option(dream_http_client@recorder:recorder()),
    dream_http_client@recording:recorded_request()
) -> nil.
record_message_stream_if_needed(Request_id, Recorder_option, Recorded_request) ->
    case Recorder_option of
        {some, Recorder_instance} ->
            case dream_http_client@recorder:is_record_mode(Recorder_instance) of
                true ->
                    store_message_stream_recorder(
                        Request_id,
                        Recorder_instance,
                        Recorded_request
                    );

                false ->
                    nil
            end;

        none ->
            nil
    end.

-file("src/dream_http_client/client.gleam", 1828).
-spec extract_error_reason(gleam@dynamic:dynamic_()) -> {ok, request_id()} |
    {error, binary()}.
extract_error_reason(Result) ->
    Reason_result = gleam@dynamic@decode:run(
        Result,
        gleam@dynamic@decode:at(
            [1],
            {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
        )
    ),
    case Reason_result of
        {ok, Reason_dyn} ->
            Reason = gleam@string:inspect(Reason_dyn),
            {error, <<"Failed to start stream: "/utf8, Reason/binary>>};

        {error, Decode_error} ->
            {error,
                <<<<"Failed to start stream (decode error: "/utf8,
                        (gleam@string:inspect(Decode_error))/binary>>/binary,
                    ")"/utf8>>}
    end.

-file("src/dream_http_client/client.gleam", 1819).
-spec extract_request_id(gleam@dynamic:dynamic_()) -> {ok, request_id()} |
    {error, binary()}.
extract_request_id(Result) ->
    Id_result = gleam@dynamic@decode:run(
        Result,
        gleam@dynamic@decode:at(
            [1],
            {decoder, fun gleam@dynamic@decode:decode_string/1}
        )
    ),
    case Id_result of
        {ok, Id_string} ->
            {ok, {request_id, Id_string}};

        {error, Decode_errors} ->
            {error,
                <<"Failed to extract request ID: "/utf8,
                    (gleam@string:inspect(Decode_errors))/binary>>}
    end.

-file("src/dream_http_client/client.gleam", 1807).
-spec parse_stream_start_tag(gleam@dynamic:dynamic_(), gleam@dynamic:dynamic_()) -> {ok,
        request_id()} |
    {error, binary()}.
parse_stream_start_tag(Tag_dyn, Result) ->
    Tag = begin
        _pipe = gleam_erlang_ffi:identity(Tag_dyn),
        erlang:atom_to_binary(_pipe)
    end,
    case Tag of
        <<"ok"/utf8>> ->
            extract_request_id(Result);

        <<"error"/utf8>> ->
            extract_error_reason(Result);

        _ ->
            {error, <<"Unknown response from httpc"/utf8>>}
    end.

-file("src/dream_http_client/client.gleam", 1798).
-spec parse_stream_start_result(gleam@dynamic:dynamic_()) -> {ok, request_id()} |
    {error, binary()}.
parse_stream_start_result(Result) ->
    Tag_result = gleam@dynamic@decode:run(
        Result,
        gleam@dynamic@decode:at(
            [0],
            {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
        )
    ),
    case Tag_result of
        {ok, Tag_dyn} ->
            parse_stream_start_tag(Tag_dyn, Result);

        {error, Decode_errors} ->
            {error,
                <<"Failed to parse httpc response: "/utf8,
                    (gleam@string:inspect(Decode_errors))/binary>>}
    end.

-file("src/dream_http_client/client.gleam", 1725).
-spec send_stream_messages_to_httpc(
    client_request(),
    gleam@option:option(dream_http_client@recorder:recorder()),
    dream_http_client@recording:recorded_request()
) -> {ok, request_id()} | {error, binary()}.
send_stream_messages_to_httpc(Client_request, Recorder_option, Recorded_request) ->
    Http_request = to_http_request(Client_request),
    Url = build_url(Http_request),
    Method_atom = dream_http_client@internal:atomize_method(
        erlang:element(2, Http_request)
    ),
    Body = <<(erlang:element(4, Http_request))/binary>>,
    Caller_process = erlang:self(),
    Timeout_value = resolve_timeout(Client_request),
    Start_result = dream_httpc_shim:request_stream_messages(
        Method_atom,
        Url,
        erlang:element(3, Http_request),
        Body,
        Caller_process,
        Timeout_value
    ),
    case parse_stream_start_result(Start_result) of
        {ok, Request_id} ->
            record_message_stream_if_needed(
                Request_id,
                Recorder_option,
                Recorded_request
            ),
            {ok, Request_id};

        {error, Error_reason} ->
            {error, Error_reason}
    end.

-file("src/dream_http_client/client.gleam", 1718).
-spec stream_messages_without_recorder(client_request()) -> {ok, request_id()} |
    {error, binary()}.
stream_messages_without_recorder(Client_request) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    send_stream_messages_to_httpc(Client_request, none, Recorded_request).

-file("src/dream_http_client/client.gleam", 1694).
-spec stream_messages_with_recorder(
    client_request(),
    dream_http_client@recorder:recorder()
) -> {ok, request_id()} | {error, binary()}.
stream_messages_with_recorder(Client_request, Recorder_instance) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    case dream_http_client@recorder:find_recording(
        Recorder_instance,
        Recorded_request
    ) of
        {ok, {some, _}} ->
            {error,
                <<"Unexpected: recording found in stream_messages path. This should have been handled by start_stream() playback."/utf8>>};

        {ok, none} ->
            send_stream_messages_to_httpc(
                Client_request,
                {some, Recorder_instance},
                Recorded_request
            );

        {error, Reason} ->
            {error, Reason}
    end.

-file("src/dream_http_client/client.gleam", 1686).
-spec stream_messages(client_request()) -> {ok, request_id()} |
    {error, binary()}.
stream_messages(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            stream_messages_with_recorder(Client_request, Recorder_instance);

        none ->
            stream_messages_without_recorder(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 2468).
-spec update_message_stream_recorder(
    request_id(),
    message_stream_recorder_state()
) -> nil.
update_message_stream_recorder(Request_id, State) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_insert(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        erlang:element(6, State)
    ).

-file("src/dream_http_client/client.gleam", 2461).
-spec get_message_stream_recorder(request_id()) -> gleam@option:option(message_stream_recorder_state()).
get_message_stream_recorder(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_lookup(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id
    ).

-file("src/dream_http_client/client.gleam", 2484).
-spec remove_message_stream_recorder(request_id()) -> nil.
remove_message_stream_recorder(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_delete(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id
    ),
    nil.

-file("src/dream_http_client/client.gleam", 2567).
-spec finish_message_stream_recording(
    request_id(),
    message_stream_recorder_state()
) -> nil.
finish_message_stream_recording(Request_id, State) ->
    Ordered_chunks = lists:reverse(erlang:element(5, State)),
    Status = case gleam@list:any(
        erlang:element(4, State),
        fun(H) ->
            string:lowercase(erlang:element(1, H)) =:= <<"content-range"/utf8>>
        end
    ) of
        true ->
            206;

        false ->
            200
    end,
    Response = {streaming_response,
        Status,
        erlang:element(4, State),
        Ordered_chunks},
    Rec = {recording, erlang:element(3, State), Response},
    dream_http_client@recorder:add_recording(erlang:element(2, State), Rec),
    remove_message_stream_recorder(Request_id).

-file("src/dream_http_client/client.gleam", 2490).
-spec record_stream_message(stream_message()) -> nil.
record_stream_message(Message) ->
    case Message of
        {chunk, Request_id, Data} ->
            case get_message_stream_recorder(Request_id) of
                {some, State} ->
                    Now = get_time_ms(),
                    Delay = case erlang:element(6, State) of
                        {some, Last_time} ->
                            Now - Last_time;

                        none ->
                            0
                    end,
                    Chunk = {chunk, Data, Delay},
                    New_state = {message_stream_recorder_state,
                        erlang:element(2, State),
                        erlang:element(3, State),
                        erlang:element(4, State),
                        [Chunk | erlang:element(5, State)],
                        {some, Now}},
                    update_message_stream_recorder(Request_id, New_state);

                none ->
                    nil
            end;

        {stream_end, Request_id@1, Headers} ->
            case get_message_stream_recorder(Request_id@1) of
                {some, State@1} ->
                    Header_tuples = headers_to_tuples(Headers),
                    Final_headers = case Header_tuples =:= [] of
                        true ->
                            erlang:element(4, State@1);

                        false ->
                            Header_tuples
                    end,
                    Updated = {message_stream_recorder_state,
                        erlang:element(2, State@1),
                        erlang:element(3, State@1),
                        Final_headers,
                        erlang:element(5, State@1),
                        erlang:element(6, State@1)},
                    finish_message_stream_recording(Request_id@1, Updated);

                none ->
                    nil
            end;

        {stream_error, Request_id@2, Error_reason} ->
            {request_id, Request_id_string} = Request_id@2,
            gleam_stdlib:println_error(
                <<<<<<"HTTP stream error while recording messages for request "/utf8,
                            Request_id_string/binary>>/binary,
                        ": "/utf8>>/binary,
                    Error_reason/binary>>
            ),
            case get_message_stream_recorder(Request_id@2) of
                {some, State@2} ->
                    finish_message_stream_recording(Request_id@2, State@2);

                none ->
                    nil
            end;

        {stream_start, Request_id@3, Headers@1} ->
            case get_message_stream_recorder(Request_id@3) of
                {some, State@3} ->
                    Header_tuples@1 = headers_to_tuples(Headers@1),
                    New_state@1 = {message_stream_recorder_state,
                        erlang:element(2, State@3),
                        erlang:element(3, State@3),
                        Header_tuples@1,
                        erlang:element(5, State@3),
                        erlang:element(6, State@3)},
                    update_message_stream_recorder(Request_id@3, New_state@1);

                none ->
                    nil
            end;

        {decode_error, Error_reason@1} ->
            gleam_stdlib:println_error(
                <<"Internal DecodeError in HTTP stream message recorder: "/utf8,
                    Error_reason@1/binary>>
            ),
            nil
    end.

-file("src/dream_http_client/client.gleam", 1895).
-spec handle_tag_decode_error(
    list(gleam@dynamic@decode:decode_error()),
    {ok, binary()} | {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
handle_tag_decode_error(Decode_error, Req_id_result) ->
    Error_msg = <<"Internal error: Failed to decode stream message tag: "/utf8,
        (gleam@string:inspect(Decode_error))/binary>>,
    case Req_id_result of
        {ok, Req_id_string} ->
            Req_id = {request_id, Req_id_string},
            {stream_error, Req_id, Error_msg};

        {error, Req_id_error} ->
            Full_error_msg = <<<<<<Error_msg/binary,
                        " (also failed to decode request ID: "/utf8>>/binary,
                    (gleam@string:inspect(Req_id_error))/binary>>/binary,
                ")"/utf8>>,
            {decode_error, Full_error_msg}
    end.

-file("src/dream_http_client/client.gleam", 2057).
-spec decode_error_reason(request_id(), gleam@dynamic:dynamic_()) -> stream_message().
decode_error_reason(Req_id, Reason_dyn) ->
    case gleam@dynamic@decode:run(
        Reason_dyn,
        {decoder, fun gleam@dynamic@decode:decode_string/1}
    ) of
        {ok, Reason} ->
            {stream_error, Req_id, Reason};

        {error, _} ->
            case gleam@dynamic@decode:run(
                Reason_dyn,
                {decoder, fun gleam@dynamic@decode:decode_bit_array/1}
            ) of
                {ok, Bytes} ->
                    case gleam@bit_array:to_string(Bytes) of
                        {ok, S} ->
                            {stream_error, Req_id, S};

                        {error, _} ->
                            {stream_error,
                                Req_id,
                                gleam@string:inspect(Reason_dyn)}
                    end;

                {error, _} ->
                    {stream_error, Req_id, gleam@string:inspect(Reason_dyn)}
            end
    end.

-file("src/dream_http_client/client.gleam", 2041).
-spec decode_stream_error(
    request_id(),
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_stream_error(Req_id, Data_result) ->
    case Data_result of
        {ok, Reason_dyn} ->
            decode_error_reason(Req_id, Reason_dyn);

        {error, Decode_error} ->
            Error_msg = <<<<"Stream error (failed to decode error reason: "/utf8,
                    (gleam@string:inspect(Decode_error))/binary>>/binary,
                ")"/utf8>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 2091).
-spec pair_with_name(binary(), binary()) -> {binary(), binary()}.
pair_with_name(Value, Name) ->
    {Name, Value}.

-file("src/dream_http_client/client.gleam", 2086).
-spec decode_header_value(binary()) -> gleam@dynamic@decode:decoder({binary(),
    binary()}).
decode_header_value(Name) ->
    _pipe = gleam@dynamic@decode:at(
        [1],
        {decoder, fun gleam@dynamic@decode:decode_string/1}
    ),
    gleam@dynamic@decode:map(
        _pipe,
        fun(_capture) -> pair_with_name(_capture, Name) end
    ).

-file("src/dream_http_client/client.gleam", 2075).
-spec decode_headers(gleam@dynamic:dynamic_()) -> {ok,
        list({binary(), binary()})} |
    {error, list(gleam@dynamic@decode:decode_error())}.
decode_headers(Dyn) ->
    Header_decoder = begin
        _pipe = gleam@dynamic@decode:at(
            [0],
            {decoder, fun gleam@dynamic@decode:decode_string/1}
        ),
        gleam@dynamic@decode:then(_pipe, fun decode_header_value/1)
    end,
    gleam@dynamic@decode:run(Dyn, gleam@dynamic@decode:list(Header_decoder)).

-file("src/dream_http_client/client.gleam", 2026).
-spec decode_stream_end_headers(request_id(), gleam@dynamic:dynamic_()) -> stream_message().
decode_stream_end_headers(Req_id, Headers_dyn) ->
    case decode_headers(Headers_dyn) of
        {ok, Headers} ->
            {stream_end, Req_id, tuples_to_headers(Headers)};

        {error, Header_decode_error} ->
            Error_msg = <<"Failed to decode trailing headers in StreamEnd: "/utf8,
                (gleam@string:inspect(Header_decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 2011).
-spec decode_stream_end(
    request_id(),
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_stream_end(Req_id, Data_result) ->
    case Data_result of
        {ok, Headers_dyn} ->
            decode_stream_end_headers(Req_id, Headers_dyn);

        {error, Decode_error} ->
            Error_msg = <<"Failed to get trailing headers data in StreamEnd: "/utf8,
                (gleam@string:inspect(Decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1999).
-spec decode_chunk_data(request_id(), gleam@dynamic:dynamic_()) -> stream_message().
decode_chunk_data(Req_id, Data_dyn) ->
    case gleam@dynamic@decode:run(
        Data_dyn,
        {decoder, fun gleam@dynamic@decode:decode_bit_array/1}
    ) of
        {ok, Data} ->
            {chunk, Req_id, Data};

        {error, Decode_error} ->
            Error_msg = <<"Internal error: Failed to decode chunk data: "/utf8,
                (gleam@string:inspect(Decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1984).
-spec decode_chunk(
    request_id(),
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_chunk(Req_id, Data_result) ->
    case Data_result of
        {ok, Data_dyn} ->
            decode_chunk_data(Req_id, Data_dyn);

        {error, Decode_error} ->
            Error_msg = <<"Internal error: Failed to get chunk data: "/utf8,
                (gleam@string:inspect(Decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1969).
-spec decode_stream_start_headers(request_id(), gleam@dynamic:dynamic_()) -> stream_message().
decode_stream_start_headers(Req_id, Headers_dyn) ->
    case decode_headers(Headers_dyn) of
        {ok, Headers} ->
            {stream_start, Req_id, tuples_to_headers(Headers)};

        {error, Header_decode_error} ->
            Error_msg = <<"Failed to decode headers in StreamStart: "/utf8,
                (gleam@string:inspect(Header_decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1954).
-spec decode_stream_start(
    request_id(),
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_stream_start(Req_id, Data_result) ->
    case Data_result of
        {ok, Headers_dyn} ->
            decode_stream_start_headers(Req_id, Headers_dyn);

        {error, Decode_error} ->
            Error_msg = <<"Failed to get headers data in StreamStart: "/utf8,
                (gleam@string:inspect(Decode_error))/binary>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1939).
-spec decode_by_tag(
    binary(),
    request_id(),
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_by_tag(Tag, Req_id, Data_result) ->
    case Tag of
        <<"stream_start"/utf8>> ->
            decode_stream_start(Req_id, Data_result);

        <<"chunk"/utf8>> ->
            decode_chunk(Req_id, Data_result);

        <<"stream_end"/utf8>> ->
            decode_stream_end(Req_id, Data_result);

        <<"stream_error"/utf8>> ->
            decode_stream_error(Req_id, Data_result);

        _ ->
            {stream_error,
                Req_id,
                <<"Internal error: Unknown stream message tag: "/utf8,
                    Tag/binary>>}
    end.

-file("src/dream_http_client/client.gleam", 1918).
-spec decode_with_tag(
    gleam@dynamic:dynamic_(),
    {ok, binary()} | {error, list(gleam@dynamic@decode:decode_error())},
    {ok, gleam@dynamic:dynamic_()} |
        {error, list(gleam@dynamic@decode:decode_error())}
) -> stream_message().
decode_with_tag(Tag_dyn, Req_id_result, Data_result) ->
    Tag = begin
        _pipe = gleam_erlang_ffi:identity(Tag_dyn),
        erlang:atom_to_binary(_pipe)
    end,
    case Req_id_result of
        {ok, Req_id_string} ->
            Req_id = {request_id, Req_id_string},
            decode_by_tag(Tag, Req_id, Data_result);

        {error, Decode_error} ->
            Error_msg = <<"Internal error: Failed to decode request ID from stream message: "/utf8,
                (gleam@string:inspect(Decode_error))/binary>>,
            {decode_error, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 1883).
-spec decode_simplified_message(gleam@dynamic:dynamic_()) -> stream_message().
decode_simplified_message(Dyn) ->
    Tag_result = gleam@dynamic@decode:run(
        Dyn,
        gleam@dynamic@decode:at(
            [0],
            {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
        )
    ),
    Req_id_result = gleam@dynamic@decode:run(
        Dyn,
        gleam@dynamic@decode:at(
            [1],
            {decoder, fun gleam@dynamic@decode:decode_string/1}
        )
    ),
    Data_result = gleam@dynamic@decode:run(
        Dyn,
        gleam@dynamic@decode:at(
            [2],
            {decoder, fun gleam@dynamic@decode:decode_dynamic/1}
        )
    ),
    case Tag_result of
        {ok, Tag_dyn} ->
            decode_with_tag(Tag_dyn, Req_id_result, Data_result);

        {error, Decode_error} ->
            handle_tag_decode_error(Decode_error, Req_id_result)
    end.

-file("src/dream_http_client/client.gleam", 1868).
-spec apply_mapper_to_dynamic(
    gleam@dynamic:dynamic_(),
    fun((stream_message()) -> JYS)
) -> JYS.
apply_mapper_to_dynamic(Dyn, Mapper) ->
    Simplified = dream_httpc_shim:decode_stream_message_for_selector(Dyn),
    Stream_msg = decode_simplified_message(Simplified),
    record_stream_message(Stream_msg),
    Mapper(Stream_msg).

-file("src/dream_http_client/client.gleam", 1859).
-spec create_selector_mapper(fun((stream_message()) -> JYR)) -> fun((gleam@dynamic:dynamic_()) -> JYR).
create_selector_mapper(Mapper) ->
    fun(_capture) -> apply_mapper_to_dynamic(_capture, Mapper) end.

-file("src/dream_http_client/client.gleam", 1847).
-spec select_stream_messages(
    gleam@erlang@process:selector(JYO),
    fun((stream_message()) -> JYO)
) -> gleam@erlang@process:selector(JYO).
select_stream_messages(Selector, Mapper) ->
    _pipe = Selector,
    gleam@erlang@process:select_record(
        _pipe,
        erlang:binary_to_atom(<<"http"/utf8>>),
        1,
        create_selector_mapper(Mapper)
    ).

-file("src/dream_http_client/client.gleam", 2263).
-spec handle_stream_message(
    stream_message(),
    request_id(),
    client_request(),
    gleam@erlang@process:selector(stream_message()),
    integer()
) -> nil.
handle_stream_message(Message, Req_id, Request, Selector, Timeout_ms) ->
    case Message of
        {stream_start, Stream_req_id, Headers} ->
            case Stream_req_id =:= Req_id of
                true ->
                    case erlang:element(12, Request) of
                        {some, On_start} ->
                            On_start(Headers);

                        none ->
                            nil
                    end,
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms);

                false ->
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms)
            end;

        {chunk, Stream_req_id@1, Data} ->
            case Stream_req_id@1 =:= Req_id of
                true ->
                    case erlang:element(13, Request) of
                        {some, On_chunk} ->
                            On_chunk(Data);

                        none ->
                            nil
                    end,
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms);

                false ->
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms)
            end;

        {stream_end, Stream_req_id@2, Headers@1} ->
            case Stream_req_id@2 =:= Req_id of
                true ->
                    case erlang:element(14, Request) of
                        {some, On_end} ->
                            On_end(Headers@1);

                        none ->
                            nil
                    end,
                    nil;

                false ->
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms)
            end;

        {stream_error, Stream_req_id@3, Reason} ->
            case Stream_req_id@3 =:= Req_id of
                true ->
                    case erlang:element(15, Request) of
                        {some, On_error} ->
                            On_error(Reason);

                        none ->
                            nil
                    end,
                    nil;

                false ->
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms)
            end;

        {decode_error, Reason@1} ->
            case erlang:element(15, Request) of
                {some, On_error@1} ->
                    On_error@1(<<"DecodeError: "/utf8, Reason@1/binary>>);

                none ->
                    nil
            end,
            nil
    end.

-file("src/dream_http_client/client.gleam", 2243).
-spec process_stream_loop(
    gleam@erlang@process:selector(stream_message()),
    request_id(),
    client_request(),
    integer()
) -> nil.
process_stream_loop(Selector, Req_id, Request, Timeout_ms) ->
    case gleam_erlang_ffi:select(Selector, Timeout_ms) of
        {ok, Message} ->
            handle_stream_message(
                Message,
                Req_id,
                Request,
                Selector,
                Timeout_ms
            );

        {error, nil} ->
            case erlang:element(15, Request) of
                {some, On_error} ->
                    On_error(<<"Timeout waiting for stream messages"/utf8>>);

                none ->
                    nil
            end
    end.

-file("src/dream_http_client/client.gleam", 2205).
?DOC(
    " Replay a recorded response by directly invoking the stream callbacks.\n"
    " Handles both StreamingResponse (multiple chunks) and BlockingResponse\n"
    " (body delivered as a single chunk).\n"
).
-spec replay_recorded_stream(
    client_request(),
    dream_http_client@recording:recorded_response()
) -> nil.
replay_recorded_stream(Request, Response) ->
    case Response of
        {streaming_response, _, Headers, Chunks} ->
            case erlang:element(12, Request) of
                {some, Cb} ->
                    Cb(
                        gleam@list:map(
                            Headers,
                            fun(H) ->
                                {header,
                                    erlang:element(1, H),
                                    erlang:element(2, H)}
                            end
                        )
                    );

                none ->
                    nil
            end,
            gleam@list:each(
                Chunks,
                fun(Chunk) -> case erlang:element(13, Request) of
                        {some, Cb@1} ->
                            Cb@1(erlang:element(2, Chunk));

                        none ->
                            nil
                    end end
            ),
            case erlang:element(14, Request) of
                {some, Cb@2} ->
                    Cb@2([]);

                none ->
                    nil
            end;

        {blocking_response, _, Headers@1, Body} ->
            case erlang:element(12, Request) of
                {some, Cb@3} ->
                    Cb@3(
                        gleam@list:map(
                            Headers@1,
                            fun(H@1) ->
                                {header,
                                    erlang:element(1, H@1),
                                    erlang:element(2, H@1)}
                            end
                        )
                    );

                none ->
                    nil
            end,
            case erlang:element(13, Request) of
                {some, Cb@4} ->
                    Cb@4(<<Body/binary>>);

                none ->
                    nil
            end,
            case erlang:element(14, Request) of
                {some, Cb@5} ->
                    Cb@5([]);

                none ->
                    nil
            end
    end.

-file("src/dream_http_client/client.gleam", 2186).
?DOC(
    " Check if a matching recording exists and replay it via callbacks.\n"
    " Returns True if playback was handled, False if the caller should\n"
    " proceed with a real HTTP stream.\n"
).
-spec maybe_replay_from_recording(client_request()) -> boolean().
maybe_replay_from_recording(Request) ->
    case erlang:element(11, Request) of
        {some, Rec} ->
            Recorded_request = client_request_to_recorded_request(Request),
            case dream_http_client@recorder:find_recording(
                Rec,
                Recorded_request
            ) of
                {ok, {some, {recording, _, Response}}} ->
                    replay_recorded_stream(Request, Response),
                    true;

                _ ->
                    false
            end;

        none ->
            false
    end.

-file("src/dream_http_client/client.gleam", 2153).
-spec run_stream_process(client_request()) -> nil.
run_stream_process(Request) ->
    case maybe_replay_from_recording(Request) of
        true ->
            nil;

        false ->
            Selector = begin
                _pipe = gleam_erlang_ffi:new_selector(),
                select_stream_messages(_pipe, fun(Msg) -> Msg end)
            end,
            Timeout_ms = resolve_timeout(Request),
            case stream_messages(Request) of
                {error, Reason} ->
                    case erlang:element(15, Request) of
                        {some, On_error} ->
                            On_error(Reason);

                        none ->
                            nil
                    end;

                {ok, Req_id} ->
                    process_stream_loop(Selector, Req_id, Request, Timeout_ms)
            end
    end.

-file("src/dream_http_client/client.gleam", 2147).
?DOC(
    " Start an HTTP stream with callback handlers\n"
    "\n"
    " Spawns a dedicated process to handle HTTP streaming and calls your callbacks\n"
    " as messages arrive. This is the recommended API for streaming in OTP\n"
    " applications and concurrent contexts.\n"
    "\n"
    " Returns a `StreamHandle` immediately (non-blocking). The stream runs in a\n"
    " separate process, and your callbacks execute in that process.\n"
    "\n"
    " ## Recording and Playback\n"
    "\n"
    " When a recorder is attached (via `recorder()`), this function fully supports\n"
    " both recording and playback:\n"
    "\n"
    " - **Record mode**: Streams from the real server and records chunks to disk.\n"
    "   The recorded fixture captures each chunk along with timing information.\n"
    " - **Playback mode**: Replays recorded chunks directly via your callbacks —\n"
    "   `on_stream_start`, `on_stream_chunk`, and `on_stream_end` are called in\n"
    "   sequence with the recorded data. No network calls are made.\n"
    "\n"
    " The same `StreamingResponse` fixture format is shared with `stream_yielder()`,\n"
    " so recordings made with either function can be played back by both.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request`: The configured HTTP request with callbacks set via builder pattern\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(StreamHandle)`: Stream started successfully\n"
    " - `Error(String)`: Failed to start stream\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(stream) = client.new()\n"
    "   |> client.host(\"api.openai.com\")\n"
    "   |> client.path(\"/v1/chat/completions\")\n"
    "   |> client.on_stream_chunk(fn(data) {\n"
    "     case bit_array.to_string(data) {\n"
    "       Ok(text) -> io.print(text)\n"
    "       Error(_) -> Nil\n"
    "     }\n"
    "   })\n"
    "   |> client.on_stream_error(fn(reason) {\n"
    "     io.println_error(\"Error: \" <> reason)\n"
    "   })\n"
    "   |> client.start_stream()\n"
    "\n"
    " // Later: cancel if needed\n"
    " client.cancel_stream_handle(stream)\n"
    " ```\n"
).
-spec start_stream(client_request()) -> {ok, stream_handle()} |
    {error, binary()}.
start_stream(Request) ->
    Stream_pid = proc_lib:spawn(fun() -> run_stream_process(Request) end),
    {ok, {stream_handle, Stream_pid}}.

-file("src/dream_http_client/client.gleam", 2345).
?DOC(
    " Cancel a stream started with start_stream()\n"
    "\n"
    " Stops the stream process and cancels the underlying HTTP request.\n"
    " Safe to call multiple times on the same handle.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(stream) = client.start_stream(request)\n"
    " // Later:\n"
    " client.cancel_stream_handle(stream)\n"
    " ```\n"
).
-spec cancel_stream_handle(stream_handle()) -> nil.
cancel_stream_handle(Handle) ->
    {stream_handle, Pid} = Handle,
    gleam@erlang@process:kill(Pid).

-file("src/dream_http_client/client.gleam", 2363).
?DOC(
    " Check if a stream is still active\n"
    "\n"
    " Returns True if the stream process is still running, False otherwise.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(stream) = client.start_stream(request)\n"
    " case client.is_stream_active(stream) {\n"
    "   True -> io.println(\"Stream still running\")\n"
    "   False -> io.println(\"Stream completed\")\n"
    " }\n"
    " ```\n"
).
-spec is_stream_active(stream_handle()) -> boolean().
is_stream_active(Handle) ->
    {stream_handle, Pid} = Handle,
    erlang:is_process_alive(Pid).

-file("src/dream_http_client/client.gleam", 2385).
?DOC(
    " Wait for a stream to complete\n"
    "\n"
    " Blocks until the stream process exits. Use this when you need to wait\n"
    " for the stream to finish before continuing.\n"
    "\n"
    " Returns Ok(Nil) when stream completes.\n"
    "\n"
    " For timeout behavior, use cancel_stream_handle() with a timer, or\n"
    " implement your own timeout logic.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " let assert Ok(stream) = client.start_stream(request)\n"
    " client.await_stream(stream)\n"
    " io.println(\"Stream finished\")\n"
    " ```\n"
).
-spec await_stream(stream_handle()) -> nil.
await_stream(Handle) ->
    {stream_handle, Pid} = Handle,
    case erlang:is_process_alive(Pid) of
        true ->
            gleam_erlang_ffi:sleep(50),
            await_stream(Handle);

        false ->
            nil
    end.

-file("src/dream_http_client/client.gleam", 2413).
?DOC(
    " Cancel an active streaming request (low-level API)\n"
    "\n"
    " Cancels an HTTP stream given its `RequestId`.\n"
    "\n"
    " **Note:** Most users should use `start_stream()` and `cancel_stream_handle()`\n"
    " instead. `cancel_stream()` exists primarily to support internal stream\n"
    " machinery and advanced integrations.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request_id`: The request ID for an active internal stream\n"
    "\n"
    " ## Example\n"
    "\n"
    " This is typically not called directly unless you already have a `RequestId`.\n"
).
-spec cancel_stream(request_id()) -> nil.
cancel_stream(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:cancel_stream_by_string(Id).
