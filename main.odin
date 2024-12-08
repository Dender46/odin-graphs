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
update_statics :: proc() {
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

    update_statics()
    ctx.zoomLevel = 60_000
    ctx.targetZoomLevel = ctx.zoomLevel
    ctx.pointsCount = 2400

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

    ctx.pointsData = make([dynamic]rl.Vector2, len(ctx.fileElements))
}

@(export)
game_update :: proc() -> bool {
    defer {
        reset_debug_text_state()
    }
    update_statics()
    // update window size values outside of update_statics() to avoid issues
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
            case h == 0 && m == 0 && s < 3  : rightCaption = fmt.ctprintf(FORMAT_S_MS, s, ms)
            case h == 0 && m >= 0 && s >= 0 : rightCaption = fmt.ctprintf(FORMAT_M_S, m, s)
            case h > 0                      : rightCaption = fmt.ctprintf(FORMAT_H_M, h, m)
        }
        
        GuiSlider_Custom(zoomLevelSliderRect, leftCaption, rightCaption, &ctx.targetZoomLevel, 10, ctx.pointsCount*3000) //40 mins
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
        ctx.targetZoomLevel = clamp(ctx.targetZoomLevel, 10, ctx.pointsCount*3000)
    }

    ctx.zoomLevel = exp_decay(ctx.zoomLevel, ctx.targetZoomLevel, 16, rl.GetFrameTime())

    // ====================
    // Raylib begin drawing
    // ====================
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    render_x_axis(ctx.plotOffset, ctx.offsetX, ctx.zoomLevel)

    // h, m, s, ms := clock_from_nanoseconds(i64(abs(ctx.plotOffset)) * 1_000_000)
    //debug_text("plotOffset:")
    //debug_text(ctx.plotOffset)
    //debug_textf(FORMAT_H_M_S_MS, h, m, s, ms)
    //debug_padding()

    // Render plot line
    if true {
        plotStart := -ctx.plotOffset
        plotEnd   := ctx.zoomLevel-ctx.plotOffset
        pointsDataIndex: i32

        {
            pointsPerBucket_f := f32(ctx.pointsPerBucket)
            GuiSlider_Custom({100, 0, 600, 28}, "", "", &pointsPerBucket_f, 1, 100)
            ctx.pointsPerBucket = int(pointsPerBucket_f)
        }
        bucketsCount := len(ctx.fileElements) / ctx.pointsPerBucket
        debug_text("pointsPerBucket: ", ctx.pointsPerBucket)
        debug_text("bucketsCount: ", bucketsCount)

        get_point_on_plot :: proc(ctx: ^Context, plotStart, plotEnd: f32, el: FileElement) -> rl.Vector2 {
            // for testing convert initial values in nanoseconds to milliseconds
            convertedVal := f64(el.value) / 1_000_000
            return {
                remap(plotStart, plotEnd, f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(el.timestep)),
                f32(math.lerp(f64(ctx.xAxisLine.y), f64(0), f64(convertedVal / 150))) // TODO: use yAxisLine TODO: change lerpT
            }
        }

        if ctx.pointsPerBucket == 1 {
            for i := 0; i < len(ctx.fileElements)-1; i += 1 {
                el := ctx.fileElements[i]
                if f32(el.timestep) < plotStart {
                    continue
                }
                if f32(el.timestep) > plotEnd {
                    debug_text(i)
                    break
                }

                ctx.pointsData[pointsDataIndex] = get_point_on_plot(ctx, plotStart, plotEnd, el)
                pointsDataIndex += 1
            }

            rl.DrawSplineLinear(raw_data(ctx.pointsData[:]), pointsDataIndex, 3, rl.BLUE)
        }
        else {
            {
                firstEl := ctx.fileElements[0]
                lastEl  := ctx.fileElements[len(ctx.fileElements)-1]
                ctx.pointsData[0] = get_point_on_plot(ctx, plotStart, plotEnd, firstEl)
                ctx.pointsData[bucketsCount-1] = get_point_on_plot(ctx, plotStart, plotEnd, lastEl)
            }

            // Skip ranking first and last bucket
            for i in 1..<bucketsCount-1 {
                nextBucketPoint: rl.Vector2
                if i == bucketsCount-2 { // instead of ranking last bucket - use last value
                    nextBucketPoint = ctx.pointsData[bucketsCount-1]
                } else {
                    timestepAvg, valueAvg: f32
                    nextBucketBegin := (i+1)*ctx.pointsPerBucket
                    nextBucketEnd   := (i+2)*ctx.pointsPerBucket
                    for j in nextBucketBegin..<nextBucketEnd {
                        p := get_point_on_plot(ctx, plotStart, plotEnd, ctx.fileElements[j])
                        timestepAvg += p.x
                        valueAvg    += p.y
                    }
                    nextBucketPoint.x = timestepAvg / f32(ctx.pointsPerBucket)
                    nextBucketPoint.y = valueAvg    / f32(ctx.pointsPerBucket)
                }

                currBucketBegin := i * ctx.pointsPerBucket
                currBucketEnd   := (i+1) * ctx.pointsPerBucket
                bestRank: f32
                bestRankedPoint := get_point_on_plot(ctx, plotStart, plotEnd, ctx.fileElements[currBucketBegin])
                for j in currBucketBegin..<currBucketEnd {
                    pC := get_point_on_plot(ctx, plotStart, plotEnd, ctx.fileElements[j]) // pointCurrent
                    pB := ctx.pointsData[i-1]
                    pN := nextBucketPoint
                    area := abs((pN.x * pC.y - pC.x * pN.y) + (pB.x * pN.y - pN.x * pB.y) + (pC.x * pB.y - pB.x * pC.y)) * 0.5
                    if area > bestRank {
                        bestRank = area
                        bestRankedPoint = pC
                    }
                }
                ctx.pointsData[i] = bestRankedPoint
            }
    
            rl.DrawSplineLinear(raw_data(ctx.pointsData[:]), i32(bucketsCount), 3, rl.BLUE)
        }
    }

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
    delete(ctx.fileElements)
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