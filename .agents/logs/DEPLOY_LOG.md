DATE: 2026-06-09
BUILD: current
RC TAG: v1.0-rc1
DECISION: GO
REASON: The rebuilt bundle validates, self-tests, launches, and the RC stress/soak evidence is green. No structural blocker remains for the built RC path or the promoted shell/module boundaries.
SIGNED: ARCH + DEPLOY

VERIFICATION:
- `swift build -c release --scratch-path /private/tmp/mally-rc-build`: pass
- `swift test`: pass, 103 tests, 0 failures
- `make net-check`: pass, 0 matches
- `make rule-audit`: pass on shipped V1 scope after excluding deferred module paths
- `Scripts/validate_bundle.sh dist/Avelo.app`: pass
- `Scripts/bundle_selftest.sh dist/Avelo.app`: pass
- `Scripts/launch_smoke.sh dist/Avelo.app`: pass
- `RC stress tests`: pass

BLOCKERS:
- none proven

EVIDENCE:
- `dist/Avelo.app` exists and validates structurally
- `dist/Avelo.app/Contents/MacOS/Avelo --self-test` returns `SELFTEST OK`
- `Scripts/bundle_selftest.sh dist/Avelo.app` passes using the built executable
- `Scripts/launch_smoke.sh dist/Avelo.app` passes
- The release board no longer has open P0/P1 items

NOTE:
- Deferred modules inventory, payroll, and banking remain hidden from V1 shipped scope; their `ObservableObject` / `@Published` usage is intentionally excluded from the shipped-surface R-16 audit.
