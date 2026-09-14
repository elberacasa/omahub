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
const Model = new Function(source + "\nreturn { selector, desktops, search, pack, neighbor, recent }")()
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

// QML hands Hyprland's lists over as array-like wrappers, not arrays.
const listLike = values => Object.assign(Object.create(null), values, { length: values.length })
const wrapped = Model.desktops([workspace(1)], [{
  address: "e", title: "wrapped", workspace: { id: 1 },
  lastIpcObject: { address: "0xe", at: listLike([10, 40]), size: listLike([800, 600]), class: "foot" }
}], monitor.name)
check("positions and sizes read from list wrappers", wrapped[0].windows.length === 1 && wrapped[0].windows[0].width === 800)
check("windows are in reading order", list[0].windows.map(w => w.address).join(",") === "0xa,0xb")
check("windows without a size are left out", list[0].windows.length === 2)
check("search finds windows on every desktop by title or app", Model.search(list, "pric").map(w => w.address).join(",") === "0xc")
check("every search word must match", Model.search(list, "foot codex").length === 1 && Model.search(list, "foot pricing").length === 0)
const focused = (item, order) => Object.assign(item, { lastIpcObject: Object.assign(item.lastIpcObject, { focusHistoryID: order }) })
const history = Model.desktops([workspace(1), workspace(2)], [
  focused(toplevel("0xa", 1, 10, 40, 940, 1030, "foot", "codex"), 1),
  focused(toplevel("0xb", 1, 970, 40, 940, 1030, "cursor", "omahub"), 2),
  focused(toplevel("0xc", 2, 10, 40, 1900, 1030, "chromium", "Pricing"), 0)
], monitor.name)
check("walking windows spans every desktop, most recent first", Model.recent(history).map(w => w.address).join(",") === "0xc,0xa,0xb")

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
