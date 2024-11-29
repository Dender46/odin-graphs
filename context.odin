package graphs

import rl "vendor:raylib"

GRAPH_COLOR         :: rl.GRAY
SUB_GRAPH_COLOR     :: rl.LIGHTGRAY
DEBUG_BOUNDARY      :: false

Window :: struct {
    name            : cstring,
    width           : i32,
    height          : i32,
    fps             : i32,
    configFlags     : rl.ConfigFlags,
}

Context :: struct {
    window          : Window,

    xAxisLine       : LineDimensions,
    graphMargin     : i32,
    offsetX         : f32,
    plotOffset      : f32,

    zoomLevel       : f32, // **USE THIS**: actual zoom
    targetZoomLevel : f32, // **DO NOT USE THIS**: only used to calc smoothness

    pointsCount     : f32,
    pointsData      : [dynamic]f32
}

ctx: ^Context