-record(streaming_response, {
    status :: integer(),
    headers :: list({binary(), binary()}),
    chunks :: list(dream_http_client@recording:chunk())
}).
