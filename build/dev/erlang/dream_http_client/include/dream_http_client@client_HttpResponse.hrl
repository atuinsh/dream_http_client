-record(http_response, {
    status :: integer(),
    headers :: list(dream_http_client@client:header()),
    body :: binary()
}).
