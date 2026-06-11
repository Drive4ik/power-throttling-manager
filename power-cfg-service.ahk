#Include stdout-to-var.ahk

class PowerCfgService {
    __New() {
        this.powerCfgPath := "powercfg.exe"
        this.quoteChar := Chr(34)
    }

    ListDisabledEntries() {
        listResult := this.RunPowerCfg("/powerthrottling list")
        this.ThrowIfFailed("Failed to retrieve the power throttling list.", listResult)
        return this.ParseListOutput(listResult.output)
    }

    DisableEntry(entry) {
        disableResult := this.RunPowerCfg("/powerthrottling disable " . this.BuildTargetArgument(entry))
        this.ThrowIfFailed("Failed to add the application to the list.", disableResult)
        return true
    }

    ResetEntry(entry) {
        resetResult := this.RunPowerCfg("/powerthrottling reset " . this.BuildTargetArgument(entry))
        this.ThrowIfFailed("Failed to remove the application from the list.", resetResult)
        return true
    }

    ParseListOutput(output) {
        entries := []
        seen := Map()

        for rawLine in StrSplit(this.NormalizeNewlines(output), "`n", "`r") {
            if !RegExMatch(rawLine, "i)^\s*Application:\s*(.+?)\s*$", &match) {
                continue
            }

            value := this.CleanPath(match[1])
            if value = "" {
                continue
            }

            entry := this.IsExecutableValue(value)
                ? this.CreatePathEntry(value)
                : this.CreatePfnEntry(value)
            this.PushUniqueEntry(entries, seen, entry)
        }

        return entries
    }

    PushUniqueEntry(entries, seen, entry) {
        normalizedKey := this.NormalizeEntryKey(entry)
        if normalizedKey = "" || seen.Has(normalizedKey) {
            return false
        }

        seen[normalizedKey] := true
        entries.Push(entry)
        return true
    }

    IsExecutableValue(value) {
        return RegExMatch(value, "i)\.exe$")
    }

    BuildTargetArgument(entry) {
        entry := this.CoerceToEntry(entry)
        if !IsObject(entry) {
            throw Error("Could not determine the entry type for powercfg.")
        }

        if entry.kind = "pfn" {
            return "/pfn " . this.WrapInQuotes(entry.value)
        }

        return "/path " . this.WrapInQuotes(entry.value)
    }

    RunPowerCfg(arguments) {
        fullCommandLine := A_ComSpec
            . " /D /Q /C chcp 65001 >nul & "
            . this.powerCfgPath
            . " "
            . arguments
            . " 2>&1"

        commandCaptureResult := StdoutToVar(fullCommandLine, , "UTF-8")
        return {
            commandLine: fullCommandLine,
            output: this.NormalizeNewlines(commandCaptureResult.Output),
            exitCode: commandCaptureResult.ExitCode
        }
    }

    ThrowIfFailed(prefix, result) {
        if result.exitCode = 0 {
            return
        }

        details := Trim(result.output)
        if details = "" {
            details := "powercfg exited with code " . result.exitCode . "."
        }

        throw Error(prefix . "`n`n" . details)
    }

    CleanPath(path) {
        value := Trim(path)
        value := Trim(value, '"')
        return value
    }

    CleanPfn(pfn) {
        return Trim(pfn)
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
            displayName: Trim(displayName)
        }
    }

    CoerceToEntry(entry) {
        if !IsObject(entry) {
            return this.CreatePathEntry(entry)
        }

        kind := entry.HasOwnProp("kind") ? entry.kind : "path"
        if kind = "pfn" {
            value := entry.HasOwnProp("value") ? entry.value : (entry.HasOwnProp("pfn") ? entry.pfn : "")
            displayName := entry.HasOwnProp("displayName") ? entry.displayName : ""
            return this.CreatePfnEntry(value, displayName)
        }

        value := entry.HasOwnProp("value") ? entry.value : (entry.HasOwnProp("fullPath") ? entry.fullPath : "")
        displayName := entry.HasOwnProp("displayName") ? entry.displayName : ""
        return this.CreatePathEntry(value, displayName)
    }

    NormalizeEntryKey(entry) {
        entry := this.CoerceToEntry(entry)
        if !IsObject(entry) {
            return ""
        }

        return entry.kind . ":" . StrLower(entry.value)
    }

    WrapInQuotes(value) {
        return this.quoteChar . value . this.quoteChar
    }

    NormalizeNewlines(text) {
        text := StrReplace(text, "`r`n", "`n")
        return StrReplace(text, "`r", "`n")
    }

}
