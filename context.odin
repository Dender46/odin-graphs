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

FileElement :: struct {
    timestep        : i64,
    value           : i64,
}

Context :: struct {
    window          : Window,

    xAxisLine       : LineDimensions,
    graphMargin     : i32,

    offsetX         : f32, // in pixels
    plotOffset      : f32, // in milliseconds
    zoomLevel       : f32, // **USE THIS**: actual zoom
    targetZoomLevel : f32, // **DO NOT USE THIS**: only used to calc smoothness

    pointsCount     : f32,
    pointsData      : [dynamic]rl.Vector2,
    fileElements    : [dynamic]FileElement,
}

ctx: ^Context