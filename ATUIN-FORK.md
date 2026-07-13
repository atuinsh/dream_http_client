# atuinsh fork of dream_http_client

Extracted from the [TrustBound/dream](https://github.com/TrustBound/dream)
monorepo (`modules/http_client`, MIT) via `git subtree split`, preserving
the module's history. This fork tracks the 3.0.1 release — upstream
monorepo commit `bbbdbf38e01aba2797941b59b36961fb490e0e5d`, identical to
the `dream_http_client` 3.0.1 hex release — because newer majors have a
stdlib dependency constraint we can't satisfy.

Consumed as a Gleam git dependency by Atuin Hub. Local patches on top of
upstream are individual commits after the extraction commit; see
`git log` for details. Patch versions are tagged `3.0.1-atuin.N`.
