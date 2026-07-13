{application, dream_http_client, [
    {vsn, "3.0.1"},
    {applications, [gleam_crypto,
                    gleam_erlang,
                    gleam_http,
                    gleam_json,
                    gleam_otp,
                    gleam_stdlib,
                    gleam_yielder,
                    gleeunit,
                    simplifile]},
    {description, "Type-safe HTTP client for Gleam with streaming support"},
    {modules, [dream_http_client@client,
               dream_http_client@matching,
               dream_http_client@recorder,
               dream_http_client@recording,
               dream_http_client@storage]},
    {registered, []}
]}.
