-record(blocking_response, {
    status :: integer(),
    headers :: list({binary(), binary()}),
    body :: binary()
}).
