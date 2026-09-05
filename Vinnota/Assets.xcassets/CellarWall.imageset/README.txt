cellar-wall.png is missing.

The design project's copy is larger than the 256 KiB cap on reading a single
file out of Claude Design, so it could only be fetched truncated (192 KiB,
cut mid-IDAT — about 17% of its 1200 rows survive).

To restore it: export `assets/labels/cellar-wall.png` from the Claude Design
project, drop it into this folder, and put the filename back:

    { "filename" : "cellar-wall.png", "idiom" : "universal" }

Until then LoginView falls back to a gradient — see `cellarWall` in
Vinnota/Views/LoginView.swift.
