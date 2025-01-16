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
    zoomLevel       : f32,
}

Graph :: struct {
    using settings  : GraphSettings,

    xAxisLine       : LineDimensions,
    yAxisLine       : LineDimensions,

    plotOffset      : f32, // in milliseconds
    zoomLevelTarget : f32, // **DO NOT USE THIS**: only used to calc smoothness

    pointsCount     : f32,
    data            : ^[dynamic][2]i64,
    reducedData     : [dynamic][2]i64,
    pointsBuffer    : [dynamic][2]f32,

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
    return
}

graph_delete :: proc(g:^ Graph) {
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
    if wheelMove := rl.GetMouseWheelMoveV().y; wheelMove != 0 {
        zoomExp :: -0.07
        zoomLevelTarget *= math.exp(zoomExp * wheelMove)
        zoomLevelTarget = clamp(zoomLevelTarget, 10, pointsCount)
    }
    zoomLevel = exp_decay(zoomLevel, zoomLevelTarget, 16, rl.GetFrameTime())
    maxValue = exp_decay(maxValue, graph.maxValueTarget, 8, rl.GetFrameTime())

    // ========================================
    // Moving
    // ========================================
    if rl.IsMouseButtonDown(.LEFT) && !guiControlExclusiveMode {
        plotOffset -= remap(f32(0), x_axis_width(graph), f32(0), zoomLevel, rl.GetMouseDelta().x)
    }
    plotOffset = clamp(plotOffset, 0, pointsCount-zoomLevel)

    // ========================================
    // Render axis
    // ========================================
    x_axis_render(graph)
    y_axis_render(graph)

    draw_line(xAxisLine, GRAPH_COLOR)
    draw_line(yAxisLine, GRAPH_COLOR)

    // ========================================
    // Render plot line
    // ========================================
    newMaxValueTarget: f64
    defer maxValueTarget = newMaxValueTarget * 1.1
    // Indices to data
    loopStart := 0
    loopEnd := len(data)-1
    {
        cmpProc := proc(el: [2]i64, target: f32) -> slice.Ordering {
            return slice.cmp(f32(el[0]), target)
        }
        if f32(loopStart) != plotOffset {
            loopStart, _ = slice.binary_search_by(data[loopStart:loopEnd], plotOffset, cmpProc)
        }
        maxTimestep := zoomLevel+plotOffset
        if f32(data[loopEnd][0]) >= maxTimestep {
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

    pointsBufferSize: i32
    if pointsPerBucket == 1 {
        for i in loopStart..<loopEnd {
            newMaxValueTarget = max(newMaxValueTarget, f64(data[i][1]) / 1_000_000)
            pointsBuffer[i-loopStart] = get_point_on_graph(graph, data[i])
        }

        pointsBufferSize = i32(loopEnd-loopStart)
    } else {
        pointsBufferSize = graph_decimate_data(graph, loopStart, loopEnd)
        for i in 0..<pointsBufferSize {
            newMaxValueTarget = max(newMaxValueTarget, f64(reducedData[i][1]) / 1_000_000)
            pointsBuffer[i] = get_point_on_graph(graph, reducedData[i])
        }
    }

    debug_text("drawn points: ", pointsBufferSize)
    rl.DrawSplineLinear(raw_data(pointsBuffer[:]), pointsBufferSize, 3, rl.BLUE)
}

@(private)
graph_decimate_data :: proc(g: ^Graph, loopStart, loopEnd: int) -> (pointsBufferSize: i32) {
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
    pointsBufferSize = i32(pointsBufferIndex)
    return
}

@(private)
get_point_on_graph :: proc(g: ^Graph, el: [2]i64) -> [2]f32 {
    // for testing convert initial values in nanoseconds to milliseconds
    convertedVal := f64(el[1]) / 1_000_000
    plotStart := g.plotOffset
    plotEnd := g.zoomLevel + g.plotOffset
    return {
        remap(plotStart, plotEnd, f32(g.xAxisLine.x0), f32(g.xAxisLine.x1), f32(el[0])),
        remap(f32(0), f32(g.maxValue), f32(g.yAxisLine.y1), f32(g.yAxisLine.y0), f32(convertedVal))
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
    segmentsCount: f32 = 10
    segmentTime := find_appropriate_time_interval(g.zoomLevel, segmentsCount)
    segmentsCount += 8 // increasing count so we can try to draw more segments than expected

    segmentsOffsetInTime := math.floor(g.plotOffset / segmentTime) * segmentTime
    lastSegmentTime := segmentsCount * segmentTime + segmentsOffsetInTime

    for i := segmentsOffsetInTime;
        i <= lastSegmentTime;
        i += segmentTime
    {
        pos := i32(remap(g.plotOffset, g.zoomLevel + g.plotOffset, f32(g.xAxisLine.x0), f32(g.xAxisLine.x1), i))
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
find_appropriate_time_interval :: proc (zoomLvl, intervalCount: f32) -> (intervalInMS: f32) {
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
        return f32(d+1) * 2 * HOUR
    }

    return
}