package graphs

import "core:math"
import "core:fmt"
import rl "vendor:raylib"

DEBUG_BOUNDARY :: false

// =============== RAYLIB ===============

// These values are identical in raygui.h, but they are static to that file and not exposed
// they are recreated here so we can have same functionality
guiControlExclusiveMode := false
guiControlExclusiveRec := rl.Rectangle{ 0, 0, 0, 0 }

LineDimensions_Orient :: enum { NONE, HOR, VER }

LineDimensions :: struct {
    using _ : struct #raw_union {
        using _: struct { x0, x1: i32 },
        x: i32
    },
    using _ : struct #raw_union {
        using _: struct { y0, y1: i32 },
        y: i32
    },
    orient: LineDimensions_Orient
}

draw_line :: proc(line: LineDimensions, color: rl.Color) {
    using line
    switch orient {
        case .HOR:  rl.DrawLine(line.x0, line.y, line.x1, line.y, color)
        case .VER:  rl.DrawLine(line.x, line.y0, line.x, line.y1, color)
        case .NONE: rl.DrawLine(line.x0, line.y0, line.x1, line.y1, color)
    }
}

draw_centered_text :: proc "contextless" (text: cstring, posX, posY: i32, rot, fontSize: f32, tint: rl.Color) {
    spacing := fontSize / 10
    textSize := rl.MeasureTextEx(rl.GetFontDefault(), text, fontSize, spacing)
    pivot := textSize / 2
    when DEBUG_BOUNDARY {
        rl.DrawRectanglePro({f32(posX), f32(posY), textSize.x, textSize.y}, pivot, rot, rl.ColorAlpha(rl.RED, 0.3))
    }
    rl.DrawTextPro(rl.GetFontDefault(), text, {f32(posX), f32(posY)}, pivot, rot, fontSize, spacing, tint)
}

draw_right_text :: proc "contextless" (text: cstring, posX, posY: i32, rot, fontSize: f32, tint: rl.Color) {
    spacing := fontSize / 10
    textSize := rl.MeasureTextEx(rl.GetFontDefault(), text, fontSize, spacing)
    pivot := textSize
    pivot.y *= 0.5
    when DEBUG_BOUNDARY {
        rl.DrawRectanglePro({f32(posX), f32(posY), textSize.x, textSize.y}, pivot, rot, rl.ColorAlpha(rl.RED, 0.3))
    }
    rl.DrawTextPro(rl.GetFontDefault(), text, {f32(posX), f32(posY)}, pivot, rot, fontSize, spacing, tint)
}

draw_vertical_line :: proc "contextless" (ctx: ^Context, x: i32, color: rl.Color) {
    rl.DrawLine(x, 0, x, ctx.window.height, color)
}

draw_horizontal_line :: proc "contextless" (ctx: ^Context, y: i32, color: rl.Color) {
    rl.DrawLine(0, y, ctx.window.width, y, color)
}

debugTextYOffset: i32 = 30
reset_debug_text_state :: proc() {
    debugTextYOffset = 30
}

debug_padding :: proc() {
    debugTextYOffset += 10
}

debug_text :: proc(args: ..any) {
    rl.DrawText(fmt.ctprint(..args), 3, debugTextYOffset, 20, rl.BLACK)
    debugTextYOffset += 20
}

debug_textf :: proc(f: string, args: ..any) {
    rl.DrawText(fmt.ctprintf(f, ..args), 3, debugTextYOffset, 20, rl.BLACK)
    debugTextYOffset += 20
}

// Sets guiControlExclusiveMode, guiControlExclusiveRec, so we can tell if element is being manipulated
// even if mouse cursor is outside bounds of slider
GuiSlider_Custom :: proc(bounds: rl.Rectangle, textLeft: cstring, textRight: cstring, value: ^f32, minValue: f32, maxValue: f32) {
    rl.GuiSlider(bounds, textLeft, textRight, value, minValue, maxValue)

    if rl.GuiState(rl.GuiGetState()) != .STATE_DISABLED && !rl.GuiIsLocked() {
        mousePoint := rl.GetMousePosition();

        if guiControlExclusiveMode { // Allows to keep dragging outside of bounds
            if !rl.IsMouseButtonDown(.LEFT) {
                guiControlExclusiveMode = false;
                guiControlExclusiveRec = rl.Rectangle{ 0, 0, 0, 0 }
            }
        }
        else if rl.CheckCollisionPointRec(mousePoint, bounds) {
            if rl.IsMouseButtonDown(.LEFT) {
                guiControlExclusiveMode = true;
                guiControlExclusiveRec = bounds; // Store bounds as an identifier when dragging starts
            }
        }
    }
}

// =============== MATH ===============

// Freya's smooth lerp
// a - from
// b - to
// decay - approx. from 1 (slow) to 25 (fast)
// dt - deltaTime
exp_decay :: proc "contextless" (a, b: $T, decay, dt: f32) -> T {
    return b + (a - b) * T(math.exp(-decay * dt))
}

inv_lerp :: proc "contextless" (a, b, val: $T) -> T {
    return (val - a) / (b - a)
}

remap :: proc "contextless" (iMin, iMax, oMin, oMax, val: $T) -> T {
    t := inv_lerp(iMin, iMax, val)
    return math.lerp(oMin, oMax, t)
}

// =============== OTHER ===============

inbetween :: proc "contextless" (val, a, b: f32) -> bool {
    return a <= val && val <= b
}
closesTo :: proc "contextless" (val, a, b: f32) -> f32 {
    diffA := abs(val - a)
    diffB := abs(val - b)
    if diffA < diffB { return a }
    return b
}

bytes_to_int64 :: proc(buf: []u8) -> (res: i64) {
    assert(len(buf) == 8)
    res |= i64(buf[0])
    res |= i64(buf[1]) << 8
    res |= i64(buf[2]) << 16
    res |= i64(buf[3]) << 24
    res |= i64(buf[4]) << 32
    res |= i64(buf[5]) << 40
    res |= i64(buf[6]) << 48
    res |= i64(buf[7]) << 56
    return
}

hi_bit :: proc(n: u32) -> u32 {
    n := n
    n |= (n >>  1);
    n |= (n >>  2);
    n |= (n >>  4);
    n |= (n >>  8);
    n |= (n >> 16);
    return n - (n >> 1);
}
