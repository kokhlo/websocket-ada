# Contributing

Thanks for considering a contribution!

## Getting started

You need [Alire](https://alire.ada.dev) with a GNAT toolchain (`alr toolchain`).

```bash
git clone https://github.com/kokhlo/websocket-ada
cd websocket-ada
alr build
```

## Running the tests

Both suites must pass before any change is merged:

```bash
alr exec -- gprbuild -p -P websocket_tests.gpr && ./obj_test/test_runner
alr exec -- gprbuild -p -P websocket_handshake_tests.gpr && ./obj_test_handshake/test_handshake
```

Note: `alr test` only checks compilation — it does not run these binaries.

## What gets reviewed

- **RFC 6455 correctness.** Cite the RFC section your change relates to,
  both in code comments and in the PR description. If the RFC says a peer
  MUST fail the connection, the library should return `Protocol_Error`,
  not raise or accept silently.
- **Tests.** Bug fixes need a regression test that fails without the fix.
  New features need tests covering the RFC-normative cases (valid input
  accepted, each invalid class rejected).
- **Style.** The build runs with `-gnatwa -gnatwe` — all warnings on,
  warnings as errors. A change that compiles with a warning does not build.
- **No new dependencies.** Stdlib/GNAT only.

## Commit style

Conventional commits (`fix:`, `feat:`, `docs:`, `chore:`, `test:`),
one logical change per commit.

## Releasing

Maintainers only: bump `version` in `alire.toml` (and the README badge /
index mention if relevant), commit, tag `vX.Y.Z`, push the tag — the
[release workflow](.github/workflows/release.yml) checks the tag against
the manifest version, reruns the tests, and publishes the GitHub Release.
 Afterwards submit the new version to the [Alire index](https://github.com/alire-project/alire-index).
