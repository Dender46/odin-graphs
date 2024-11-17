package graphs

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

x_axis_width :: proc "contextless" () -> f32 {
    return abs(f32(xAxisLine.x1 - xAxisLine.x0))
}

render_x_axis :: proc(plotOffset, offsetX, zoomLevel: f32) {
    plotOffset := -plotOffset
    segmentsCount: f32 = 10
    segmentTime := findAppropriateInterval(zoomLevel, segmentsCount)
    segmentsCount += 2 // increasing count so we can try to draw more segments than expected

    {// Axis X line
        using xAxisLine
        rl.DrawLine(x0, y, x1, y, GRAPH_COLOR)
    }

    buf1 : [MIN_HMSMS_LEN]u8
    segmentsOffsetInTime := math.floor(plotOffset / segmentTime) * segmentTime

    for i := segmentsOffsetInTime;
        i <= segmentsCount * segmentTime + segmentsOffsetInTime;
        i += segmentTime
    {
        pos := i32(remap(plotOffset, zoomLevel + plotOffset, f32(xAxisLine.x0), f32(xAxisLine.x1), i))

        markLineSize: i32 = 15
        rl.DrawLine(pos, xAxisLine.y + markLineSize, pos, xAxisLine.y - markLineSize, GRAPH_COLOR)

        subGraph: LineDimensions = {
           x = pos,
           y0 = xAxisLine.y - markLineSize,
           y1 = graphMargin
        }
        rl.DrawLine(subGraph.x, subGraph.y0, subGraph.x, subGraph.y1, SUB_GRAPH_COLOR)

        time := time_to_string_hmsms(i64(i) * 1_000_000_000, buf1[:])
        draw_centered_text(fmt.caprintf("%s:%s", time[3:5], time[6:8]), pos, xAxisLine.y + markLineSize*2, 0, 16, GRAPH_COLOR)
    }
}

// Figure out decent amount of segments
// in terms of 'seconds in interval' (should be 5, 10, 15, 30, 60, 120, 300...)
@private
findAppropriateInterval :: proc "contextless" (zoomLvl, intervalCount: f32) -> (intervalInS: f32) {
    // To make less segments than we won't - increase slightly segment duration
    @(static) magicFix: f32 = 1.2
    // rl.GuiSlider({0,0,500,50}, "", fmt.caprint(magicFix), &magicFix, 1, 2)
    segmentDuration := zoomLvl / intervalCount * magicFix
    if segmentDuration <= 1 {
        return 1
    }
    if inbetween(segmentDuration, 1, 2) {
        return closesTo(segmentDuration, 1, 2)
    }
    if inbetween(segmentDuration, 2, 5) {
        return closesTo(segmentDuration, 2, 5)
    }
    if inbetween(segmentDuration, 5, 10) {
        return closesTo(segmentDuration, 5, 10)
    }
    if inbetween(segmentDuration, 10, 15) {
        return closesTo(segmentDuration, 10, 15)
    }

    for interval: f32 = 15; interval <= 60; interval *= 2 {
        if inbetween(segmentDuration, interval, interval*2) {
            return closesTo(segmentDuration, interval, interval*2)
        }
    }

    if inbetween(segmentDuration, 120, 300) {
        return closesTo(segmentDuration, 120, 300)
    }

    for interval: f32 = 300; interval <= 900; interval += 300 {
        if inbetween(segmentDuration, interval, interval+300) {
            return closesTo(segmentDuration, interval, interval+300)
        }
    }

    return 0
}