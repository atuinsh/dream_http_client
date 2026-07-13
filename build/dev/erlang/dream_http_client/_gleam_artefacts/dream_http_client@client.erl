-module(dream_http_client@client).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/dream_http_client/client.gleam").
-export([method/2, scheme/2, host/2, port/2, path/2, 'query'/2, headers/2, body/2, recorder/2, timeout/2, on_stream_start/2, on_stream_chunk/2, on_stream_end/2, on_stream_error/2, add_header/3, get_method/1, get_scheme/1, get_host/1, get_port/1, get_path/1, get_query/1, get_headers/1, get_body/1, get_timeout/1, get_recorder/1, send/1, send_with_status/1, stream_yielder/1, start_stream/1, cancel_stream_handle/1, is_stream_active/1, await_stream/1, cancel_stream/1]).
-export_type([header/0, client_request/0, request_id/0, stream_message/0, stream_handle/0, yielder_state/0, recording_yielder_state/0, message_stream_recorder_state/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Type-safe HTTP client with streaming support\n"
    "\n"
    " Gleam doesn't have a built-in HTTPS client, so this module wraps Erlang's battle-hardened\n"
    " `httpc`. Use this for calling external APIs, downloading files, streaming AI responses,\n"
    " or building OTP-compatible services with concurrent HTTP streams.\n"
    "\n"
    " ## Quick Example - Blocking Request\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, add_header, send}\n"
    "\n"
    " pub fn call_api() {\n"
    "   let result = client.new\n"
    "     |> host(\"api.example.com\")\n"
    "     |> path(\"/users/123\")\n"
    "     |> add_header(\"Authorization\", \"Bearer \" <> token)\n"
    "     |> send()\n"
    "\n"
    "   case result {\n"
    "     Ok(body) -> decode_json(body)\n"
    "     Error(msg) -> handle_error(msg)\n"
    "   }\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Execution Modes\n"
    "\n"
    " This module provides three ways to execute HTTP requests:\n"
    "\n"
    " ### 1. Blocking - `client.send()`\n"
    "\n"
    " Get the complete response at once. Perfect for:\n"
    " - JSON API calls\n"
    " - Small files or documents\n"
    " - Any case where you need the full response before processing\n"
    "\n"
    " ### 2. Yielder Streaming - `client.stream_yielder()`\n"
    "\n"
    " Get a `yielder.Yielder` that produces chunks sequentially. Perfect for:\n"
    " - AI/LLM inference endpoints (streaming tokens)\n"
    " - Simple file downloads\n"
    " - Scripts or one-off operations\n"
    "\n"
    " **Note:** This is a pull-based synchronous API. It blocks the calling process\n"
    " while waiting for chunks, making it unsuitable for OTP actors that need to\n"
    " handle multiple concurrent operations.\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, stream_yielder}\n"
    " import gleam/yielder.{each}\n"
    " import gleam/bytes_tree.{to_string}\n"
    " import gleam/io.{print, println_error}\n"
    "\n"
    " client.new\n"
    " |> host(\"api.openai.com\")\n"
    " |> path(\"/v1/chat/completions\")\n"
    " |> stream_yielder()\n"
    " |> each(fn(result) {\n"
    "   case result {\n"
    "     Ok(chunk) -> print(to_string(chunk))\n"
    "     Error(reason) -> println_error(\"Stream error: \" <> reason)\n"
    "   }\n"
    " })\n"
    " ```\n"
    "\n"
    " ### 3. Message-Based Streaming - `client.stream_messages()`\n"
    "\n"
    " Get messages sent to your process mailbox. Perfect for:\n"
    " - OTP actors handling multiple concurrent streams\n"
    " - Long-lived connections that need cancellation\n"
    " - Integration with OTP supervisors and selectors\n"
    "\n"
    " This is a push-based asynchronous API fully compatible with OTP patterns.\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{\n"
    "   type StreamMessage, Chunk, StreamEnd, StreamError, StreamStart,\n"
    "   select_stream_messages\n"
    " }\n"
    " import gleam/otp/actor.{continue}\n"
    " import gleam/erlang/process.{new_selector}\n"
    "\n"
    " pub type Message {\n"
    "   HttpStream(StreamMessage)\n"
    " }\n"
    "\n"
    " fn init_selector() {\n"
    "   new_selector()\n"
    "   |> select_stream_messages(HttpStream)\n"
    " }\n"
    "\n"
    " fn handle_message(msg: Message, state: State) {\n"
    "   case msg {\n"
    "     HttpStream(Chunk(req_id, data)) -> process_chunk(data, state)\n"
    "     HttpStream(StreamEnd(req_id, _)) -> cleanup(req_id, state)\n"
    "     HttpStream(StreamError(req_id, reason)) -> handle_error(req_id, reason, state)\n"
    "     HttpStream(StreamStart(_, _)) -> continue(state)\n"
    "     HttpStream(DecodeError(reason)) -> {\n"
    "       // FFI corruption - report as bug\n"
    "       log_critical_error(\"DecodeError: \" <> reason)\n"
    "       continue(state)\n"
    "     }\n"
    "   }\n"
    " }\n"
    " ```\n"
    "\n"
    " ## Configuration\n"
    "\n"
    " All execution modes support the same builder pattern for configuration:\n"
    " - **Timeouts**: Use `timeout()` to set request timeout (default: 30 seconds)\n"
    " - **Headers**: Use `add_header()` for incremental or `headers()` for batch\n"
    " - **Method/Path/Query**: Standard HTTP request components\n"
    "\n"
    " Example with timeout:\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, timeout, send}\n"
    "\n"
    " client.new\n"
    " |> host(\"slow-api.example.com\")\n"
    " |> timeout(60_000)  // 60 second timeout\n"
    " |> send()\n"
    " ```\n"
    "\n"
    " ## Inspecting Requests\n"
    "\n"
    " The `ClientRequest` type is opaque to ensure API stability. Use getter functions\n"
    " to inspect request properties for logging, testing, or middleware:\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import gleam/io\n"
    "\n"
    " let req = client.new\n"
    "   |> client.host(\"api.example.com\")\n"
    "   |> client.path(\"/users/123\")\n"
    "\n"
    " // Inspect the request before sending\n"
    " io.println(\"Calling: \" <> client.get_host(req) <> client.get_path(req))\n"
    " // Prints: \"Calling: api.example.com/users/123\"\n"
    "\n"
    " let result = client.send(req)\n"
    " ```\n"
    "\n"
    " Available getters: `get_method`, `get_scheme`, `get_host`, `get_port`, `get_path`,\n"
    " `get_query`, `get_headers`, `get_body`, `get_timeout`, `get_recorder`\n"
).

-type header() :: {header, binary(), binary()}.

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
        list(dream_http_client@recording:chunk()),
        gleam@option:option(integer())}.

-type message_stream_recorder_state() :: {message_stream_recorder_state,
        dream_http_client@recorder:recorder(),
        dream_http_client@recording:recorded_request(),
        list(dream_http_client@recording:chunk()),
        gleam@option:option(integer())}.

-file("src/dream_http_client/client.gleam", 307).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 336).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 364).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 394).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 419).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 448).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 480).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 516).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 552).
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
    " import dream_http_client/recorder\n"
    "\n"
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: recorder.match_url_only(),\n"
    " )\n"
    "\n"
    " client.new\n"
    " |> client.host(\"api.example.com\")\n"
    " |> client.recorder(rec)\n"
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

-file("src/dream_http_client/client.gleam", 577).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 604).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 632).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 659).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 686).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 718).
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
    " client.new\n"
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

-file("src/dream_http_client/client.gleam", 747).
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
    " let req = client.new |> client.method(Post)\n"
    " let method = client.get_method(req)\n"
    " // method == Post\n"
    " ```\n"
).
-spec get_method(client_request()) -> gleam@http:method().
get_method(Client_request) ->
    erlang:element(2, Client_request).

-file("src/dream_http_client/client.gleam", 765).
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
    " let req = client.new |> client.scheme(Http)\n"
    " let scheme = client.get_scheme(req)\n"
    " // scheme == Http\n"
    " ```\n"
).
-spec get_scheme(client_request()) -> gleam@http:scheme().
get_scheme(Client_request) ->
    erlang:element(3, Client_request).

-file("src/dream_http_client/client.gleam", 782).
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
    " let req = client.new |> client.host(\"api.example.com\")\n"
    " let host = client.get_host(req)\n"
    " // host == \"api.example.com\"\n"
    " ```\n"
).
-spec get_host(client_request()) -> binary().
get_host(Client_request) ->
    erlang:element(4, Client_request).

-file("src/dream_http_client/client.gleam", 800).
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
    " let req = client.new |> client.port(8080)\n"
    " let port = client.get_port(req)\n"
    " // port == Some(8080)\n"
    " ```\n"
).
-spec get_port(client_request()) -> gleam@option:option(integer()).
get_port(Client_request) ->
    erlang:element(5, Client_request).

-file("src/dream_http_client/client.gleam", 817).
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
    " let req = client.new |> client.path(\"/api/users\")\n"
    " let path = client.get_path(req)\n"
    " // path == \"/api/users\"\n"
    " ```\n"
).
-spec get_path(client_request()) -> binary().
get_path(Client_request) ->
    erlang:element(6, Client_request).

-file("src/dream_http_client/client.gleam", 834).
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
    " let req = client.new |> client.query(\"page=1&limit=10\")\n"
    " let query = client.get_query(req)\n"
    " // query == Some(\"page=1&limit=10\")\n"
    " ```\n"
).
-spec get_query(client_request()) -> gleam@option:option(binary()).
get_query(Client_request) ->
    erlang:element(7, Client_request).

-file("src/dream_http_client/client.gleam", 853).
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
    " let req = client.new\n"
    "   |> client.add_header(\"Authorization\", \"Bearer token\")\n"
    "   |> client.add_header(\"Content-Type\", \"application/json\")\n"
    " let headers = client.get_headers(req)\n"
    " // headers == [Header(\"Content-Type\", \"application/json\"), Header(\"Authorization\", \"Bearer token\")]\n"
    " ```\n"
).
-spec get_headers(client_request()) -> list(header()).
get_headers(Client_request) ->
    erlang:element(8, Client_request).

-file("src/dream_http_client/client.gleam", 870).
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
    " let req = client.new |> client.body(\"{\\\"name\\\": \\\"Alice\\\"}\")\n"
    " let body = client.get_body(req)\n"
    " // body == \"{\\\"name\\\": \\\"Alice\\\"}\"\n"
    " ```\n"
).
-spec get_body(client_request()) -> binary().
get_body(Client_request) ->
    erlang:element(9, Client_request).

-file("src/dream_http_client/client.gleam", 888).
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
    " let req = client.new |> client.timeout(5000)\n"
    " let timeout = client.get_timeout(req)\n"
    " // timeout == Some(5000)\n"
    " ```\n"
).
-spec get_timeout(client_request()) -> gleam@option:option(integer()).
get_timeout(Client_request) ->
    erlang:element(10, Client_request).

-file("src/dream_http_client/client.gleam", 911).
?DOC(
    " Get the recorder from a request\n"
    "\n"
    " Returns the optional recorder attached to the request for recording or playback.\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client\n"
    " import dream_http_client/recorder\n"
    " import dream_http_client/matching\n"
    "\n"
    " let assert Ok(rec) = recorder.start(\n"
    "   mode: recorder.Record(directory: \"mocks\"),\n"
    "   matching: matching.match_url_only(),\n"
    " )\n"
    " let req = client.new |> client.recorder(rec)\n"
    " let recorder_opt = client.get_recorder(req)\n"
    " // recorder_opt == Some(rec)\n"
    " ```\n"
).
-spec get_recorder(client_request()) -> gleam@option:option(dream_http_client@recorder:recorder()).
get_recorder(Client_request) ->
    erlang:element(11, Client_request).

-file("src/dream_http_client/client.gleam", 1212).
-spec convert_string_error(nil) -> binary().
convert_string_error(_) ->
    <<"Failed to convert response to string"/utf8>>.

-file("src/dream_http_client/client.gleam", 1218).
-spec resolve_timeout(client_request()) -> integer().
resolve_timeout(Client_request) ->
    case erlang:element(10, Client_request) of
        {some, Timeout_value} ->
            Timeout_value;

        none ->
            30000
    end.

-file("src/dream_http_client/client.gleam", 1833).
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

-file("src/dream_http_client/client.gleam", 1586).
-spec headers_to_tuples(list(header())) -> list({binary(), binary()}).
headers_to_tuples(Headers) ->
    gleam@list:map(
        Headers,
        fun(H) -> {erlang:element(2, H), erlang:element(3, H)} end
    ).

-file("src/dream_http_client/client.gleam", 1573).
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

-file("src/dream_http_client/client.gleam", 1175).
-spec send_client_request_to_httpc(client_request()) -> {ok, binary()} |
    {error, binary()}.
send_client_request_to_httpc(Client_request) ->
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
        {ok, Response_body} ->
            _pipe = Response_body,
            _pipe@1 = gleam@bit_array:to_string(_pipe),
            gleam@result:map_error(_pipe@1, fun convert_string_error/1);

        {error, Error_message} ->
            {error, Error_message}
    end.

-file("src/dream_http_client/client.gleam", 1100).
-spec send_without_recorder(client_request()) -> {ok, binary()} |
    {error, binary()}.
send_without_recorder(Client_request) ->
    send_client_request_to_httpc(Client_request).

-file("src/dream_http_client/client.gleam", 1150).
-spec record_blocking_response_if_needed(
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request(),
    binary()
) -> nil.
record_blocking_response_if_needed(Recorder_instance, Recorded_request, Body) ->
    case dream_http_client@recorder:is_record_mode(Recorder_instance) of
        true ->
            Recorded_response = {blocking_response, 200, [], Body},
            Recorder_entry = {recording, Recorded_request, Recorded_response},
            dream_http_client@recorder:add_recording(
                Recorder_instance,
                Recorder_entry
            );

        false ->
            nil
    end.

-file("src/dream_http_client/client.gleam", 1132).
-spec send_and_maybe_record(
    client_request(),
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request()
) -> {ok, binary()} | {error, binary()}.
send_and_maybe_record(Client_request, Recorder_instance, Recorded_request) ->
    case send_client_request_to_httpc(Client_request) of
        {ok, Body} ->
            record_blocking_response_if_needed(
                Recorder_instance,
                Recorded_request,
                Body
            ),
            {ok, Body};

        {error, Error_message} ->
            {error, Error_message}
    end.

-file("src/dream_http_client/client.gleam", 1120).
-spec handle_recorded_blocking_response(
    dream_http_client@recording:recorded_response()
) -> {ok, binary()} | {error, binary()}.
handle_recorded_blocking_response(Response) ->
    case Response of
        {blocking_response, _, _, Body} ->
            {ok, Body};

        {streaming_response, _, _, _} ->
            {error,
                <<"Recording contains streaming response, use stream_yielder() instead"/utf8>>}
    end.

-file("src/dream_http_client/client.gleam", 1197).
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

-file("src/dream_http_client/client.gleam", 1106).
-spec send_with_recorder(
    client_request(),
    dream_http_client@recorder:recorder()
) -> {ok, binary()} | {error, binary()}.
send_with_recorder(Client_request, Recorder_instance) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    case dream_http_client@recorder:find_recording(
        Recorder_instance,
        Recorded_request
    ) of
        {some, {recording, _, Response}} ->
            handle_recorded_blocking_response(Response);

        none ->
            send_and_maybe_record(
                Client_request,
                Recorder_instance,
                Recorded_request
            )
    end.

-file("src/dream_http_client/client.gleam", 1092).
?DOC(
    " Make a blocking HTTP request and get the complete response\n"
    "\n"
    " Sends an HTTP request and collects all response chunks, returning the\n"
    " complete response body as a string. This is ideal for:\n"
    "\n"
    " - JSON API responses\n"
    " - Small files or documents\n"
    " - Any case where you need the full response before processing\n"
    "\n"
    " For large responses or when you need OTP compatibility, use\n"
    " `stream_yielder()` or `stream_messages()` instead.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `client_request`: The configured HTTP request\n"
    "\n"
    " ## Returns\n"
    "\n"
    " - `Ok(String)`: The complete response body as a string\n"
    " - `Error(String)`: An error message if the request failed\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, path, add_header, send}\n"
    " import gleam/json.{decode}\n"
    "\n"
    " let result = client.new\n"
    "   |> host(\"api.example.com\")\n"
    "   |> path(\"/users/123\")\n"
    "   |> add_header(\"Authorization\", \"Bearer \" <> token)\n"
    "   |> send()\n"
    "\n"
    " case result {\n"
    "   Ok(body) -> {\n"
    "     case decode(body, user_decoder) {\n"
    "       Ok(user) -> Ok(user)\n"
    "       Error(json_error) ->\n"
    "         Error(\"Invalid JSON response: \" <> string.inspect(json_error))\n"
    "     }\n"
    "   }\n"
    "   Error(error_message) -> Error(\"Request failed: \" <> error_message)\n"
    " }\n"
    " ```\n"
).
-spec send(client_request()) -> {ok, binary()} | {error, binary()}.
send(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            send_with_recorder(Client_request, Recorder_instance);

        none ->
            send_without_recorder(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 1304).
-spec send_with_status_to_httpc(client_request()) -> {ok, {integer(), binary()}} |
    {error, binary()}.
send_with_status_to_httpc(Client_request) ->
    Http_request = to_http_request(Client_request),
    Url = build_url(Http_request),
    Method_atom = dream_http_client@internal:atomize_method(
        erlang:element(2, Http_request)
    ),
    Method_dynamic = gleam_erlang_ffi:identity(Method_atom),
    Body = <<(erlang:element(4, Http_request))/binary>>,
    Timeout_value = resolve_timeout(Client_request),
    case dream_httpc_shim:request_sync_response(
        Method_dynamic,
        Url,
        erlang:element(3, Http_request),
        Body,
        Timeout_value
    ) of
        {ok, {Status, Response_body}} ->
            _pipe = Response_body,
            _pipe@1 = gleam@bit_array:to_string(_pipe),
            _pipe@2 = gleam@result:map_error(
                _pipe@1,
                fun convert_string_error/1
            ),
            gleam@result:map(_pipe@2, fun(Text) -> {Status, Text} end);

        {error, Error_message} ->
            {error, Error_message}
    end.

-file("src/dream_http_client/client.gleam", 1281).
-spec record_status_response_if_needed(
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request(),
    integer(),
    binary()
) -> nil.
record_status_response_if_needed(
    Recorder_instance,
    Recorded_request,
    Status,
    Body
) ->
    case dream_http_client@recorder:is_record_mode(Recorder_instance) of
        true ->
            dream_http_client@recorder:add_recording(
                Recorder_instance,
                {recording,
                    Recorded_request,
                    {blocking_response, Status, [], Body}}
            );

        false ->
            nil
    end.

-file("src/dream_http_client/client.gleam", 1250).
-spec send_with_status_recorder(
    client_request(),
    dream_http_client@recorder:recorder()
) -> {ok, {integer(), binary()}} | {error, binary()}.
send_with_status_recorder(Client_request, Recorder_instance) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    case dream_http_client@recorder:find_recording(
        Recorder_instance,
        Recorded_request
    ) of
        {some, {recording, _, {blocking_response, Status, _, Body}}} ->
            {ok, {Status, Body}};

        {some, {recording, _, {streaming_response, _, _, _}}} ->
            {error,
                <<"Recording contains streaming response, use stream_yielder() instead"/utf8>>};

        none ->
            case send_with_status_to_httpc(Client_request) of
                {ok, {Status@1, Body@1}} ->
                    record_status_response_if_needed(
                        Recorder_instance,
                        Recorded_request,
                        Status@1,
                        Body@1
                    ),
                    {ok, {Status@1, Body@1}};

                {error, Error_message} ->
                    {error, Error_message}
            end
    end.

-file("src/dream_http_client/client.gleam", 1240).
?DOC(
    " Send an HTTP request and return the response status and body\n"
    "\n"
    " Like `send`, but preserves the response status code instead of\n"
    " discarding it. Recorder-aware: a recorded blocking response replays\n"
    " with its stored status, and record mode stores the actual status\n"
    " (unlike `send`'s recordings, which assume 200).\n"
).
-spec send_with_status(client_request()) -> {ok, {integer(), binary()}} |
    {error, binary()}.
send_with_status(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            send_with_status_recorder(Client_request, Recorder_instance);

        none ->
            send_with_status_to_httpc(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 1611).
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

-file("src/dream_http_client/client.gleam", 1594).
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

-file("src/dream_http_client/client.gleam", 1564).
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

-file("src/dream_http_client/client.gleam", 1519).
-spec create_plain_yielder(gleam@http@request:request(binary()), integer()) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_plain_yielder(Http_request, Timeout_value) ->
    Initial_state = {yielder_state, none, Http_request, Timeout_value},
    gleam@yielder:unfold(Initial_state, fun handle_yielder_unfold_with_deps/1).

-file("src/dream_http_client/client.gleam", 1716).
-spec save_streaming_recording(
    recording_yielder_state(),
    list(dream_http_client@recording:chunk())
) -> nil.
save_streaming_recording(State, Chunks) ->
    Ordered_chunks = lists:reverse(Chunks),
    Response = {streaming_response, 200, [], Ordered_chunks},
    Rec = {recording, erlang:element(6, State), Response},
    dream_http_client@recorder:add_recording(erlang:element(5, State), Rec).

-file("src/dream_http_client/client.gleam", 1627).
-spec get_time_ms() -> integer().
get_time_ms() ->
    Native = erlang:monotonic_time(),
    erlang:convert_time_unit(
        Native,
        erlang:binary_to_atom(<<"native"/utf8>>),
        erlang:binary_to_atom(<<"millisecond"/utf8>>)
    ).

-file("src/dream_http_client/client.gleam", 1679).
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
            Delay = case erlang:element(8, State) of
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
                [Chunk | erlang:element(7, State)],
                {some, Now}},
            {next, {ok, gleam@bytes_tree:from_bit_array(Bin)}, New_state};

        {ok, none} ->
            save_streaming_recording(State, erlang:element(7, State)),
            done;

        {error, Error_reason} ->
            save_streaming_recording(State, erlang:element(7, State)),
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1646).
-spec handle_recording_yielder_start(recording_yielder_state()) -> gleam@yielder:step({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}, recording_yielder_state()).
handle_recording_yielder_start(State) ->
    Request_result = dream_http_client@internal:start_httpc_stream(
        erlang:element(3, State),
        erlang:element(4, State)
    ),
    Owner = dream_http_client@internal:extract_owner_pid(Request_result),
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
                [Chunk],
                {some, Now}},
            {next, {ok, gleam@bytes_tree:from_bit_array(Bin)}, New_state};

        {ok, none} ->
            save_streaming_recording(State, []),
            done;

        {error, Error_reason} ->
            {next, {error, Error_reason}, State}
    end.

-file("src/dream_http_client/client.gleam", 1637).
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

-file("src/dream_http_client/client.gleam", 1491).
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
                none},
            gleam@yielder:unfold(
                Initial_state,
                fun handle_recording_yielder_unfold/1
            );

        false ->
            create_plain_yielder(Http_request, Timeout_value)
    end.

-file("src/dream_http_client/client.gleam", 1473).
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

-file("src/dream_http_client/client.gleam", 1536).
-spec convert_chunk_to_result(dream_http_client@recording:chunk()) -> {ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}.
convert_chunk_to_result(Chunk) ->
    Data = gleam@bytes_tree:from_bit_array(erlang:element(2, Chunk)),
    {ok, Data}.

-file("src/dream_http_client/client.gleam", 1528).
-spec create_yielder_from_chunks(list(dream_http_client@recording:chunk())) -> gleam@yielder:yielder({ok,
        gleam@bytes_tree:bytes_tree()} |
    {error, binary()}).
create_yielder_from_chunks(Chunks) ->
    _pipe = Chunks,
    _pipe@1 = gleam@yielder:from_list(_pipe),
    gleam@yielder:map(_pipe@1, fun convert_chunk_to_result/1).

-file("src/dream_http_client/client.gleam", 1459).
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

-file("src/dream_http_client/client.gleam", 1446).
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
        {some, {recording, _, Response}} ->
            create_yielder_from_recorded_response(Response);

        none ->
            create_stream_yielder_from_client_request(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 1436).
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
    " **For OTP actors with concurrency, use `stream_messages()` instead.**\n"
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
    " client.new\n"
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
    "   client.new\n"
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

-file("src/dream_http_client/client.gleam", 1590).
-spec tuples_to_headers(list({binary(), binary()})) -> list(header()).
tuples_to_headers(Tuples) ->
    gleam@list:map(
        Tuples,
        fun(T) -> {header, erlang:element(1, T), erlang:element(2, T)} end
    ).

-file("src/dream_http_client/client.gleam", 2422).
-spec ensure_recorder_table() -> nil.
ensure_recorder_table() ->
    case dream_httpc_shim:ets_table_exists(
        <<"dream_http_client_stream_recorders"/utf8>>
    ) of
        true ->
            nil;

        false ->
            dream_httpc_shim:ets_new(
                <<"dream_http_client_stream_recorders"/utf8>>,
                [erlang:binary_to_atom(<<"set"/utf8>>),
                    erlang:binary_to_atom(<<"public"/utf8>>),
                    erlang:binary_to_atom(<<"named_table"/utf8>>)]
            ),
            nil
    end.

-file("src/dream_http_client/client.gleam", 2458).
-spec store_message_stream_recorder(
    request_id(),
    dream_http_client@recorder:recorder(),
    dream_http_client@recording:recorded_request()
) -> nil.
store_message_stream_recorder(Request_id, Rec, Recorded_req) ->
    ensure_recorder_table(),
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_insert(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id,
        Rec,
        Recorded_req,
        [],
        none
    ).

-file("src/dream_http_client/client.gleam", 1812).
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

-file("src/dream_http_client/client.gleam", 1880).
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

-file("src/dream_http_client/client.gleam", 1871).
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

-file("src/dream_http_client/client.gleam", 1859).
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

-file("src/dream_http_client/client.gleam", 1850).
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

-file("src/dream_http_client/client.gleam", 1777).
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

-file("src/dream_http_client/client.gleam", 1770).
-spec stream_messages_without_recorder(client_request()) -> {ok, request_id()} |
    {error, binary()}.
stream_messages_without_recorder(Client_request) ->
    Recorded_request = client_request_to_recorded_request(Client_request),
    send_stream_messages_to_httpc(Client_request, none, Recorded_request).

-file("src/dream_http_client/client.gleam", 1748).
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
        {some, _} ->
            {error,
                <<"Message-based streaming does not support playback mode. Use stream_yielder() instead."/utf8>>};

        none ->
            send_stream_messages_to_httpc(
                Client_request,
                {some, Recorder_instance},
                Recorded_request
            )
    end.

-file("src/dream_http_client/client.gleam", 1739).
-spec stream_messages(client_request()) -> {ok, request_id()} |
    {error, binary()}.
stream_messages(Client_request) ->
    case erlang:element(11, Client_request) of
        {some, Recorder_instance} ->
            stream_messages_with_recorder(Client_request, Recorder_instance);

        none ->
            stream_messages_without_recorder(Client_request)
    end.

-file("src/dream_http_client/client.gleam", 2490).
-spec remove_message_stream_recorder(request_id()) -> nil.
remove_message_stream_recorder(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_delete(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id
    ),
    nil.

-file("src/dream_http_client/client.gleam", 2554).
-spec finish_message_stream_recording(
    request_id(),
    message_stream_recorder_state()
) -> nil.
finish_message_stream_recording(Request_id, State) ->
    Ordered_chunks = lists:reverse(erlang:element(4, State)),
    Response = {streaming_response, 200, [], Ordered_chunks},
    Rec = {recording, erlang:element(3, State), Response},
    dream_http_client@recorder:add_recording(erlang:element(2, State), Rec),
    remove_message_stream_recorder(Request_id).

-file("src/dream_http_client/client.gleam", 2468).
-spec get_message_stream_recorder(request_id()) -> gleam@option:option(message_stream_recorder_state()).
get_message_stream_recorder(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:ets_lookup(
        <<"dream_http_client_stream_recorders"/utf8>>,
        Id
    ).

-file("src/dream_http_client/client.gleam", 2475).
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
        erlang:element(5, State)
    ).

-file("src/dream_http_client/client.gleam", 2496).
-spec record_stream_message(stream_message()) -> nil.
record_stream_message(Message) ->
    case Message of
        {chunk, Request_id, Data} ->
            case get_message_stream_recorder(Request_id) of
                {some, State} ->
                    Now = get_time_ms(),
                    Delay = case erlang:element(5, State) of
                        {some, Last_time} ->
                            Now - Last_time;

                        none ->
                            0
                    end,
                    Chunk = {chunk, Data, Delay},
                    New_state = {message_stream_recorder_state,
                        erlang:element(2, State),
                        erlang:element(3, State),
                        [Chunk | erlang:element(4, State)],
                        {some, Now}},
                    update_message_stream_recorder(Request_id, New_state);

                none ->
                    nil
            end;

        {stream_end, Request_id@1, _} ->
            case get_message_stream_recorder(Request_id@1) of
                {some, State@1} ->
                    finish_message_stream_recording(Request_id@1, State@1);

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

        {stream_start, _, _} ->
            nil;

        {decode_error, Error_reason@1} ->
            gleam_stdlib:println_error(
                <<"Internal DecodeError in HTTP stream message recorder: "/utf8,
                    Error_reason@1/binary>>
            ),
            nil
    end.

-file("src/dream_http_client/client.gleam", 1947).
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

-file("src/dream_http_client/client.gleam", 2109).
-spec decode_error_reason(request_id(), gleam@dynamic:dynamic_()) -> stream_message().
decode_error_reason(Req_id, Reason_dyn) ->
    case gleam@dynamic@decode:run(
        Reason_dyn,
        {decoder, fun gleam@dynamic@decode:decode_string/1}
    ) of
        {ok, Reason} ->
            {stream_error, Req_id, Reason};

        {error, Decode_error} ->
            Error_msg = <<<<"Stream error (failed to decode error string: "/utf8,
                    (gleam@string:inspect(Decode_error))/binary>>/binary,
                ")"/utf8>>,
            {stream_error, Req_id, Error_msg}
    end.

-file("src/dream_http_client/client.gleam", 2093).
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

-file("src/dream_http_client/client.gleam", 2141).
-spec pair_with_name(binary(), binary()) -> {binary(), binary()}.
pair_with_name(Value, Name) ->
    {Name, Value}.

-file("src/dream_http_client/client.gleam", 2136).
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

-file("src/dream_http_client/client.gleam", 2125).
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

-file("src/dream_http_client/client.gleam", 2078).
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

-file("src/dream_http_client/client.gleam", 2063).
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

-file("src/dream_http_client/client.gleam", 2051).
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

-file("src/dream_http_client/client.gleam", 2036).
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

-file("src/dream_http_client/client.gleam", 2021).
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

-file("src/dream_http_client/client.gleam", 2006).
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

-file("src/dream_http_client/client.gleam", 1991).
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

-file("src/dream_http_client/client.gleam", 1970).
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

-file("src/dream_http_client/client.gleam", 1935).
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

-file("src/dream_http_client/client.gleam", 1920).
-spec apply_mapper_to_dynamic(
    gleam@dynamic:dynamic_(),
    fun((stream_message()) -> BJE)
) -> BJE.
apply_mapper_to_dynamic(Dyn, Mapper) ->
    Simplified = dream_httpc_shim:decode_stream_message_for_selector(Dyn),
    Stream_msg = decode_simplified_message(Simplified),
    record_stream_message(Stream_msg),
    Mapper(Stream_msg).

-file("src/dream_http_client/client.gleam", 1911).
-spec create_selector_mapper(fun((stream_message()) -> BJD)) -> fun((gleam@dynamic:dynamic_()) -> BJD).
create_selector_mapper(Mapper) ->
    fun(_capture) -> apply_mapper_to_dynamic(_capture, Mapper) end.

-file("src/dream_http_client/client.gleam", 1899).
-spec select_stream_messages(
    gleam@erlang@process:selector(BJA),
    fun((stream_message()) -> BJA)
) -> gleam@erlang@process:selector(BJA).
select_stream_messages(Selector, Mapper) ->
    _pipe = Selector,
    gleam@erlang@process:select_record(
        _pipe,
        erlang:binary_to_atom(<<"http"/utf8>>),
        1,
        create_selector_mapper(Mapper)
    ).

-file("src/dream_http_client/client.gleam", 2242).
-spec handle_stream_message(
    stream_message(),
    request_id(),
    client_request(),
    gleam@erlang@process:selector(stream_message())
) -> nil.
handle_stream_message(Message, Req_id, Request, Selector) ->
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
                    process_stream_loop(Selector, Req_id, Request);

                false ->
                    process_stream_loop(Selector, Req_id, Request)
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
                    process_stream_loop(Selector, Req_id, Request);

                false ->
                    process_stream_loop(Selector, Req_id, Request)
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
                    process_stream_loop(Selector, Req_id, Request)
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
                    process_stream_loop(Selector, Req_id, Request)
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

-file("src/dream_http_client/client.gleam", 2223).
-spec process_stream_loop(
    gleam@erlang@process:selector(stream_message()),
    request_id(),
    client_request()
) -> nil.
process_stream_loop(Selector, Req_id, Request) ->
    case gleam_erlang_ffi:select(Selector, 30000) of
        {ok, Message} ->
            handle_stream_message(Message, Req_id, Request, Selector);

        {error, nil} ->
            case erlang:element(15, Request) of
                {some, On_error} ->
                    On_error(<<"Timeout waiting for stream messages"/utf8>>);

                none ->
                    nil
            end
    end.

-file("src/dream_http_client/client.gleam", 2201).
-spec run_stream_process(client_request()) -> nil.
run_stream_process(Request) ->
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        select_stream_messages(_pipe, fun(Msg) -> Msg end)
    end,
    case stream_messages(Request) of
        {error, Reason} ->
            case erlang:element(15, Request) of
                {some, On_error} ->
                    On_error(Reason);

                none ->
                    nil
            end;

        {ok, Req_id} ->
            process_stream_loop(Selector, Req_id, Request)
    end.

-file("src/dream_http_client/client.gleam", 2193).
-spec ensure_ets_tables() -> nil.
ensure_ets_tables() ->
    ensure_recorder_table(),
    dream_httpc_shim:ensure_ref_mapping_table().

-file("src/dream_http_client/client.gleam", 2182).
?DOC(
    " Start an HTTP stream with callback handlers\n"
    "\n"
    " Spawns a dedicated process to handle HTTP streaming and calls your callbacks\n"
    " as messages arrive. This is the recommended API for streaming.\n"
    "\n"
    " Returns a `StreamHandle` immediately (non-blocking). The stream runs in a\n"
    " separate process, and your callbacks execute in that process.\n"
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
    " let assert Ok(stream) = client.new\n"
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
    ensure_ets_tables(),
    Stream_pid = proc_lib:spawn(fun() -> run_stream_process(Request) end),
    {ok, {stream_handle, Stream_pid}}.

-file("src/dream_http_client/client.gleam", 2323).
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

-file("src/dream_http_client/client.gleam", 2341).
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

-file("src/dream_http_client/client.gleam", 2363).
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

-file("src/dream_http_client/client.gleam", 2400).
?DOC(
    " Cancel an active streaming request (low-level API)\n"
    "\n"
    " Cancels an HTTP stream that was started with `stream_messages()`.\n"
    " After cancellation, no more messages will be sent to your process.\n"
    "\n"
    " **Note:** This is a low-level API. Most users should use `start_stream()`\n"
    " and `cancel_stream_handle()` instead.\n"
    "\n"
    " ## Parameters\n"
    "\n"
    " - `request_id`: The request ID returned from `stream_messages()`\n"
    "\n"
    " ## Example\n"
    "\n"
    " ```gleam\n"
    " import dream_http_client/client.{host, stream_messages, cancel_stream}\n"
    "\n"
    " let assert Ok(req_id) = client.new\n"
    "   |> host(\"api.example.com\")\n"
    "   |> stream_messages()\n"
    "\n"
    " // Later, cancel the stream\n"
    " cancel_stream(req_id)\n"
    " ```\n"
).
-spec cancel_stream(request_id()) -> nil.
cancel_stream(Request_id) ->
    {request_id, Id} = Request_id,
    dream_httpc_shim:cancel_stream_by_string(Id).
