package graphs

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

render_x_axis :: proc(zoomLevel: f32) {
    segmentsCount: f32 = 10
    segmentTime := findAppropriateInterval(zoomLevel, segmentsCount)

    {// Axis X line
        using xAxisLine
        rl.DrawLine(x0, y, x1, y, GRAPH_COLOR)
    }

    buf1 : [MIN_HMSMS_LEN]u8
    segmentTimeAccum: f32 = 0
    for i in 0..=segmentsCount+8 {
        using xAxisLine

        lerpT := segmentTimeAccum / zoomLevel
        if (lerpT > 1.0) {
            rl.DrawText(fmt.caprintf("drawn segments: %.0f", i), i32(x), 150, 20, GRAPH_COLOR)
            break
        }
        pos := i32(math.lerp(f32(x0), f32(x1), lerpT))
        markLineSize: i32 = 15
        rl.DrawLine(pos, y+markLineSize, pos, y-markLineSize, GRAPH_COLOR)

        subGraph: LineDimensions = {
            x = pos,
            y0 = y-markLineSize,
            y1 = graphMargin
        }
        rl.DrawLine(subGraph.x, subGraph.y0, subGraph.x, subGraph.y1, SUB_GRAPH_COLOR)

        time := time_to_string_hmsms(i64(segmentTimeAccum) * 1_000_000_000, buf1[:])
        draw_centered_text(fmt.caprintf("%s:%s", time[3:5], time[6:8]), pos, y+markLineSize*2, 0, 16, GRAPH_COLOR)

        segmentTimeAccum += segmentTime
    }
}

// Figure out decent amount of segments
// in terms of 'seconds in interval' (should be 5, 10, 15, 30, 60, 120, 300...)
@private
findAppropriateInterval :: proc(zoomLvl, intervalCount: f32) -> (intervalInS: f32) {
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