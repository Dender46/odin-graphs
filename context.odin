package graphs

import rl "vendor:raylib"

GRAPH_COLOR         :: rl.DARKGRAY
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
    yAxisLine       : LineDimensions,
    graphMargin     : i32,

    plotOffset      : f32, // in milliseconds
    zoomLevel       : f32, // **USE THIS**: actual zoom
    zoomLevelTarget : f32, // **DO NOT USE THIS**: only used to calc smoothness

    pointsCount     : f32,
    pointsData      : [dynamic]rl.Vector2,
    fileElements    : [dynamic]FileElement,
    pointsPerBucket : int,
    maxValue        : f32,
    maxValueTarget  : f32,
}

ctx: ^Context