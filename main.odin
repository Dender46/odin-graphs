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

    if true {
        fileName :: "2024_08_21_12_30_Render_CPU_Main_Thread_Frame_Time.bin"
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
        reserve(&ctx.fileElements, fileSize / 16)

        if ok1 && len(fileBytes) == int(fileSize) {
            firstTimestep := bytes_to_int64(fileBytes[:8])

            for i := 0; i < len(fileBytes); i += 16 {
                timestep := bytes_to_int64(fileBytes[i:i+8])

                // Mul by 100 to convert from .NET ticks to nanoseconds
                nanoseconds := (timestep - firstTimestep) * 100
                // but for now lets keep it to milliseconds range
                ms := nanoseconds / 1_000_000

                val := bytes_to_int64(fileBytes[i+8:i+16])
                append(&ctx.fileElements, FileElement{
                    timestep=ms,
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
    ctx.plotOffset = remap(f32(0), x_axis_width(), f32(0), ctx.zoomLevel, ctx.offsetX)
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

    h, m, s, ms := clock_from_nanoseconds(i64(abs(ctx.plotOffset)) * 1_000_000)
    debug_text("plotOffset:")
    debug_text(ctx.plotOffset)
    debug_textf(FORMAT_H_M_S_MS, h, m, s, ms)
    debug_padding()

    // Render plot line
    if true {
        plotStart := -ctx.plotOffset
        plotEnd   := ctx.zoomLevel-ctx.plotOffset
        for i := 0; i < len(ctx.fileElements)-1; i += 1 {
            el := ctx.fileElements[i]
            nextEl := ctx.fileElements[i+1]
            if f32(el.timestep) < plotStart {
                continue
            }
            if f32(el.timestep) > plotEnd {
                debug_text(i)
                break
            }
            i := i32(i)
            // for testing convert initial values in nanoseconds to milliseconds
            convertedVal := f32(el.value) / 1_000_000
            convertedValNext := f32(nextEl.value) / 1_000_000

            posBegin := rl.Vector2{
                remap(plotStart, plotEnd, f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(el.timestep)),
                f32(math.lerp(f64(ctx.xAxisLine.y), f64(0), f64(convertedVal / 40))) // TODO: use yAxisLine TODO: change lerpT
            }

            posEnd   := rl.Vector2{
                remap(plotStart, plotEnd, f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(nextEl.timestep)),
                f32(math.lerp(f64(ctx.xAxisLine.y), f64(0), f64(convertedValNext / 40))) // TODO: use yAxisLine TODO: change lerpT
            }

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
