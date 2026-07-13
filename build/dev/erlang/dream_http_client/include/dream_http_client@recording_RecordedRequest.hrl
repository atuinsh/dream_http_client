-record(recorded_request, {
    method :: gleam@http:method(),
    scheme :: gleam@http:scheme(),
    host :: binary(),
    port :: gleam@option:option(integer()),
    path :: binary(),
    'query' :: gleam@option:option(binary()),
    headers :: list({binary(), binary()}),
    body :: binary()
}).
