#!/bin/bash

# overview/OverviewModel.js: desktops, reading order, search, Exposé packing, and grid neighbors.

source "$(dirname "$0")/../base-test.sh"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the overview model checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/overview/OverviewModel.js" <<'EOF'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { selector, desktops, search, pack, neighbor, recent, projectRows, freeDesktop }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

const monitor = { name: "DP-2" }
const workspace = (id, name) => ({ id, name: String(id), monitor: { name: name || "DP-2" } })
const toplevel = (address, ws, x, y, w, h, cls, title) => ({
  address: address.slice(2), title, workspace: { id: ws },
  lastIpcObject: { address, at: [x, y], size: [w, h], class: cls, workspace: { id: ws } }
})

const list = Model.desktops(
  [workspace(2), workspace(1), workspace(-98), workspace(3, "HDMI-1")],
  [
    toplevel("0xb", 1, 970, 40, 940, 1030, "cursor", "omahub"),
    toplevel("0xa", 1, 10, 40, 940, 1030, "foot", "codex"),
    toplevel("0xc", 2, 10, 40, 1900, 1030, "chromium", "Pricing"),
    toplevel("0xd", 1, 0, 0, 0, 0, "ghost", "unmapped")
  ],
  monitor.name
)

check("desktops are the regular workspaces on this screen, in id order", JSON.stringify(list.map(d => d.id)) === "[1,2]")

const numbered = Model.desktops([workspace(2), workspace(3, "HDMI-1"), workspace(7)], [], monitor.name, 5)
check("desktops 1 to 5 are always there, and any open beyond them", JSON.stringify(numbered.map(d => d.id)) === "[1,2,4,5,7]")
check("a number open on another screen is left out", !numbered.some(d => d.id === 3))
check("desktops not opened yet are marked, open ones are not",
  numbered.find(d => d.id === 1).unopened === true && numbered.find(d => d.id === 2).unopened === false)
check("without a count, only open desktops show", Model.desktops([workspace(2)], [], monitor.name).length === 1)

// QML hands Hyprland's lists over as array-like wrappers, not arrays.
const listLike = values => Object.assign(Object.create(null), values, { length: values.length })
const wrapped = Model.desktops([workspace(1)], [{
  address: "e", title: "wrapped", workspace: { id: 1 },
  lastIpcObject: { address: "0xe", at: listLike([10, 40]), size: listLike([800, 600]), class: "foot" }
}], monitor.name)
check("positions and sizes read from list wrappers", wrapped[0].windows.length === 1 && wrapped[0].windows[0].width === 800)
check("windows are in reading order", list[0].windows.map(w => w.address).join(",") === "0xa,0xb")
check("windows Hyprland reports as zero size are left out", list[0].windows.length === 2)
const fresh = Model.desktops([workspace(1)], [{ address: "f", title: "just opened", workspace: { id: 1 }, lastIpcObject: {} }], monitor.name)
check("a window not yet measured still shows on its desktop", fresh[0].windows.length === 1 && fresh[0].windows[0].address === "f")
check("an unmeasured window takes a screen's shape", fresh[0].windows[0].width / fresh[0].windows[0].height === 1920 / 1080)
check("search finds windows on every desktop by title or app", Model.search(list, "pric").map(w => w.address).join(",") === "0xc")
check("every search word must match", Model.search(list, "foot codex").length === 1 && Model.search(list, "foot pricing").length === 0)
const focused = (item, order) => Object.assign(item, { lastIpcObject: Object.assign(item.lastIpcObject, { focusHistoryID: order }) })
const history = Model.desktops([workspace(1), workspace(2)], [
  focused(toplevel("0xa", 1, 10, 40, 940, 1030, "foot", "codex"), 1),
  focused(toplevel("0xb", 1, 970, 40, 940, 1030, "cursor", "omahub"), 2),
  focused(toplevel("0xc", 2, 10, 40, 1900, 1030, "chromium", "Pricing"), 0)
], monitor.name)
check("walking windows spans every desktop, most recent first", Model.recent(history).map(w => w.address).join(",") === "0xc,0xa,0xb")
check("the overview's own focus order wins over Hyprland's history", Model.recent(history, ["b", "0xc"]).map(w => w.address).join(",") === "0xb,0xc,0xa")

check("selectors always carry 0x", Model.selector("55ab") === "address:0x55ab" && Model.selector("0x55ab") === "address:0x55ab")

const two = [{ width: 1920, height: 1080 }, { width: 1920, height: 1080 }]
const rects = Model.pack(two, 1000, 600, 20)
check("packing places every window", rects.length === 2 && rects.every(Boolean))
check("packed windows stay inside the area", rects.every(r => r.x >= 0 && r.y >= 0 && r.x + r.width <= 1000.01 && r.y + r.height <= 600.01))
check("packed windows do not overlap", rects[0].x + rects[0].width <= rects[1].x || rects[0].y + rects[0].height <= rects[1].y)
check("packing keeps each window's shape", rects.every(r => Math.abs(r.width / r.height - 1920 / 1080) < 0.01))
check("packing never makes a window larger than it is", Model.pack([{ width: 400, height: 300 }], 2000, 2000, 20)[0].width === 400)

const grid = Model.pack([{ width: 800, height: 600 }, { width: 800, height: 600 }, { width: 800, height: 600 }, { width: 800, height: 600 }], 1000, 800, 20)
check("right from the first window reaches its neighbor", Model.neighbor(grid, 0, 1, 0) === 1)
check("a move off the edge keeps the selection", Model.neighbor(grid, 1, 1, 0) === 1)

const projects = [{ name: "orbit-api", branch: "feature/search", git: true }, { name: "lumen-docs", branch: "", git: true }, { name: "notes", git: false }]
const allRows = Model.projectRows(projects, "", { "lumen-docs": 2 })
check("the picker lists every project in order, with no create row", allRows.map(r => r.name).join(",") === "orbit-api,lumen-docs,notes" && !allRows.some(r => r.create))
check("a project open on a desktop says which", allRows[1].desktop === 2 && allRows[0].desktop === 0)
check("typing keeps projects with every word", Model.projectRows(projects, "ORB api", {}).filter(r => !r.create).map(r => r.name).join(",") === "orbit-api")
const created = Model.projectRows(projects, "new idea", {})
check("a new name ends the list as a row that creates it, spaces as dashes", created.length === 1 && created[0].create && created[0].name === "new-idea")
check("an existing name is not offered again", !Model.projectRows(projects, "notes", {}).some(r => r.create))
check("a name no folder could have is not offered", Model.projectRows(projects, "../x", {}).length === 0)
const top = ws => ({ workspace: { id: ws } })
check("the free desktop is the lowest with no windows", Model.freeDesktop([top(1), top(3), top(-98)]) === 2)
check("with nothing open, desktop 1 is free", Model.freeDesktop([]) === 1)

console.log(JSON.stringify(checks))
EOF
)

while IFS=$'\t' read -r name ok; do
  if [[ $ok == "true" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
done < <(jq -r '.[] | [.name, (.ok | tostring)] | @tsv' <<<"$results")

finish
