# MALLY Makefile — Swift Package Manager
# Run from repo root.

SRC_DIR := .

.PHONY: all build test net-check rule-audit board todo count help

all: net-check build test

# Swift Package Manager build
build:
	swift build 2>&1

# Run full test suite
test:
	swift test 2>&1

# CRITICAL: Must be 0 for V1
net-check:
	@echo "=== NET-CHECK ==="
	@count=$$(grep -rn --include="*.swift" \
	  -e "URLSession" -e "URLRequest" -e "URLComponents" \
	  -e "import Network" -e "NWConnection" -e "WKWebView" \
	  -e "URLCache" -e "HTTPURLResponse" \
	  $(SRC_DIR) | grep -v ".agents" | grep -v ".build" | wc -l | tr -d ' '); \
	echo "Matches: $$count"; \
	if [ "$$count" -gt 0 ]; then \
	  grep -rn --include="*.swift" \
	    -e "URLSession" -e "URLRequest" -e "import Network" -e "NWConnection" \
	    $(SRC_DIR) | grep -v ".agents" | grep -v ".build"; \
	  echo "FAIL"; exit 1; \
	else echo "PASS: 0 network calls"; fi

# R-16 check: ObservableObject/Published forbidden in shipped paths
r16-check:
	@echo "=== R-16 CHECK ==="
	@violations=$$(grep -rn --include="*.swift" \
	  -e "ObservableObject" -e "@Published" -e "@EnvironmentObject" \
	  $(SRC_DIR)/Mally/App \
	  $(SRC_DIR)/Mally/Core \
	  $(SRC_DIR)/Mally/Features/Accounts \
	  $(SRC_DIR)/Mally/Features/Audit \
	  $(SRC_DIR)/Mally/Features/Onboarding \
	  $(SRC_DIR)/Mally/Features/Reports \
	  $(SRC_DIR)/Mally/Features/Settings \
	  $(SRC_DIR)/Mally/Features/Vouchers \
	  | grep -v ".build" | grep -v Test); \
	if [ -n "$$violations" ]; then \
	  echo "$$violations"; echo "FAIL"; exit 1; \
	else echo "PASS: R-16 clean"; fi

# R-15 check: no TODOs or fatalError("Not implemented") in shipped paths
r15-check:
	@echo "=== R-15 CHECK ==="
	@grep -rn --include="*.swift" \
	  -e 'TODO' -e 'FIXME' -e 'fatalError("Not implemented")' \
	  $(SRC_DIR)/Mally | grep -v ".build" || echo "PASS: R-15 clean"

# R-4 check: no Double/Float in money paths
r4-check:
	@echo "=== R-4 CHECK (Double in money) ==="
	@grep -rn --include="*.swift" \
	  -e "Double.*paise\|paise.*Double\|Float.*amount\|amount.*Float" \
	  $(SRC_DIR)/Mally | grep -v ".build" || echo "PASS: R-4 check clean (manual review still needed)"

# Full rule audit
rule-audit: net-check r16-check r15-check r4-check
	@echo ""
	@echo "Manual checks still needed: R-2, R-3, R-5, R-6, R-8, R-9, R-10, R-11, R-12, R-13, R-17, R-18"
	@echo "See Docs/Mally_Rules.md"

# Show full task board
board:
	@cat .agents/TASK_BOARD.md

# Show only incomplete tasks
todo:
	@grep "^- \[ \]" .agents/TASK_BOARD.md

# Count remaining
count:
	@echo "Remaining:"
	@grep -c "^- \[ \]" .agents/TASK_BOARD.md || echo "0"

help:
	@echo "Targets: build | test | net-check | r16-check | r15-check | rule-audit | board | todo | count"
