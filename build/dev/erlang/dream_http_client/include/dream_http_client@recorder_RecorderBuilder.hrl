-record(recorder_builder, {
    mode :: binary(),
    directory :: gleam@option:option(binary()),
    key :: fun((dream_http_client@recording:recorded_request()) -> binary()),
    request_transformer :: fun((dream_http_client@recording:recorded_request()) -> dream_http_client@recording:recorded_request()),
    response_transformer :: fun((dream_http_client@recording:recorded_request(), dream_http_client@recording:recorded_response()) -> dream_http_client@recording:recorded_response())
}).
