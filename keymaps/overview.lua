-- Overview. SUPER + TAB shows every desktop and window with live previews, and pressed again with
-- SUPER held it walks windows like a switcher. Omarchy's Next workspace moves to
-- SUPER + CTRL + ALT + TAB; Previous and Former keep SUPER + SHIFT + TAB and SUPER + CTRL + TAB.

hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Overview", "omarchy-shell shell summon io.github.elberacasa.omahub '{\"overview\":\"next\"}'")
o.bind("SUPER + CTRL + ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
