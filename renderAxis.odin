package graphs

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

x_axis_width :: proc "contextless" () -> f32 {
    return abs(f32(ctx.xAxisLine.x1 - ctx.xAxisLine.x0))
}

render_x_axis :: proc(plotOffset, offsetX, zoomLevel: f32) {
    plotOffset := -plotOffset
    segmentsCount: f32 = 10
    segmentTime := findAppropriateInterval(zoomLevel, segmentsCount)
    segmentsCount += 8 // increasing count so we can try to draw more segments than expected

    {// Axis X line
        using ctx.xAxisLine
        rl.DrawLine(x0, y, x1, y, GRAPH_COLOR)
    }

    segmentsOffsetInTime := math.floor(plotOffset / segmentTime) * segmentTime

    lastSegmentTime := segmentsCount * segmentTime + segmentsOffsetInTime
    debug_textf("segmentTime: %f", segmentTime)

    for i := segmentsOffsetInTime;
        i <= lastSegmentTime;
        i += segmentTime
    {
        pos := i32(remap(plotOffset, zoomLevel + plotOffset, f32(ctx.xAxisLine.x0), f32(ctx.xAxisLine.x1), i))
        if ctx.xAxisLine.x0 > pos {
            continue
        }
        if pos > ctx.xAxisLine.x1 {
            break
        }

        markLineSize: i32 = 15
        rl.DrawLine(pos, ctx.xAxisLine.y + markLineSize, pos, ctx.xAxisLine.y - markLineSize, GRAPH_COLOR)

        subGraph: LineDimensions = {
           x = pos,
           y0 = ctx.xAxisLine.y - markLineSize,
           y1 = ctx.graphMargin
        }
        rl.DrawLine(subGraph.x, subGraph.y0, subGraph.x, subGraph.y1, SUB_GRAPH_COLOR)

        h, m, s, ms := clock_from_nanoseconds(i64(i) * 1_000_000)
        graphHintLabel: cstring
        switch {
            case h == 0 && m == 0 && s <=5  : graphHintLabel = fmt.ctprintf("%02v.%03v", s, ms)
            case h == 0 && m >= 0 && s >= 0 : graphHintLabel = fmt.ctprintf("%02v:%02v", m, s)
            case h > 0                      : graphHintLabel = fmt.ctprintf("%02v:%02v", h, m)
        }

        draw_centered_text(graphHintLabel, pos, ctx.xAxisLine.y + markLineSize*2, 0, 20, GRAPH_COLOR)
    }
}

// Figure out decent amount of segments
// in terms of 'seconds in interval' (should be 5, 10, 15, 30, 60, 120, 300...)
@private
findAppropriateInterval :: proc (zoomLvl, intervalCount: f32) -> (intervalInMS: f32) {
    defer {
        debug_textf("zoomLvl: %f", zoomLvl)

        h, m, s, ms := clock_from_nanoseconds(i64(intervalInMS) * 1_000_000)
        switch {
            case h == 0 && m == 0 && s <=5  : debug_textf("%02vs.%03vms", s, ms)
            case h == 0 && m >= 0 && s >= 0 : debug_textf("%02vm:%02vs", m, s)
            case h > 0                      : debug_textf("%02vh:%02vm", h, m)
        }
        debug_padding()
        debug_textf("intervalInMS: %f", intervalInMS)
    }

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
        return f32(d+1) * 2 * HOUR
    }

    return
}