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
const Model = new Function(source + "\nreturn { rows, keyboardSummary, optimistic, markCurrent, errorText }")()
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

const unknown = Model.keyboardSummary({ "keyboard/size": { value: null, label: "Unknown", recommended: [] } })
check("an unrecognized keyboard is never shown as done", unknown.complete === false && unknown.progress === "Pick a size to get recommendations")
const known = Model.keyboardSummary({ "keyboard/size": { value: "60", label: "60%", source: "known", recommended: ["a", "b"] }, a: { value: true }, b: { value: false } })
check("a recognized keyboard counts its recommended settings", known.progress === "1 of 2 recommended settings are on" && known.complete === false)

const toggle = { id: "dock/show", kind: "toggle" }
const flipped = Model.optimistic(toggle, { value: false, label: "Off", extra: 1 }, null, "on")
check("a switch shows its new state at once and keeps the rest", flipped.state.value === true && flipped.state.label === "On" && flipped.state.extra === 1)
check("a switch ignores values it does not know", Model.optimistic(toggle, null, null, "maybe") === null)
const sizes = [{ value: "60", label: "60%", current: true }, { value: "tkl", label: "Tenkeyless", current: false }]
const chosen = Model.optimistic({ id: "keyboard/size", kind: "choice" }, { value: "60", recommended: ["x"] }, sizes, "tkl")
check("a choice moves its highlight at once", chosen.options.map(o => o.current).join(",") === "false,true" && chosen.state.label === "Tenkeyless")
check("a choice keeps the rest of its state", Array.isArray(chosen.state.recommended))
check("an action waits for the real answer", Model.optimistic({ id: "projects/new", kind: "action" }, null, null, "moonshot") === null)
check("highlights compare values as text", Model.markCurrent([{ value: 60 }, { value: "tkl" }], "60")[0].current === true)
check("an empty error says what to do", Model.errorText("") === "Omahub didn't respond. Try again")
check("an error drops the command's name and starts a sentence", Model.errorText("omahub: no app named 'x'") === "No app named 'x'")

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
