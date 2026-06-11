GetExeInfo(exePath) {
    info := {Path: exePath, Name: ""}

    try {
        verSize := DllCall("version\GetFileVersionInfoSize", "str", exePath, "uint*", 0, "uint")
        if !verSize {
            throw OSError()
        }

        verInfo := Buffer(verSize)
        if !DllCall("version\GetFileVersionInfo", "str", exePath, "uint", 0, "uint", verSize, "ptr", verInfo) {
            throw OSError()
        }

        info.ProductName := QueryVersionString(verInfo, "ProductName")
        info.Description := QueryVersionString(verInfo, "FileDescription")
        info.Name := info.ProductName != "" ? info.ProductName : info.Description
    } catch {
    }

    if info.Name = "" {
        SplitPath(exePath, &fileName, , , &fileNameNoExt)
        info.Name := fileNameNoExt != "" ? fileNameNoExt : fileName
    }

    return info
}

QueryVersionString(verInfo, infoName) {
    if DllCall("version\VerQueryValue", "ptr", verInfo, "str", "\StringFileInfo\040904b0\" . infoName, "ptr*", &valuePtr := 0, "uint*", &valueLen := 0) {
        return valueLen > 0 ? StrGet(valuePtr, valueLen) : ""
    }

    return ""
}
