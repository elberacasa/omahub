#!/bin/bash

# dock/DockModel.js: when a window covers the band the dock uses, so an auto-hiding dock hides.

source "$(dirname "$0")/../base-test.sh"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the dock model checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/dock/DockModel.js" <<'EOF'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { covered, items, parseConfig, catalog, dropSlot, reorder }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

// A 1920 by 1080 screen and a dock band 700 long and 90 deep, centered on its edge.
const monitor = { x: 0, y: 0, width: 1920, height: 1080, scale: 1, activeWorkspace: { id: 1 }, specialWorkspace: { id: 0 } }
const client = (ws, x, y, w, h, extra) => Object.assign({ mapped: true, hidden: false, workspace: { id: ws }, at: [x, y], size: [w, h] }, extra)

check("an empty desktop leaves the dock clear", !Model.covered(monitor, [], "bottom", 700, 90))
check("a full-height tiled window covers it", Model.covered(monitor, [client(1, 10, 40, 1900, 1030)], "bottom", 700, 90))
check("a window that stops above the band leaves it clear", !Model.covered(monitor, [client(1, 10, 40, 1900, 940)], "bottom", 700, 90))
check("a window beside the band leaves it clear", !Model.covered(monitor, [client(1, 0, 600, 500, 470)], "bottom", 700, 90))
check("windows on other desktops do not count", !Model.covered(monitor, [client(2, 10, 40, 1900, 1030)], "bottom", 700, 90))
check("hidden and unmapped windows do not count",
  !Model.covered(monitor, [client(1, 10, 40, 1900, 1030, { hidden: true }), client(1, 10, 40, 1900, 1030, { mapped: false })], "bottom", 700, 90))
check("an open special workspace counts",
  Model.covered(Object.assign({}, monitor, { specialWorkspace: { id: -98 } }), [client(-98, 100, 100, 1700, 950)], "bottom", 700, 90))
check("a scaled monitor measures in logical pixels",
  Model.covered(Object.assign({}, monitor, { width: 3840, height: 2160, scale: 2 }), [client(1, 10, 40, 1900, 1030)], "bottom", 700, 90))
check("a window without geometry yet does not count", !Model.covered(monitor, [{ mapped: true, workspace: { id: 1 } }], "bottom", 700, 90))
const listLike = values => Object.assign(Object.create(null), values, { length: values.length })
check("positions and sizes read from list wrappers",
  Model.covered(monitor, listLike([client(1, 10, 40, 1900, 1030, { at: listLike([10, 40]), size: listLike([1900, 1030]) })]), "bottom", 700, 90))
check("no monitor record means clear", !Model.covered(null, [client(1, 10, 40, 1900, 1030)], "bottom", 700, 90))

check("a left dock is covered by a window along the left edge", Model.covered(monitor, [client(1, 0, 40, 960, 1030)], "left", 700, 90))
check("a left dock stays clear of a window on the right half", !Model.covered(monitor, [client(1, 970, 40, 940, 1030)], "left", 700, 90))
check("a right dock is covered by a window along the right edge", Model.covered(monitor, [client(1, 970, 40, 940, 1030)], "right", 700, 90))
check("a side band is centered along the edge", !Model.covered(monitor, [client(1, 0, 0, 1920, 150)], "left", 700, 90))

const entries = [{ id: "foot", name: "Foot" }, { id: "obsidian", name: "Obsidian" }]
const open = [{ appId: "foot" }, { appId: "obsidian" }]
const all = Model.items(["foot"], entries, open)
check("open apps that are not kept follow the kept ones", all.map(i => i.id).join(",") === "foot,obsidian" && all[1].divider)
const kept = Model.items(["foot"], entries, open, false)
check("with open apps hidden, only kept apps show", kept.map(i => i.id).join(",") === "foot")
check("kept apps still know their open windows", kept[0].windows.length === 1)

const installed = [
  { id: "obsidian", name: "Obsidian", genericName: "Notes" },
  { id: "foot", name: "Foot", genericName: "Terminal", keywords: ["shell", "console"] },
  { id: "foot", name: "Foot again" },
  { id: "hidden", name: "Hidden helper", noDisplay: true }
]
const rows = Model.catalog(installed, ["foot"], "")
check("the app catalog lists each app once, by name, leaving out hidden ones", rows.map(r => r.id).join(",") === "foot,obsidian")
check("the catalog marks kept apps", rows[0].kept === true && rows[1].kept === false)
check("catalog search matches keywords and generic names",
  Model.catalog(installed, [], "console")[0].id === "foot" && Model.catalog(installed, [], "notes")[0].id === "obsidian")
check("a choice not saved yet shows in the catalog", Model.catalog(installed, ["foot"], "", { foot: false })[0].kept === false)

check("a point before the first icon drops first", Model.dropSlot([30, 90, 150], 10, 3) === 0)
check("a point between icons drops between them", Model.dropSlot([30, 90, 150], 100, 3) === 2)
check("drops stay among the kept apps", Model.dropSlot([30, 90, 150, 210], 400, 2) === 2)
check("moving a kept app places it at the slot", Model.reorder(["a", "b", "c"], "a", 2).join(",") === "b,c,a")
check("a newly kept app joins at the slot", Model.reorder(["a", "b"], "x", 1).join(",") === "a,x,b")
check("a slot past the end keeps the app last", Model.reorder(["a", "b"], "a", 9).join(",") === "b,a")

check("settings read from the dock file", Model.parseConfig('{"show":true}').show === true)
check("an empty dock file means no settings", JSON.stringify(Model.parseConfig("")) === "{}")
check("a broken dock file is not taken as settings", Model.parseConfig('{"show":') === null && Model.parseConfig("[1]") === null)

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
