package graphs

import "core:fmt"
import "core:math"
import "core:slice"
import rl "vendor:raylib"

GRAPH_COLOR         :: rl.DARKGRAY
SUB_GRAPH_COLOR     :: rl.LIGHTGRAY

GraphBoundaries :: struct {
    using rect      : rl.Rectangle,
    padding         : f32,
}

GraphSettings :: struct {
    boundaries      : GraphBoundaries,
    zoomLevel       : f64,
}

Graph :: struct {
    using settings  : GraphSettings,

    xAxisLine       : LineDimensions,
    yAxisLine       : LineDimensions,

    plotOffset      : f64, // in milliseconds
    zoomLevelTarget : f64, // **DO NOT USE THIS**: only used to calc smoothness

    mouseWidgetAlpha: f32,
    mousePosPlotTarget: rl.Vector2, // **DO NOT USE THIS**: only used to calc smoothness
    mouseClosesToIdx: i32,

    pointsCount     : f32,
    data            : ^[dynamic][2]i64,
    reducedData     : [dynamic][2]i64,
    pointsBuffer    : [dynamic][2]f32,
    pointsBufferSize: i32,

    pointsPerBucket : int,
    maxValue        : f64,
    maxValueTarget  : f64,
}

graph_init :: proc(settings: GraphSettings, data: ^[dynamic][2]i64) -> (graph: Graph) {
    graph.settings = settings

    graph.zoomLevelTarget = settings.zoomLevel

    graph.data = data
    graph.pointsBuffer = make([dynamic][2]f32, len(data)) // TODO: We probably don't need to allocate that much
    graph.reducedData = make([dynamic][2]i64, len(data))  // TODO: Same as here ^^^
    graph.pointsCount = f32(data[len(data)-1][0]) * 1.1   // TODO: Add option of how much user wants to scroll on x axis

    graph.xAxisLine.orient = .HOR
    graph.yAxisLine.orient = .VER

    graph_update(&graph)
    // Init values that will be used in the next `graph_update()` and `graph_draw()` calls
    graph.maxValue = graph.maxValueTarget

    return
}

graph_delete :: proc(g:^ Graph) {
    g.data = nil
    delete(g.pointsBuffer)
    delete(g.reducedData)
}

graph_update :: proc(graph: ^Graph) {
    using graph
    {
        using boundaries
        // Additional padding for content of graph. Content is dependant on position and size of axis
        xAxisLine.x0 = i32(x + padding) + 65
        xAxisLine.x1 = i32(x + width - padding)
        xAxisLine.y  = i32(y + height - padding) - 50

        yAxisLine.x = i32(x + padding) + 65
        yAxisLine.y0 = i32(y + padding)
        yAxisLine.y1 = i32(y + height - padding) - 50
    }

    // ========================================
    // Zoom handling
    // ========================================
    if wheelMove := f64(rl.GetMouseWheelMoveV().y); wheelMove != 0 {
        zoomExp :: -0.07
        zoomLevelTarget *= math.exp(zoomExp * wheelMove)
        zoomLevelTarget = clamp(zoomLevelTarget, 10, f64(pointsCount))
    }
    zoomLevel = exp_decay(zoomLevel, zoomLevelTarget, 16, rl.GetFrameTime())

    // ========================================
    // Moving
    // ========================================
    {
        @static moveDelta: f32
        @static keyboardScrollFadeSpeed: f32
        switch {
            // mouse
            case rl.IsMouseButtonDown(.LEFT) && !guiControlExclusiveMode : {
                moveDelta = rl.GetMouseDelta().x
            }
            case rl.IsMouseButtonReleased(.LEFT) : {
                moveDelta = 0
            }
            // keyboard
            case rl.IsKeyPressed(.A) || rl.IsKeyPressedRepeat(.A) : {
                moveDelta = 20
            }
            case rl.IsKeyPressed(.D) || rl.IsKeyPressedRepeat(.D) : {
                moveDelta = -20
            }
        }

        moveDelta = exp_decay(moveDelta, 0, 16, rl.GetFrameTime()) // this is only if scrolling by keyboard
        debug_text("moveDelta: ", moveDelta)
        if moveDelta != 0 {
            plotOffset -= remap(f64(0), f64(x_axis_width(graph)), 0, f64(zoomLevel), f64(moveDelta))
        }
        plotOffset = clamp(plotOffset, 0, f64(pointsCount)-zoomLevel)
    }

    // ====================================================================
    // Reduce, if needed, and remap data to screen points buffer
    // ====================================================================
    // Indices to data
    loopStart := 0
    loopEnd := len(data)-1
    {
        cmpProc := proc(el: [2]i64, target: f64) -> slice.Ordering {
            return slice.cmp(el[0], i64(target))
        }
        if f64(loopStart) != plotOffset {
            loopStart, _ = slice.binary_search_by(data[loopStart:loopEnd], plotOffset, cmpProc)
        }
        maxTimestep := zoomLevel+plotOffset
        if f64(data[loopEnd][0]) >= maxTimestep {
            loopEnd, _ = slice.binary_search_by(data[:loopEnd], maxTimestep, cmpProc)
        }
    }
    // (╯°□°）╯︵ ┻━┻
    // stupid naive padding of some elements, so that when zoom is really close - render few first and last elements
    // but the trade off, is that lines are drawn outside of its boundry when zoom is too low
    // TODO: to fix this - maybe draw background colored rectangles on the sides?
    loopStart = max(0, loopStart-2)
    loopEnd   = min(len(data)-1, loopEnd+2)

    maxPointsOnGraph :: 3000 // actual max count of points will be either 1.333x or 1.5x more. Sweet spot is value 3000
    newPointsPerBucket := max((loopEnd-loopStart) / (maxPointsOnGraph / 2), 1)
    {
        // Get two right-most bits of a value to get more gradular change when scrolling in/out
        hibit := int(hi_bit(u32(newPointsPerBucket)))
        newPointsPerBucket = hibit | (newPointsPerBucket & (hibit >> 1))
    }
    pointsPerBucket = newPointsPerBucket

    debug_padding()
    debug_text("loopStart: ", loopStart)
    debug_text("loopEnd: ", loopEnd)
    debug_text("pointsPerBucket: ", pointsPerBucket)
    debug_padding()

    mousePosScreenX := rl.GetMousePosition().x
    mousePosScreenX = clamp(mousePosScreenX, f32(graph.xAxisLine.x0), f32(graph.xAxisLine.x1))
    mousePosScreenX = remap(f32(graph.xAxisLine.x0), f32(graph.xAxisLine.x1), f32(graph.plotOffset), f32(graph.plotOffset+graph.zoomLevel), mousePosScreenX)
    debug_text("mousePosScreenX: ", mousePosScreenX)

    newMaxValueTarget: f64
    defer {
        maxValueTarget = newMaxValueTarget * 1.1
        graph.maxValue = exp_decay(graph.maxValue, graph.maxValueTarget, 8, rl.GetFrameTime())
    }

    minDistToMouse: f32 = max(f32)
    if pointsPerBucket == 1 {
    // if false {
        pointsBufferSize = i32(loopEnd-loopStart)
        for i in loopStart..<loopEnd {
            // finding index of datapoint closest to the mouse
            distToMouse := abs(f32(data[i][0]) - mousePosScreenX)
            if minDistToMouse > distToMouse {
                mouseClosesToIdx = i32(i - loopStart) // -loopStart because we want index of plotted points
                minDistToMouse = distToMouse
            }

            newMaxValueTarget = max(newMaxValueTarget, f64(data[i][1]) / 1_000_000)
            pointsBuffer[i-loopStart] = get_point_on_graph(graph, data[i])
        }
    } else {
        graph_decimate_data(graph, loopStart, loopEnd)
        for i in 0..<pointsBufferSize {
            // finding index of datapoint closest to the mouse
            distToMouse := abs(f32(reducedData[i][0]) - mousePosScreenX)
            if minDistToMouse > distToMouse {
                mouseClosesToIdx = i32(i)
                minDistToMouse = distToMouse
            }

            newMaxValueTarget = max(newMaxValueTarget, f64(reducedData[i][1]) / 1_000_000)
            pointsBuffer[i] = get_point_on_graph(graph, reducedData[i])
        }
    }
}

@(private)
graph_draw :: proc(g: ^Graph) {
    // ========================================
    // Render axis
    // ========================================
    x_axis_render(g)
    y_axis_render(g)

    draw_line(g.xAxisLine, GRAPH_COLOR)
    draw_line(g.yAxisLine, GRAPH_COLOR)

    // =====================================================================
    // Render plotline
    //=====================================================================
    debug_text("drawn points: ", g.pointsBufferSize)
    rl.DrawSplineLinear(raw_data(g.pointsBuffer[:]), g.pointsBufferSize, 3, rl.BLUE)

    // =====================================================================
    // Render widget of datapoint and circle highlighter on the plot
    //=====================================================================
    {
        mousePosPlot := rl.Vector2{ g.pointsBuffer[g.mouseClosesToIdx].x, g.pointsBuffer[g.mouseClosesToIdx].y }
        // Highlighter on the plot
        rl.DrawCircle(i32(mousePosPlot.x), i32(mousePosPlot.y), 6, rl.BLUE)

        // Init target value if not inited
        if g.mousePosPlotTarget == {0, 0} {
            g.mousePosPlotTarget = mousePosPlot
        }
        g.mousePosPlotTarget = exp_decay(g.mousePosPlotTarget, mousePosPlot, 22, rl.GetFrameTime())

        // Widget alpha fade-in/out
        mousePos := rl.GetMousePosition()
        if rl.Vector2Distance(mousePos, mousePosPlot) < 200 {
            g.mouseWidgetAlpha += rl.GetFrameTime() * 15
        } else {
            g.mouseWidgetAlpha -= rl.GetFrameTime() * 15
        }
        g.mouseWidgetAlpha = clamp(g.mouseWidgetAlpha, 0.0, 0.7)
        widgetBgColor := rl.ColorAlpha(rl.ColorBrightness(rl.BLUE, 0.3), g.mouseWidgetAlpha) // lighter blue
        widgetTextColor := rl.ColorAlpha(rl.DARKBLUE, g.mouseWidgetAlpha)

        // Draw little triangle pointer from widget to plot
        g.mousePosPlotTarget.y -= 5
        rl.DrawTriangle(
            { g.mousePosPlotTarget.x, g.mousePosPlotTarget.y },
            { g.mousePosPlotTarget.x + 10, g.mousePosPlotTarget.y - 10 },
            { g.mousePosPlotTarget.x - 10, g.mousePosPlotTarget.y - 10 },
            widgetBgColor
        )

        // Draw widget rectangle
        g.mousePosPlotTarget.y -= 10
        width: f32 = 260 // TODO: Adjust to text size?
        height: f32 = 75
        widgetRect := rl.Rectangle{
            g.mousePosPlotTarget.x - width/2, g.mousePosPlotTarget.y - height,
            width, height
        }
        rl.DrawRectangleRounded(widgetRect, 0.2, 5, widgetBgColor)

        // Draw text
        plotDataObject := g.reducedData[g.mouseClosesToIdx]
        xAxisText := fmt.ctprintf("Time: " + FORMAT_H_M_S_MS, clock_from_nanoseconds(i64(plotDataObject[0]) * 1_000_000))
        yAxisText := fmt.ctprint("Value: ", plotDataObject[0])
        xPos := i32(widgetRect.x) + 15
        yPos := i32(widgetRect.y) + 15
        rl.DrawText(xAxisText, xPos, yPos, 20, widgetTextColor)
        yPos += 25
        rl.DrawText(yAxisText, xPos, yPos, 20, widgetTextColor)

    }
}

@(private)
graph_decimate_data :: proc(g: ^Graph, loopStart, loopEnd: int) {
    using g
    firstBucketIndex := loopStart / pointsPerBucket
    lastBucketIndex  := loopEnd   / pointsPerBucket - 1
    bucketsCount := lastBucketIndex - firstBucketIndex + 1

    debug_padding()
    debug_text("firstBucketIndex: ", firstBucketIndex)
    debug_text("lastBucketIndex: ", lastBucketIndex)
    debug_text("bucketsCount: ", bucketsCount)
    debug_padding()

    // Set first and last points (first and last bucket)
    reducedData[0] = data[loopStart]
    reducedData[bucketsCount-1] = data[loopEnd]

    // Skip ranking first and last bucket
    pointsBufferIndex := 1
    for i in (firstBucketIndex+1)..<lastBucketIndex {
        // TODO: this is a part of lttb algo, but since we use min/max, we don't need to know next point
        // nextBucketPoint: [2]i64
        // if i == lastBucketIndex-2 { // instead of ranking last bucket - use last value
        //     nextBucketPoint = reducedData[bucketsCount-1]
        // } else {
        //     timestepAvg, valueAvg: i64
        //     nextBucketBegin := (i+1)*pointsPerBucket
        //     nextBucketEnd   := (i+2)*pointsPerBucket
        //     for j in nextBucketBegin..<nextBucketEnd {
        //         timestepAvg += data[j][0]
        //         valueAvg    += data[j][1]
        //     }
        //     nextBucketPoint.x = timestepAvg / i64(pointsPerBucket)
        //     nextBucketPoint.y = valueAvg    / i64(pointsPerBucket)
        // }

        currBucketBegin := i * pointsPerBucket
        currBucketEnd   := (i+1) * pointsPerBucket
        temp := data[currBucketBegin]

        Point :: struct {
            point: [2]i64,
            index: int
        }
        currBucket: [2]Point
        currBucket[0].point = temp // min
        currBucket[1].point = temp // max

        for j in currBucketBegin..<currBucketEnd {
            // TODO: Do we really need to calc area of a triangle as for lttb algo? It's more expensive that just min/max
            // pB := reducedData[pointsBufferIndex-1]
            // pN := nextBucketPoint
            // area := f64(abs(f64(pN.x * pC.y - pC.x * pN.y) + f64(pB.x * pN.y - pN.x * pB.y) + f64(pC.x * pB.y - pB.x * pC.y)) * 0.5)
            // if area > bestRank {
                //     bestRank = area
                //     currBucket[0].point = pC
                //     currBucket[0].index = j
                // }
            pC := data[j]
            if pC.y < currBucket[0].point.y { currBucket[0].point = pC; currBucket[0].index = j }
            if pC.y > currBucket[1].point.y { currBucket[1].point = pC; currBucket[1].index = j }
        }
        slice.sort_by(currBucket[:], proc(i, j: Point) -> bool {
            return i.index < j.index
        })
        reducedData[pointsBufferIndex] = currBucket[0].point
        reducedData[pointsBufferIndex+1] = currBucket[1].point
        pointsBufferIndex += 2
    }
    g.pointsBufferSize = i32(pointsBufferIndex)
    return
}

@(private)
get_point_on_graph :: proc(g: ^Graph, el: [2]i64) -> rl.Vector2 {
    // for testing convert initial values in nanoseconds to milliseconds
    convertedVal := f64(el[1]) / 1_000_000
    plotStart := g.plotOffset
    plotEnd := g.zoomLevel + g.plotOffset
    return {
        f32(remap(plotStart, plotEnd, f64(g.xAxisLine.x0), f64(g.xAxisLine.x1), f64(el[0]))),
        f32(remap(f64(0), g.maxValue, f64(g.yAxisLine.y1), f64(g.yAxisLine.y0), f64(convertedVal)))
    }
}

y_axis_height :: proc "contextless" (g: ^Graph) -> f32 {
    using g
    return abs(f32(yAxisLine.y1 - yAxisLine.y0))
}

x_axis_width :: proc "contextless" (g: ^Graph) -> f32 {
    using g
    return abs(f32(xAxisLine.x1 - xAxisLine.x0))
}

x_axis_render :: proc(g: ^Graph) {
    segmentTime := find_appropriate_time_interval(g.zoomLevel)

    segmentsOffsetInTime := math.floor(g.plotOffset / segmentTime) * segmentTime
    segmentsCount: f64 = 18 // increasing count so we can try to draw more segments than expected
    lastSegmentTime := segmentsCount * segmentTime + segmentsOffsetInTime

    for i := segmentsOffsetInTime;
        i <= lastSegmentTime;
        i += segmentTime
    {
        pos := i32(remap(g.plotOffset, g.zoomLevel + g.plotOffset, f64(g.xAxisLine.x0), f64(g.xAxisLine.x1), f64(i)))
        if g.xAxisLine.x0 > pos {
            continue
        }
        if pos > g.xAxisLine.x1 {
            break
        }

        segmentLine := LineDimensions {
           x = pos,
           y0 = g.xAxisLine.y - markLineSize,
           y1 = g.yAxisLine.y,
           orient = .VER,
        }
        draw_line(segmentLine, SUB_GRAPH_COLOR)

        markLineSize: i32 : 12
        segmentLineMark := LineDimensions {
            x = pos,
            y0 = g.xAxisLine.y + markLineSize,
            y1 = g.xAxisLine.y - markLineSize,
            orient = .VER,
        }
        draw_line(segmentLineMark, GRAPH_COLOR)

        h, m, s, ms := clock_from_nanoseconds(i64(i) * 1_000_000)
        graphHintLabel: cstring
        switch {
            case h == 0 && m == 0 && s <=5  : graphHintLabel = fmt.ctprintf(FORMAT_S_MS, s, ms)
            case h == 0 && m >= 0 && s >= 0 : graphHintLabel = fmt.ctprintf(FORMAT_M_S, m, s)
            case h > 0                      : graphHintLabel = fmt.ctprintf(FORMAT_H_M, h, m)
        }

        draw_centered_text(graphHintLabel, pos, g.xAxisLine.y + markLineSize*2, 0, 20, SUB_GRAPH_COLOR)
    }
}

y_axis_render :: proc(g: ^Graph) {
    segmentSize := f32(math.pow(10, math.floor(math.log10(g.maxValue))))
    segmentSizeInView := remap(f32(0), f32(g.maxValue), f32(0), y_axis_height(g), segmentSize)
    segmentsCount := y_axis_height(g) / segmentSizeInView

    if segmentsCount <= 5 {
        segmentSize /= 2
        segmentsCount *= 2
    }

    if segmentsCount <= 3 {
        segmentSize /= 2
        segmentsCount *= 2
    }

    for i: f32 = 0; i < segmentSize*segmentsCount; i += segmentSize {
        pos := i32(remap(f32(0), f32(g.maxValue), f32(g.yAxisLine.y1), f32(g.yAxisLine.y0), i))

        segmentLine := LineDimensions {
            x0 = g.xAxisLine.x0,
            x1 = g.xAxisLine.x1,
            y = pos,
            orient = .HOR
        }
        draw_line(segmentLine, SUB_GRAPH_COLOR)

        markLineSize: i32 : 12
        segmentLineMark := LineDimensions {
            x0 = g.yAxisLine.x - markLineSize,
            x1 = g.yAxisLine.x + markLineSize,
            y = pos,
            orient = .HOR
        }
        draw_line(segmentLineMark, GRAPH_COLOR)

        draw_right_text(fmt.ctprintf("%.0f", i), g.yAxisLine.x-7, pos-markLineSize, 0, 20, SUB_GRAPH_COLOR)
    }

    // pos := i32(remap(f32(0), maxValue, f32(ctx.yAxisLine.y1), f32(ctx.yAxisLine.y0), maxValue))
    // draw_right_text(fmt.ctprintf("%.0f", maxValue), ctx.yAxisLine.x, pos, 0, 20, GRAPH_COLOR)
    // draw_horizontal_line(ctx, pos, rl.GREEN)
}

// Figure out decent amount of segments
// in terms of 'seconds in interval' (should be 5, 10, 15, 30, 60, 120, 300...)
@(private)
find_appropriate_time_interval :: proc (zoomLvl: f64) -> (intervalInMS: f64) {
    d, h, m, s, ms := clock_from_nanoseconds_ex(i64(zoomLvl) * 1_000_000)

    MILLISECOND :: 1
    SECOND :: MILLISECOND * 1000
    MINUTE :: SECOND * 60
    HOUR :: MINUTE * 60
    if d == 0 && h == 0 && m == 0 && s == 0 {
        switch {
            case ms <= 10  : return MILLISECOND
            case ms <= 20  : return 2*MILLISECOND
            case ms <= 50  : return 5*MILLISECOND
            case ms <= 100 : return 10*MILLISECOND
            case ms <= 200 : return 20*MILLISECOND
            case ms <= 500 : return 50*MILLISECOND
            case ms <= 1000: return 100*MILLISECOND
        }
    } else if d == 0 && h == 0 && m == 0 && s < 60 {
        switch {
            case s <= 2  : return 200*MILLISECOND
            case s <= 5  : return 500*MILLISECOND
            case s <= 12 : return SECOND
            case s <= 30 : return 2*SECOND
            case s <= 60 : return 5*SECOND
        }
    } else if d == 0 && h == 0 && m < 60 {
        switch {
            case m < 2  : return 10*SECOND
            case m < 3  : return 15*SECOND
            case m < 6  : return 30*SECOND
            case m < 12 : return MINUTE
            case m < 30 : return 2*MINUTE
            case m < 60 : return 5*MINUTE
        }
    } else if d == 0 && h < 24 {
        switch {
            case h < 2  : return 10*MINUTE
            case h < 4  : return 15*MINUTE
            case h < 8  : return 30*MINUTE
            case h < 12 : return HOUR
            case h < 24 : return HOUR+ 30*MINUTE
        }
    } else if d < 30 {
        debug_text("days: ", d)
        // TODO: keep handling the same way?
        return f64(d+1) * 2 * HOUR
    }

    return
}