package graphs

import rl "vendor:raylib"

// =============== CONFIG ===============

Window :: struct {
    name:           cstring,
    width:          i32,
    height:         i32,
    fps:            i32,
    configFlags:    rl.ConfigFlags,
}

window := Window{"Raylib Graphs", 1600, 720, 60, {.WINDOW_RESIZABLE, .MSAA_4X_HINT}}

// =============== GRAPHS ===============

GRAPH_COLOR         :: rl.GRAY
SUB_GRAPH_COLOR     :: rl.LIGHTGRAY
DEBUG_BOUNDARY      :: true

graphMargin: i32    : 60

xAxisLine: LineDimensions = {
    x0 = graphMargin,
    x1 = window.width - graphMargin,
    y  = window.height - graphMargin - 80
}