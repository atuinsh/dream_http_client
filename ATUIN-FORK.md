# atuinsh fork of dream_http_client

Extracted from the [TrustBound/dream](https://github.com/TrustBound/dream)
monorepo (`modules/http_client`, MIT) via `git subtree split`, preserving
the module's history. This fork tracks the 5.1.3 release — upstream
monorepo commit `98a7103` — with one delta: the `gleam_stdlib`
requirement is widened to allow 1.x, which upstream caps at `< 1.0.0`.
That widening is proposed upstream as
[TrustBound/dream#69](https://github.com/TrustBound/dream/pull/69); once
it ships in a release, consumers should switch to the hex package and
this fork can be archived.

The 3.0.1-era patches this fork used to carry are gone — upstream
absorbed or obviated all three (the query-string fix in 5.1.2, the
silent-stream-failure fixes in 5.1.1/5.1.3, and `send_with_status`
superseded by 5.0.0's structured `send`).

To pick up a newer upstream release: `git subtree split
--prefix=modules/http_client -b <branch> <upstream-ref>` in a
TrustBound/dream clone, fetch the split branch here, `git merge` it
(shared ancestry is preserved), and re-apply the packaging adaptations
(this file, `gleam.toml`'s repository/stdlib/dev-deps changes, dropped
`test/`, regenerated `manifest.toml`).

Consumed as a Gleam git dependency by atuin-ai-core (and through it,
Atuin Hub and atuin-ai-server). Versions are tagged `5.1.3-atuin.N`.

Note for consumers: since 5.1.3 this package is an OTP application (its
ETS tables are created in the application start callback). Hosts that
load the compiled BEAM files outside a normal OTP boot must start the
`dream_http_client` application before streaming.
