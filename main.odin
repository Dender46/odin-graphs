package graphs

import "core:os"
import "core:bufio"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// Variables that don't change, and that should be updated on hot reloaded
// Be careful
initialize_statics :: proc() {
    ctx.zoomLevel = 60_000
    ctx.graphMargin = 60
    ctx.xAxisLine = {
        x0 = ctx.graphMargin,
        x1 = ctx.window.width - ctx.graphMargin,
        y  = ctx.window.height - ctx.graphMargin - 30
    }
}

@(export)
game_init :: proc() {
    ctx = new(Context)
    ctx.window = Window{"Raylib Graphs", 1600, 720, 60, {.WINDOW_RESIZABLE, .MSAA_4X_HINT}}

    initialize_statics()
    ctx.targetZoomLevel = ctx.zoomLevel
    ctx.pointsCount = 2400

    rl.SetConfigFlags(ctx.window.configFlags)
    rl.InitWindow(ctx.window.width, ctx.window.height, ctx.window.name)
    rl.SetTargetFPS(ctx.window.fps)

    if false {
        fileHandle, err := os.open("2024_10_14_14_33_Battery_Level.bin")
        defer os.close(fileHandle)
        if err != os.ERROR_NONE {
            fmt.println("Couldn't open a file")
            return
        }
    
        fmt.println("main context.user_index: ", context.user_index)
        fileBytes, succ := os.read_entire_file_from_filename("2024_10_14_14_33_Battery_Level.bin")
        fileSize, _ := os.file_size(fileHandle)
    
        FileElement :: struct {
            timestep: i64,
            value: i64,
        }
        elements: [dynamic]FileElement
        defer delete(elements)
        reserve(&elements, fileSize / 16)
    
        if succ && len(fileBytes) == int(fileSize) {
            firstTimestep := bytes_to_int64(fileBytes[:8])
    
            for i := 0; i < len(fileBytes); i += 16 {
                timestep := bytes_to_int64(fileBytes[i:i+8])
    
                nanoseconds := i64(timestep - firstTimestep) * 100
                // buf : [MIN_HMSMS_LEN]u8
                // fmt.println(time_to_string_hmsms(nanoseconds, buf[:]))
    
                val := bytes_to_int64(fileBytes[i+8:i+16])
                append(&elements, FileElement{
                    timestep=timestep,
                    value=val
                })
            }
        } else {
            fmt.println("something is wrong")
        }
    }

    reserve(&ctx.pointsData, u32(ctx.pointsCount))
    for i in 0..<ctx.pointsCount {
        append(&ctx.pointsData, rand.float32_range(10, 60))
    }
}

@(export)
game_update :: proc() -> bool {
    defer {
        reset_debug_text_state()
    }
    ctx.window.width = rl.GetScreenWidth()
    ctx.window.height = rl.GetScreenHeight()

    {// Zoom slider, before calc of mouse/zoom offsets to avoid jitter when zooming in some cases
        margin :: 80
        zoomLevelSliderRect: rl.Rectangle = {
            margin, f32(ctx.window.height-30),
            f32(ctx.window.width-margin*2), 30
        }
        h, m, s, ms := clock_from_nanoseconds(i64(ctx.zoomLevel) * 1_000_000)
        leftCaption  := fmt.ctprint(ctx.zoomLevel)
        rightCaption: cstring
        switch {
            case h == 0 && m == 0 && s < 3  : rightCaption = fmt.ctprintf("%02vs.%03vms", s, ms)
            case h == 0 && m >= 0 && s >= 0 : rightCaption = fmt.ctprintf("%02vm:%02vs", m, s)
            case h > 0                      : rightCaption = fmt.ctprintf("%02vh:%02vm", h, m)
        }

        GuiSlider_Custom(zoomLevelSliderRect, leftCaption, rightCaption, &ctx.targetZoomLevel, 10, ctx.pointsCount*1000) //40 mins
    }

    if rl.IsMouseButtonDown(.LEFT) && !guiControlExclusiveMode {
        ctx.offsetX += rl.GetMouseDelta().x
    }

    ctx.offsetX = clamp(ctx.offsetX, -((ctx.pointsCount*1000/ctx.zoomLevel-1)*x_axis_width()), 0)
    ctx.plotOffset = remap(0, x_axis_width(), 0, ctx.zoomLevel, ctx.offsetX)
    // Clamp plotOffset just in case. If gives trouble - remove it >:(
    ctx.plotOffset = clamp(ctx.plotOffset, -(ctx.pointsCount*1000-ctx.zoomLevel), 0)

    if wheelMove := rl.GetMouseWheelMoveV().y; wheelMove != 0 {
        zoomExp :: -0.07
        ctx.targetZoomLevel *= math.exp(zoomExp * wheelMove)
        ctx.targetZoomLevel = clamp(ctx.targetZoomLevel, 10, ctx.pointsCount*1000)
    }

    ctx.zoomLevel = exp_decay(ctx.zoomLevel, ctx.targetZoomLevel, 16, rl.GetFrameTime())

    // ====================
    // Raylib begin drawing
    // ====================
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    render_x_axis(ctx.plotOffset, ctx.offsetX, ctx.zoomLevel)

    // Render plot line
    if false {
        for i in i32(-ctx.plotOffset)..<i32(ctx.zoomLevel-ctx.plotOffset) {
            index := clamp(i, 0, i32(ctx.pointsCount-2))
            posBegin := rl.Vector2{
                math.lerp(f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(index)/ctx.zoomLevel),
                math.lerp(f32(0), f32(ctx.xAxisLine.y), ctx.pointsData[index]/60) // TODO: use yAxisLine TODO: change lerpT
            }

            posEnd   := rl.Vector2{
                math.lerp(f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(index+1)/ctx.zoomLevel),
                math.lerp(f32(0), f32(ctx.xAxisLine.y), ctx.pointsData[index+1]/60) // TODO: use yAxisLine TODO: change lerpT
            }
            posBegin.x += ctx.offsetX
            posEnd.x   += ctx.offsetX
            rl.DrawLineEx(posBegin, posEnd, 3, rl.BLUE)
        }
    }

    //rl.GuiSlider({0,0, 100,30}, "", "", &x, 0, f32(window.width) / 2)
    //rl.GuiSlider({0,60,100,30}, "", "", &y, 0, f32(window.height) / 2)
    //rl.GuiSlider({0,90,100,30}, "", "", &rot, 0, 360)
    {
        @(static) hotReloadTimer: f32 = 3
        if hotReloadTimer >= 0 {
            draw_centered_text("RELOADED", ctx.window.width/2, ctx.window.height/2, 0, 60, rl.ColorAlpha(rl.RED, hotReloadTimer))
            hotReloadTimer -= rl.GetFrameTime()
            hotReloadTimer = clamp(hotReloadTimer, 0, 3)
        }
    }
    rl.DrawFPS(5, 5)
    rl.EndDrawing()

    return !rl.WindowShouldClose()
}

@(export)
game_memory :: proc() -> rawptr {
    return ctx
}

@(export)
game_shutdown :: proc() {
    delete(ctx.pointsData)
    free(ctx)
}

// This is called everytime game is reloaded
// So we can put something that can be trivially reinited
@(export)
game_hot_reloaded :: proc(memFromOldApi: ^Context) {
    ctx = memFromOldApi
    initialize_statics()
}
