-record(client_request, {
    method :: gleam@http:method(),
    scheme :: gleam@http:scheme(),
    host :: binary(),
    port :: gleam@option:option(integer()),
    path :: binary(),
    'query' :: gleam@option:option(binary()),
    headers :: list(dream_http_client@client:header()),
    body :: binary(),
    timeout :: gleam@option:option(integer()),
    recorder :: gleam@option:option(dream_http_client@recorder:recorder()),
    on_stream_start :: gleam@option:option(fun((list(dream_http_client@client:header())) -> nil)),
    on_stream_chunk :: gleam@option:option(fun((bitstring()) -> nil)),
    on_stream_end :: gleam@option:option(fun((list(dream_http_client@client:header())) -> nil)),
    on_stream_error :: gleam@option:option(fun((binary()) -> nil))
}).
