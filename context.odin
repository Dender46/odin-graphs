package graphs

import rl "vendor:raylib"

Window :: struct {
    name            : cstring,
    width           : i32,
    height          : i32,
    fps             : i32,
    configFlags     : rl.ConfigFlags,
}

Context :: struct {
    window          : Window,

    fileData        : [dynamic][2]i64,
    graph           : Graph,
}

ctx: ^Context