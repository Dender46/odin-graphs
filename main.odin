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

// Variables that don't change, and that should be updated on hot reloaded
// Be careful
update_statics :: proc() {
    ctx.graphMargin = 60
    ctx.xAxisLine = {
        x0 = ctx.graphMargin,
        x1 = ctx.window.width - ctx.graphMargin,
        y  = ctx.window.height - ctx.graphMargin - 30,
        orient = .HOR,
    }
    ctx.yAxisLine = {
        x = ctx.graphMargin,
        y0 = ctx.graphMargin,
        y1 = ctx.xAxisLine.y,
        orient = .VER
    }
}

@(export)
game_init :: proc() {
    ctx = new(Context)
    ctx.window = Window{"Raylib Graphs", 1600, 720, 60, {.WINDOW_RESIZABLE, .MSAA_4X_HINT}}

    update_statics()
    ctx.zoomLevel = 60_000
    ctx.zoomLevelTarget = ctx.zoomLevel
    ctx.pointsCount = 2400*1000*10

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
        reserve(&ctx.fileElements, fileSize / 16 * 3)

        if ok1 && len(fileBytes) == int(fileSize) {
            lastts: i64 = 0
            for i in 0..<3 {
                firstTimestep := bytes_to_int64(fileBytes[:8])
    
                for i := 0; i < len(fileBytes); i += 16 {
                    timestep := bytes_to_int64(fileBytes[i:i+8])
    
                    // Mul by 100 to convert from .NET ticks to nanoseconds
                    nanoseconds := (timestep - firstTimestep) * 100
                    // but for now lets keep it to milliseconds range
                    ms := nanoseconds / 1_000_000
    
                    val := bytes_to_int64(fileBytes[i+8:i+16])
                    append(&ctx.fileElements, FileElement{
                        timestep=ms + lastts,
                        value=val
                    })
                }
                lastts = ctx.fileElements[len(ctx.fileElements)-1].timestep
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
        
        GuiSlider_Custom(zoomLevelSliderRect, leftCaption, rightCaption, &ctx.zoomLevelTarget, 10, ctx.pointsCount) //40 mins
    }

    // ========================================
    // Zoom handling
    // ========================================
    if wheelMove := rl.GetMouseWheelMoveV().y; wheelMove != 0 {
        zoomExp :: -0.07
        ctx.zoomLevelTarget *= math.exp(zoomExp * wheelMove)
        ctx.zoomLevelTarget = clamp(ctx.zoomLevelTarget, 10, ctx.pointsCount)
    }
    ctx.zoomLevel = exp_decay(ctx.zoomLevel, ctx.zoomLevelTarget, 16, rl.GetFrameTime())
    ctx.maxValue = exp_decay(ctx.maxValue, ctx.maxValueTarget, 8, rl.GetFrameTime())

    // ========================================
    // Moving
    // ========================================
    if rl.IsMouseButtonDown(.LEFT) && !guiControlExclusiveMode {
        ctx.plotOffset -= remap(f32(0), x_axis_width(), f32(0), ctx.zoomLevel, rl.GetMouseDelta().x)
    }
    ctx.plotOffset = clamp(ctx.plotOffset, 0, ctx.pointsCount-ctx.zoomLevel)

    // ========================================
    // Raylib begin drawing
    // ========================================
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    x_axis_render(ctx.plotOffset, ctx.zoomLevel)
    y_axis_render(ctx.maxValue)

    draw_line(ctx.xAxisLine, GRAPH_COLOR)
    draw_line(ctx.yAxisLine, GRAPH_COLOR)

    // h, m, s, ms := clock_from_nanoseconds(i64(abs(ctx.plotOffset)) * 1_000_000)
    //debug_text("plotOffset:")
    //debug_text(ctx.plotOffset)
    //debug_textf(FORMAT_H_M_S_MS, h, m, s, ms)
    //debug_padding()

    // ========================================
    // Render plot line
    // ========================================
    if true {
        get_point_on_plot :: proc(ctx: ^Context, el: FileElement) -> rl.Vector2 {
            // for testing convert initial values in nanoseconds to milliseconds
            convertedVal := f64(el.value) / 1_000_000
            plotStart := ctx.plotOffset
            plotEnd := ctx.zoomLevel+ctx.plotOffset
            return {
                remap(plotStart, plotEnd, f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), f32(el.timestep)),
                f32(math.lerp(f64(ctx.xAxisLine.y), f64(0), f64(convertedVal) / f64(ctx.maxValue)))
            }
        }

        newMaxValueTarget: f32
        defer ctx.maxValueTarget = newMaxValueTarget * 1.5

        // Indices to points
        loopStart := 0
        loopEnd := len(ctx.fileElements)-1
        {
            for i in 0..<loopEnd {
                if f32(ctx.fileElements[i].timestep) >= ctx.plotOffset {
                    loopStart = i
                    break
                }
            }
            maxTimestep := ctx.zoomLevel+ctx.plotOffset
            if f32(ctx.fileElements[loopEnd].timestep) >= maxTimestep {
                for i in loopStart..<loopEnd {
                    if f32(ctx.fileElements[i].timestep) >= maxTimestep {
                        loopEnd = i
                        break
                    }
                }
            }
        }
        // (╯°□°）╯︵ ┻━┻
        // stupid naive padding of some elements, so that when zoom is really close - render few first and last elements
        // but the trade off, is that lines are drawn outside of its boundry when zoom is too low
        // TODO: to fix this - maybe draw background colored rectangles on the sides?
        loopStart = max(0, loopStart-2)
        loopEnd   = min(len(ctx.fileElements)-1, loopEnd+2)

        maxPointsOnPlot :: 5_000 * 0.5
        ctx.pointsPerBucket = max((loopEnd-loopStart) / (maxPointsOnPlot), 1)
        if ctx.pointsPerBucket > 1 {
            // +2 for min and max points
            ctx.pointsPerBucket += 2
        }

        {
            pointsPerBucket_f := f32(ctx.pointsPerBucket)
            // GuiSlider_Custom({100, 0, 600, 28}, "", "", &pointsPerBucket_f, 5, 100)
            ctx.pointsPerBucket = int(pointsPerBucket_f)
        }

        debug_padding()
        debug_text("loopStart: ", loopStart)
        debug_text("loopEnd: ", loopEnd)
        debug_text("pointsPerBucket: ", ctx.pointsPerBucket)

        if ctx.pointsPerBucket == 1 {
            for i in loopStart..<loopEnd {
                newMaxValueTarget = max(newMaxValueTarget, f32(ctx.fileElements[i].value) / 1_000_000)
                ctx.pointsData[i-loopStart] = get_point_on_plot(ctx, ctx.fileElements[i])
            }

            debug_text("drawn points: ", loopEnd-loopStart)
            rl.DrawSplineLinear(raw_data(ctx.pointsData[:]), i32(loopEnd-loopStart), 3, rl.BLUE)
        }
        else {
            firstBucketIndex := loopStart / ctx.pointsPerBucket
            lastBucketIndex  := loopEnd   / ctx.pointsPerBucket - 1
            bucketsCount := lastBucketIndex - firstBucketIndex + 1

            debug_padding()
            debug_text("firstBucketIndex: ", firstBucketIndex)
            debug_text("lastBucketIndex: ", lastBucketIndex)
            debug_text("bucketsCount: ", bucketsCount)

            {
                firstEl := ctx.fileElements[loopStart]
                lastEl  := ctx.fileElements[loopEnd]
                ctx.pointsData[0] = get_point_on_plot(ctx, firstEl)
                ctx.pointsData[bucketsCount-1] = get_point_on_plot(ctx, lastEl)
            }

            // Skip ranking first and last bucket
            pointsDataIndex := 1
            for i in (firstBucketIndex+1)..<lastBucketIndex {
                nextBucketPoint: rl.Vector2
                if i == lastBucketIndex-2 { // instead of ranking last bucket - use last value
                    nextBucketPoint = ctx.pointsData[bucketsCount-1]
                } else {
                    timestepAvg, valueAvg: f32
                    nextBucketBegin := (i+1)*ctx.pointsPerBucket
                    nextBucketEnd   := (i+2)*ctx.pointsPerBucket
                    for j in nextBucketBegin..<nextBucketEnd {
                        p := get_point_on_plot(ctx, ctx.fileElements[j])
                        timestepAvg += p.x
                        valueAvg    += p.y
                    }
                    nextBucketPoint.x = timestepAvg / f32(ctx.pointsPerBucket)
                    nextBucketPoint.y = valueAvg    / f32(ctx.pointsPerBucket)
                }

                currBucketBegin := i * ctx.pointsPerBucket
                currBucketEnd   := (i+1) * ctx.pointsPerBucket
                temp := get_point_on_plot(ctx, ctx.fileElements[currBucketBegin])

                Point :: struct {
                    point: rl.Vector2,
                    index: int
                }
                currBucket: [2]Point
                currBucket[0].point = temp // min
                currBucket[1].point = temp // max

                for j in currBucketBegin..<currBucketEnd {
                    // TODO: Do we really need to calc area of a triangle? As for lttb algo
                    // pB := ctx.pointsData[pointsDataIndex-1]
                    // pN := nextBucketPoint
                    // area := f64(abs(f64(pN.x * pC.y - pC.x * pN.y) + f64(pB.x * pN.y - pN.x * pB.y) + f64(pC.x * pB.y - pB.x * pC.y)) * 0.5)
                    // if area > bestRank {
                        //     bestRank = area
                        //     currBucket[0].point = pC
                        //     currBucket[0].index = j
                        // }
                    newMaxValueTarget = max(newMaxValueTarget, f32(ctx.fileElements[j].value) / 1_000_000)
                    pC := get_point_on_plot(ctx, ctx.fileElements[j])
                    if pC.y < currBucket[0].point.y { currBucket[0].point = pC; currBucket[0].index = j }
                    if pC.y > currBucket[1].point.y { currBucket[1].point = pC; currBucket[1].index = j }
                }
                slice.sort_by(currBucket[:], proc(i, j: Point) -> bool {
                    return i.index < j.index
                })
                ctx.pointsData[pointsDataIndex] = currBucket[0].point
                ctx.pointsData[pointsDataIndex+1] = currBucket[1].point
                pointsDataIndex += 2
            }

            debug_text("drawn points: ", pointsDataIndex)
            rl.DrawSplineLinear(raw_data(ctx.pointsData[:]), i32(pointsDataIndex), 3, rl.BLUE)
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

    free_all(context.temp_allocator)

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