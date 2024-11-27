package graphs

import "core:os"
import "core:bufio"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags(window.configFlags)
    rl.InitWindow(window.width, window.height, window.name)
    // rl.SetWindowState(window.configFlags)
    rl.SetTargetFPS(window.fps)

    fileHandle, err := os.open("2024_10_14_14_33_Battery_Level.bin")
    defer os.close(fileHandle)
    if err != os.ERROR_NONE {
        fmt.println("Couldn't open a file")
        return
    }

    fileBytes, succ := os.read_entire_file_from_filename("2024_10_14_14_33_Battery_Level.bin")
    fileSize, _ := os.file_size(fileHandle)

    FileElement :: struct {
        timestep: i64,
        value: i64,
    }
    elements: [dynamic]FileElement
    defer delete(elements)
    reserve(&elements, fileSize / 16)

    if succ && len(fileBytes) == int(fileSize) {
        firstTimestep := bytes_to_int64(fileBytes[:8])

        for i := 0; i < len(fileBytes); i += 16 {
            timestep := bytes_to_int64(fileBytes[i:i+8])

            nanoseconds := i64(timestep - firstTimestep) * 100
            // buf : [MIN_HMSMS_LEN]u8
            // fmt.println(time_to_string_hmsms(nanoseconds, buf[:]))

            val := bytes_to_int64(fileBytes[i+8:i+16])
            append(&elements, FileElement{
                timestep=timestep,
                value=val
            })
        }
    } else {
        fmt.println("something is wrong")
    }

    offsetX: f32
    zoomLevel: f32 = 60
    targetZoomLevel: f32 = zoomLevel
    plotOffset: f32

    pointsCount: f32 = 24000
    pointsData: [dynamic]f32
    reserve(&pointsData, u32(pointsCount))
    for i in 0..<pointsCount {
        append(&pointsData, rand.float32_range(10, 60))
    }

    for !rl.WindowShouldClose() {
        window.width = rl.GetScreenWidth()
        window.height = rl.GetScreenHeight()

        // TODO: find better place for this variable so we can update it and reference everywhere
        xAxisLine.x1 = window.width - graphMargin
        xAxisLine.y  = window.height - graphMargin - 80

        {// Zoom slider, before calc of mouse/zoom offsets to avoid jitter when zooming in some cases
            zoomLevelSliderRect: rl.Rectangle = {
                0, f32(window.height-30),
                f32(window.width-100), 30
            }
            GuiSlider_Custom(zoomLevelSliderRect, "", fmt.caprintf("%f = %fs", zoomLevel, zoomLevel / 60), &targetZoomLevel, 0, pointsCount)
        }

        if rl.IsMouseButtonDown(.LEFT) && !guiControlExclusiveMode {
            mouseDelta := rl.GetMouseDelta();
            offsetX += mouseDelta.x
        }

        offsetX = clamp(offsetX, -((pointsCount/zoomLevel-1)*x_axis_width()), 0)
        plotOffset = remap(0, x_axis_width(), 0, zoomLevel, offsetX)
        plotOffset = clamp(plotOffset, -(pointsCount-zoomLevel), 0)

        @(static) zoomExp: f32 = -0.07
        // rl.GuiSlider({0,50,f32(window.width-100),30}, "", fmt.caprint(zoomExp), &zoomExp, -0.5, -0.001)
        if wheelMove := rl.GetMouseWheelMoveV().y; wheelMove != 0 {
            targetZoomLevel *= math.exp(zoomExp * wheelMove)
            targetZoomLevel = clamp(targetZoomLevel, 1, pointsCount)
        }

        zoomLevel = exp_decay(zoomLevel, targetZoomLevel, 18, rl.GetFrameTime())

        rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)

        render_x_axis(plotOffset, offsetX, zoomLevel)
        
        // Render plot line
        if true {
            for i in i32(-plotOffset)..<i32(zoomLevel-plotOffset) {
                index := clamp(i, 0, i32(pointsCount-2))
                posBegin := rl.Vector2{
                    math.lerp(f32(xAxisLine.x0), f32(xAxisLine.x1), f32(index)/zoomLevel),
                    math.lerp(f32(0), f32(xAxisLine.y), pointsData[index]/60) // TODO: use yAxisLine TODO: change lerpT
                }

                posEnd   := rl.Vector2{
                    math.lerp(f32(xAxisLine.x0), f32(xAxisLine.x1), f32(index+1)/zoomLevel),
                    math.lerp(f32(0), f32(xAxisLine.y), pointsData[index+1]/60) // TODO: use yAxisLine TODO: change lerpT
                }
                posBegin.x += offsetX
                posEnd.x   += offsetX
                rl.DrawLineEx(posBegin, posEnd, 3, rl.BLUE)
            }

        }

        //rl.GuiSlider({0,0, 100,30}, "", "", &x, 0, f32(window.width) / 2)
        //rl.GuiSlider({0,60,100,30}, "", "", &y, 0, f32(window.height) / 2)
        //rl.GuiSlider({0,90,100,30}, "", "", &rot, 0, 360)
        rl.DrawFPS(5, 5)
        rl.EndDrawing()
    }
}
