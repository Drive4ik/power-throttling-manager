class AppState {
    __New() {
        this.items := []
        this.entryIndex := Map()
    }

    Clear() {
        this.items := []
        this.entryIndex := Map()
    }

    LoadFromEntries(entries) {
        this.Clear()
        for entry in entries {
            this.AddEntry(entry)
        }
    }

    AddPath(path, displayName := "") {
        return this.AddEntry({kind: "path", value: path, displayName: displayName})
    }

    AddPfn(pfn, displayName := "") {
        return this.AddEntry({kind: "pfn", value: pfn, displayName: displayName})
    }

    AddEntry(entry) {
        entry := this.CoerceToEntry(entry)
        if !IsObject(entry) {
            return false
        }

        normalizedKey := this.NormalizeEntryKey(entry)
        if normalizedKey = "" || this.entryIndex.Has(normalizedKey) {
            return false
        }

        item := this.BuildItem(entry, normalizedKey)

        this.entryIndex[normalizedKey] := this.items.Length + 1
        this.items.Push(item)
        return item
    }

    HasPath(path) {
        return this.HasEntry({kind: "path", value: path})
    }

    HasPfn(pfn) {
        return this.HasEntry({kind: "pfn", value: pfn})
    }

    HasEntry(entry) {
        normalizedKey := this.NormalizeEntryKey(entry)
        return normalizedKey != "" && this.entryIndex.Has(normalizedKey)
    }

    GetItemByRow(rowNumber) {
        if rowNumber < 1 || rowNumber > this.items.Length {
            return false
        }

        return this.items[rowNumber]
    }

    ExportToTxt(filePath) {
        if FileExist(filePath) {
            FileDelete(filePath)
        }

        outFile := FileOpen(filePath, "w", "UTF-8")
        for item in this.items {
            outFile.WriteLine(this.FormatEntryForExport(item))
        }
        outFile.Close()
    }

    ReadEntriesFromTxt(filePath) {
        paths := []
        if !FileExist(filePath) {
            return paths
        }

        text := FileRead(filePath, "UTF-8")
        for line in StrSplit(text, "`n", "`r") {
            entry := this.ParseTxtEntry(line)
            if entry {
                paths.Push(entry)
            }
        }

        return paths
    }

    CreatePathEntry(path, displayName := "") {
        return this.CreateEntry("path", path, displayName)
    }

    CreatePfnEntry(pfn, displayName := "") {
        return this.CreateEntry("pfn", pfn, displayName)
    }

    CreateEntry(kind, value, displayName := "") {
        if kind = "pfn" {
            cleanedValue := this.CleanPfn(value)
        } else {
            kind := "path"
            cleanedValue := this.CleanPath(value)
        }

        if cleanedValue = "" {
            return false
        }

        return {
            kind: kind,
            value: cleanedValue,
            displayName: this.CleanDisplayName(displayName)
        }
    }

    CoerceToEntry(entry) {
        if !IsObject(entry) {
            return this.CreatePathEntry(entry)
        }

        kind := entry.HasOwnProp("kind") ? entry.kind : "path"
        value := entry.HasOwnProp("value") ? entry.value : ""
        displayName := entry.HasOwnProp("displayName") ? entry.displayName : ""

        if kind = "pfn" {
            return this.CreatePfnEntry(value, displayName)
        }

        return this.CreatePathEntry(value, displayName)
    }

    BuildItem(entry, normalizedKey) {
        displayName := entry.displayName
        if entry.kind = "pfn" && displayName = "" {
            displayName := entry.value
        }

        item := {
            kind: entry.kind,
            value: entry.value,
            normalizedKey: normalizedKey,
            displayName: displayName,
            iconIndex: 0,
            fullPath: "",
            normalizedPath: "",
            pfn: ""
        }

        if entry.kind = "path" {
            item.fullPath := entry.value
            item.normalizedPath := StrLower(entry.value)
        } else {
            item.pfn := entry.value
        }

        return item
    }

    NormalizeEntryKey(entry) {
        entry := this.CoerceToEntry(entry)
        if !IsObject(entry) {
            return ""
        }

        return entry.kind . ":" . StrLower(entry.value)
    }

    ParseTxtEntry(line) {
        value := this.CleanPath(line)
        if value = "" {
            return false
        }

        if this.IsShortcutPath(value) || this.IsExecutableValue(value) {
            return this.CreatePathEntry(value)
        }

        return this.CreatePfnEntry(value)
    }

    FormatEntryForExport(item) {
        return item.kind = "pfn" ? item.pfn : item.fullPath
    }

    IsExistingFile(path) {
        attributes := FileExist(path)
        return attributes != "" && !InStr(attributes, "D")
    }

    CleanPath(path) {
        value := Trim(path)
        value := Trim(value, '"')
        return value
    }

    CleanPfn(pfn) {
        return Trim(pfn)
    }

    CleanDisplayName(displayName) {
        return Trim(displayName)
    }

    IsExecutableValue(value) {
        return RegExMatch(value, "i)\.exe$")
    }

    IsShortcutPath(value) {
        return RegExMatch(value, "i)\.lnk$")
    }

    NormalizePath(path) {
        value := this.CleanPath(path)
        value := StrLower(value)
        return value
    }
}
