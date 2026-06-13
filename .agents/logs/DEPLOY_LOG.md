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

NOTES:
- GST export remains summary CSV only; invoice-wise GSTR-1 upload data is still deferred.
- Purchase order / sales order workflow, cash flow statement, stock ageing/reorder, and group-company consolidation remain deferred for this RC.

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
- Bill-wise ageing buckets are shipped; interest-on-overdue remains deferred and is not part of the current RC bundle.
- TDS/TCS/cheque/bill-allocation voucher fields are shipped; only deeper workflow expansion remains deferred.
- PO/SO order-tracking remains deferred and is not part of the current RC bundle.
- Cash flow / funds flow statement remains deferred and is not part of the current RC bundle.
- Stock ageing / reorder-level reports remain deferred and are not part of the current RC bundle.
- Group-company consolidation remains deferred and is not part of the current RC bundle.
- Search consistency remains intentionally asymmetrical in this RC; Reports and Settings do not add extra search surfaces.
