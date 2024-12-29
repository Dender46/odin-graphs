package graphs

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

y_axis_height :: proc "contextless" () -> f32 {
    return abs(f32(ctx.yAxisLine.y1 - ctx.yAxisLine.y0))
}

x_axis_width :: proc "contextless" () -> f32 {
    return abs(f32(ctx.xAxisLine.x1 - ctx.xAxisLine.x0))
}

x_axis_render :: proc(plotOffset, zoomLevel: f32) {
    segmentsCount: f32 = 10
    segmentTime := find_appropriate_time_interval(zoomLevel, segmentsCount)
    segmentsCount += 8 // increasing count so we can try to draw more segments than expected

    segmentsOffsetInTime := math.floor(plotOffset / segmentTime) * segmentTime
    lastSegmentTime := segmentsCount * segmentTime + segmentsOffsetInTime

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

        markLineSize: i32 : 15
        segmentLineMark := LineDimensions {
            x = pos,
            y0 = ctx.xAxisLine.y + markLineSize,
            y1 = ctx.xAxisLine.y - markLineSize,
            orient = .VER,
        }
        draw_line(segmentLineMark, GRAPH_COLOR)

        segmentLine := LineDimensions {
           x = pos,
           y0 = ctx.xAxisLine.y - markLineSize,
           y1 = ctx.graphMargin,
           orient = .VER,
        }
        draw_line(segmentLine, SUB_GRAPH_COLOR)

        h, m, s, ms := clock_from_nanoseconds(i64(i) * 1_000_000)
        graphHintLabel: cstring
        switch {
            case h == 0 && m == 0 && s <=5  : graphHintLabel = fmt.ctprintf(FORMAT_S_MS, s, ms)
            case h == 0 && m >= 0 && s >= 0 : graphHintLabel = fmt.ctprintf(FORMAT_M_S, m, s)
            case h > 0                      : graphHintLabel = fmt.ctprintf(FORMAT_H_M, h, m)
        }

        draw_centered_text(graphHintLabel, pos, ctx.xAxisLine.y + markLineSize*2, 0, 20, SUB_GRAPH_COLOR)
    }
}

y_axis_render :: proc(maxValue: f32) {
    segmentsCount: f32 = 10
    segmentSize := math.pow(10, math.floor(math.log10(maxValue)))

    for i: f32 = 0; i < segmentSize*segmentsCount; i += segmentSize {
        pos := i32(remap(f32(0), maxValue, f32(ctx.yAxisLine.y1), f32(ctx.yAxisLine.y0), i))
        // -1 to add padding for top most segment
        if pos < ctx.yAxisLine.x0 - 1 {
            break
        }

        markLineSize: i32 : 15
        segmentLineMark := LineDimensions {
            x0 = ctx.yAxisLine.x - markLineSize,
            x1 = ctx.yAxisLine.x + markLineSize,
            y = pos,
            orient = .HOR
        }
        draw_line(segmentLineMark, GRAPH_COLOR)

        segmentLine := LineDimensions {
           x0 = ctx.xAxisLine.x0,
           x1 = ctx.xAxisLine.x1,
           y = pos,
           orient = .HOR
        }
        draw_line(segmentLine, SUB_GRAPH_COLOR)

        draw_right_text(fmt.ctprintf("%.0f", i), ctx.yAxisLine.x, pos-markLineSize, 0, 20, SUB_GRAPH_COLOR)
    }

    // pos := i32(remap(f32(0), maxValue, f32(ctx.yAxisLine.y1), f32(ctx.yAxisLine.y0), maxValue))
    // draw_right_text(fmt.ctprintf("%.0f", maxValue), ctx.yAxisLine.x, pos, 0, 20, GRAPH_COLOR)
    // draw_horizontal_line(ctx, pos, rl.GREEN)
}

// Figure out decent amount of segments
// in terms of 'seconds in interval' (should be 5, 10, 15, 30, 60, 120, 300...)
@private
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