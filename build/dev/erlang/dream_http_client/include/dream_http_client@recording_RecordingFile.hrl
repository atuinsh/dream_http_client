-record(recording_file, {
    version :: binary(),
    entries :: list(dream_http_client@recording:recording())
}).
