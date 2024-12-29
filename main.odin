package graphs

import "core:os"
import "core:bufio"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:math"
import "core:slice"
import "core:math/rand"
import rl "vendor:raylib"

@(export)
game_init :: proc() {
    ctx = new(Context)
    ctx.window = Window{"Raylib Graphs", 1600, 720, 60, {.WINDOW_RESIZABLE, .MSAA_4X_HINT}}

    rl.SetConfigFlags(ctx.window.configFlags)
    rl.InitWindow(ctx.window.width, ctx.window.height, ctx.window.name)
    rl.SetTargetFPS(ctx.window.fps)

    if true {
        fileName :: "2024_08_22_14_16_Render_CPU_Main_Thread_Frame_Time.bin"
        // fileName :: "2024_08_21_12_30_Render_CPU_Main_Thread_Frame_Time.bin"
        fileHandle, ok0 := os.open(fileName)
        if ok0 != os.ERROR_NONE {
            fmt.println("Couldn't open a file")
            return
        }
        defer os.close(fileHandle)

        fileBytes, ok1 := os.read_entire_file_from_filename(fileName)
        if !ok1 {
            fmt.println("Couldn't read file ")
            return
        }
        defer delete(fileBytes)

        fileSize, _ := os.file_size(fileHandle)
        reserve(&ctx.fileData, fileSize / 16 * 3)

        if ok1 && len(fileBytes) == int(fileSize) {
            lastTimeStamp: i64 = 0
            for i in 0..<3 {
                firstTimestep := bytes_to_int64(fileBytes[:8])
    
                for i := 0; i < len(fileBytes); i += 16 {
                    timestep := bytes_to_int64(fileBytes[i:i+8])
    
                    // Mul by 100 to convert from .NET ticks to nanoseconds
                    nanoseconds := (timestep - firstTimestep) * 100
                    // but for now lets keep it to milliseconds range
                    ms := nanoseconds / 1_000_000
    
                    val := bytes_to_int64(fileBytes[i+8:i+16])
                    append(&ctx.fileData, [2]i64{
                        ms + lastTimeStamp,
                        val
                    })
                }
                lastTimeStamp = ctx.fileData[len(ctx.fileData)-1][0]
            }
        } else {
            fmt.println("something is wrong")
        }
    }

    graphSettings := GraphSettings{
        zoomLevel = 60_000,
        boundaries = {
            width = f32(ctx.window.width),
            height = f32(ctx.window.height),
            padding = 0,
        },
    }
    ctx.graph = graph_init(graphSettings, &ctx.fileData)
}

@(export)
game_update :: proc() -> bool {
    ctx.window.width  = rl.GetScreenWidth()
    ctx.window.height = rl.GetScreenHeight()

    ctx.graph.boundaries.width  = f32(ctx.window.width)
    ctx.graph.boundaries.height = f32(ctx.window.height)
    ctx.graph.boundaries.padding = 30

    {// Zoom slider, before calc of mouse/zoom offsets to avoid jitter when zooming in some cases
        margin :: 80
        zoomLevelSliderRect: rl.Rectangle = {
            margin, f32(ctx.window.height-30),
            f32(ctx.window.width-margin*2), 30
        }
        h, m, s, ms := clock_from_nanoseconds(i64(ctx.graph.zoomLevel) * 1_000_000)
        leftCaption  := fmt.ctprint(ctx.graph.zoomLevel)
        rightCaption: cstring
        switch {
            case h == 0 && m == 0 && s < 3  : rightCaption = fmt.ctprintf(FORMAT_S_MS, s, ms)
            case h == 0 && m >= 0 && s >= 0 : rightCaption = fmt.ctprintf(FORMAT_M_S, m, s)
            case h > 0                      : rightCaption = fmt.ctprintf(FORMAT_H_M, h, m)
        }

        GuiSlider_Custom(zoomLevelSliderRect, leftCaption, rightCaption, &ctx.graph.zoomLevelTarget, 10, ctx.graph.pointsCount) //40 mins
    }

    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    graph_update(&ctx.graph)

    // h, m, s, ms := clock_from_nanoseconds(i64(abs(ctx.plotOffset)) * 1_000_000)
    //debug_text("plotOffset:")
    //debug_text(ctx.plotOffset)
    //debug_textf(FORMAT_H_M_S_MS, h, m, s, ms)
    //debug_padding()

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

    reset_debug_text_state()
    free_all(context.temp_allocator)

    return !rl.WindowShouldClose()
}

@(export)
game_memory :: proc() -> rawptr {
    return ctx
}

@(export)
game_shutdown :: proc() {
    delete(ctx.fileData)
    graph_delete(&ctx.graph)
    free(ctx)
}

// This is called everytime game is reloaded
// So we can put something that can be trivially reinited
@(export)
game_hot_reloaded :: proc(memFromOldApi: ^Context) {
    ctx = memFromOldApi
}

// make game use good GPU on laptops etc
// @(export)
// NvOptimusEnablement: u32 = 1
// @(export)
// AmdPowerXpressRequestHighPerformance: i32 = 1