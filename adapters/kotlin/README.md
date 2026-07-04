# Kotlin adapter (Gradle + kover)

Stack adapter for Kotlin/JVM. Reuses the core hygiene scripts unchanged and adds a test gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `./gradlew test koverVerify` (JUnit5 + kover coverage rule) |

Validated end to end: a Kotlin consumer ran `fitness` + `test` green on a real pull_request, core
scripts byte-identical to every other stack's.

## Config

The coverage floor is a kover `verify` rule in `build.gradle.kts` (`minBound(90)`) — the analog of
COVERAGE_THRESHOLD. `harness.config.sh` sets only `FILE_LINE_NAMES="*.kt *.sh"`.

Note: Kotlin/JVM shares Gradle with the android-jvm adapter; `install.sh --profile auto` picks
`kotlin` only when a `kotlin("jvm")` plugin is present and there is no AndroidManifest.

## Mutation (shipped)

`scripts/run-mutation.sh` runs PITest via `./gradlew pitest`, which fails below `mutationThreshold`.
Validated green on a real pull_request. The consumer adds the `info.solidsoft.pitest` Gradle plugin
and a `pitest { targetClasses; mutationThreshold }` block to `build.gradle.kts`.
