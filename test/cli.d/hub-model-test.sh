#!/bin/bash

# hub/HubModel.js: the order rows take inside a section.

source "$(dirname "$0")/../base-test.sh"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the hub model checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/hub/HubModel.js" <<'EOF'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { rows }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

const row = (id, title, kind, order) => ({ id, title, kind, order, section: "dock", summary: "", keywords: "" })
const catalog = [
  row("dock/bounce", "Animate opening apps", "toggle", 70),
  row("dock/magnify", "Magnification", "choice", 30),
  row("dock/show", "Dock", "toggle", 10),
  row("dock/size", "Size", "choice", 20),
  row("dock/extra", "Another choice", "choice", undefined),
  row("dock/later", "A switch", "toggle", undefined)
]
const ids = Model.rows(catalog, "dock", "").map(setting => setting.id)
check("rows with an order come first, lowest first", ids.slice(0, 4).join(",") === "dock/show,dock/size,dock/magnify,dock/bounce")
check("rows without one follow, choices before switches", ids.slice(4).join(",") === "dock/extra,dock/later")

console.log(JSON.stringify(checks))
EOF
)

while IFS=$'\t' read -r ok name; do
  if [[ $ok == "true" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
done < <(jq -r '.[] | "\(.ok)\t\(.name)"' <<<"$results")

finish
