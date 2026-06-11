; Loads a shell-item icon (e.g. "shell:AppsFolder\<AUMID>")
; as a 32-bpp HBITMAP at exactly the requested size. Returns 0 on failure.
LoadShellItemIconBitmap(parsingName, width, height) {
    static SIIGBF_RESIZETOFIT := 0x0

    iid := Buffer(16)
    if DllCall("ole32\CLSIDFromString", "WStr", "{BCC18B79-BA16-442F-80C4-8A59C30C463B}", "Ptr", iid) != 0 {
        return 0
    }

    factoryPtr := 0
    hr := DllCall("shell32\SHCreateItemFromParsingName", "WStr", parsingName, "Ptr", 0, "Ptr", iid, "Ptr*", &factoryPtr)
    if hr != 0 || !factoryPtr {
        return 0
    }

    hBitmap := 0
    try {
        ; IShellItemImageFactory::GetImage(SIZE, flags, HBITMAP*)
        ComCall(3, factoryPtr, "Int64", width | (height << 32), "UInt", SIIGBF_RESIZETOFIT, "Ptr*", &hBitmap)
    } catch {
        hBitmap := 0
    }
    ObjRelease(factoryPtr)

    if !hBitmap {
        return 0
    }

    return FitIconBitmap(hBitmap, width, height)
}


; Scales a bitmap to exactly the target size (centered, aspect-ratio preserved).
; The source bitmap is freed if a new one is created.
FitIconBitmap(hBitmap, targetWidth, targetHeight) {
    info := Buffer(32, 0)
    if !DllCall("gdi32\GetObject", "Ptr", hBitmap, "Int", info.Size, "Ptr", info) {
        DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
        return 0
    }

    sourceWidth := NumGet(info, 4, "Int")
    sourceHeight := Abs(NumGet(info, 8, "Int"))
    if sourceWidth = targetWidth && sourceHeight = targetHeight {
        return hBitmap
    }

    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", targetWidth, bi, 4)
    NumPut("Int", -targetHeight, bi, 8)
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)

    screenDC := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    sourceDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    targetDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    bits := 0
    resultBitmap := DllCall("gdi32\CreateDIBSection", "Ptr", screenDC, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDC)

    if resultBitmap {
        oldSource := DllCall("gdi32\SelectObject", "Ptr", sourceDC, "Ptr", hBitmap, "Ptr")
        oldTarget := DllCall("gdi32\SelectObject", "Ptr", targetDC, "Ptr", resultBitmap, "Ptr")

        scale := Min(targetWidth / sourceWidth, targetHeight / sourceHeight)
        drawWidth := Max(1, Round(sourceWidth * scale))
        drawHeight := Max(1, Round(sourceHeight * scale))
        drawX := (targetWidth - drawWidth) // 2
        drawY := (targetHeight - drawHeight) // 2

        ; BLENDFUNCTION: AC_SRC_OVER, SourceConstantAlpha=255, AC_SRC_ALPHA
        DllCall("msimg32\AlphaBlend",
            "Ptr", targetDC, "Int", drawX, "Int", drawY, "Int", drawWidth, "Int", drawHeight,
            "Ptr", sourceDC, "Int", 0, "Int", 0, "Int", sourceWidth, "Int", sourceHeight,
            "UInt", 0x01FF0000)

        DllCall("gdi32\SelectObject", "Ptr", sourceDC, "Ptr", oldSource, "Ptr")
        DllCall("gdi32\SelectObject", "Ptr", targetDC, "Ptr", oldTarget, "Ptr")
    }

    DllCall("gdi32\DeleteDC", "Ptr", sourceDC)
    DllCall("gdi32\DeleteDC", "Ptr", targetDC)
    DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
    return resultBitmap
}
