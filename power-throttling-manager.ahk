#Requires AutoHotkey v2.0 64-bit
#Warn All
#SingleInstance Force

AppName := "Power Throttling Manager"
;@Ahk2Exe-Let U_AppName = %A_PriorLine~U)^.*"(.+?)".*$~$1%

AppVersion := "1.0"
;@Ahk2Exe-Let U_AppVersion = %A_PriorLine~U)^.*"(.+?)".*$~$1%

AppCopyright := "Drive4ik``, Claude Fable 5``, GPT-5.5"
;@Ahk2Exe-Let U_AppCopyright = %A_PriorLine~U)^.*"(.+?)".*$~$1%
AppCopyright := StrReplace(AppCopyright, "``")

;@Ahk2Exe-SetName           %U_AppName%
;@Ahk2Exe-SetDescription    %U_AppName% v%U_AppVersion%
;@Ahk2Exe-SetVersion        %U_AppVersion%
;@Ahk2Exe-SetProductVersion %U_AppVersion%.0.0
;@Ahk2Exe-SetCopyright      %U_AppCopyright%
;@Ahk2Exe-SetOrigFilename   %U_AppName%.exe
;@Ahk2Exe-SetMainIcon       icon.ico

#Include power-cfg-service.ahk
#Include app-state.ahk
#Include exe-info.ahk
#Include app-icon.ahk

EnsureAdminOrRestart()

PowerThrottlingApp().Run()

class PowerThrottlingApp {
    __New() {
        this.state := AppState()
        this.service := PowerCfgService()
        this.iconCache := Map()
        this.exeNameCache := Map()
        this.storeAppsCache := false
        this.storeAppNameIndex := Map()
        this.storeAppAumidIndex := Map()

        this.startWidth := 740
        this.startHeight := 420
        this.margin := 12
        this.gap := 8
        this.buttonWidth := 80
        this.buttonHeight := 24
        this.throttlingRegKey := "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"

        this.CreateGui()
    }

    Run() {
        this.gui.Show(Format("w{} h{} Center", this.startWidth, this.startHeight))
        this.gui.Opt("+Disabled")
        this.listView.Add("", "Loading...", "")
        this.RefreshFromSystem()
        this.gui.Opt("-Disabled")
    }

    RebuildListView(entriesToSelect := []) {
        try {
            this.listView.Opt("-Redraw")
            this.listView.Delete()

            for item in this.state.items {
                iconIndex := this.ResolveIconIndex(item)
                rowOptions := iconIndex > 0 ? "Icon" . iconIndex : ""
                this.listView.Add(rowOptions, this.GetItemName(item), this.GetItemValueText(item))
            }

            this.AdjustColumns()
            this.ApplySelection(entriesToSelect)
            this.UpdateCommandButtons()
        } finally {
            this.listView.Opt("+Redraw")
        }
    }

    UpdateCommandButtons() {
        hasSelection := this.GetSelectedRows().Length > 0
        hasItems := this.state.items.Length > 0

        this.removeButton.Enabled := hasSelection
        this.exportButton.Enabled := hasItems
    }

    GetSelectedRows() {
        return this.CollectSelectedRows(this.listView)
    }

    CollectSelectedRows(listView) {
        rows := []
        rowNumber := listView.GetNext(0)
        while rowNumber > 0 {
            rows.Push(rowNumber)
            rowNumber := listView.GetNext(rowNumber)
        }

        return rows
    }

    RefreshFromSystem(entriesToSelect := [], showErrors := true) {
        try {
            entries := this.service.ListDisabledEntries()
            this.state.LoadFromEntries(entries)
            this.ApplyStoreDisplayNames()
            this.RebuildListView(entriesToSelect)

            return true
        } catch Error as caughtError {
            this.state.Clear()
            this.RebuildListView()
            if showErrors {
                this.ShowError("Failed to read the system power throttling list.", caughtError.Message)
            }
            return false
        }
    }

    OnSize(guiObj, minMax, width, height) {
        if minMax = -1 {
            return
        }

        this.Layout(width, height)
    }

    Layout(width, height) {
        bottomY := height - this.margin - this.buttonHeight
        listHeight := bottomY - this.gap - this.margin
        listWidth := width - (this.margin * 2)

        this.listView.Move(this.margin, this.margin, listWidth, listHeight)

        buttons := [
            {control: this.addButton, width: this.buttonWidth},
            {control: this.removeButton, width: this.buttonWidth},
            {control: this.exportButton, width: this.buttonWidth},
            {control: this.importButton, width: this.buttonWidth}
        ]
        currentX := this.margin
        for button in buttons {
            button.control.Move(currentX, bottomY, button.width, this.buttonHeight)
            currentX += button.width + this.gap
        }

        this.throttlingCheckbox.Move(currentX + this.gap, bottomY, 180, this.buttonHeight)

        exitX := width - this.margin - this.buttonWidth
        this.exitButton.Move(exitX, bottomY, this.buttonWidth, this.buttonHeight)
        aboutX := exitX - this.gap - this.buttonWidth
        this.aboutButton.Move(aboutX, bottomY, this.buttonWidth, this.buttonHeight)
        this.AdjustColumns()
    }

    OnAdd(*) {
        this.gui.Opt("+OwnDialogs")
        selectedFile := FileSelect(3, , "Select EXE or shortcut", "Applications (*.exe;*.lnk)")
        if selectedFile = "" {
            return
        }

        this.ProcessCandidateEntries([selectedFile], "Add", false)
    }

    OnAddFromStore(*) {
        try {
            this.gui.Opt("+Disabled")
            availableApps := this.GetAvailableStoreApps()
            if availableApps.Length = 0 {
                this.ShowInfo("All available Store apps are already in the powercfg list.")
                return
            }

            selectedApps := this.ShowStorePicker(availableApps)
            if selectedApps && selectedApps.Length > 0 {
                this.ProcessCandidateEntries(selectedApps, "Add from Store", false)
            }
        } catch Error as caughtError {
            this.ShowError("Failed to open the Store apps list.", caughtError.Message)
        } finally {
            this.gui.Opt("-Disabled")
        }
    }

    OnRemove(*) {
        selectedRows := this.GetSelectedRows()
        if selectedRows.Length = 0 {
            return
        }

        if selectedRows.Length > 1 {
            this.gui.Opt("+OwnDialogs")
            choice := MsgBox("Delete " . selectedRows.Length . " entries?", this.gui.Title, "YesNo")
            if choice != "Yes" {
                return
            }
        }

        try {
            this.gui.Opt("+Disabled")

            failures := []
            for rowNumber in selectedRows {
                item := this.state.GetItemByRow(rowNumber)
                if !item {
                    continue
                }

                try {
                    this.service.ResetEntry(item)
                } catch Error as caughtError {
                    failures.Push(this.GetEntryLabel(item) . " -> " . this.FirstLine(caughtError.Message))
                }
            }

            if failures.Length > 0 {
                this.RefreshFromSystem(, false)
                this.ShowError("Some selected entries could not be removed.", this.JoinLines(failures))
                return
            }

            this.RefreshFromSystem(, true)
        } finally {
            this.gui.Opt("-Disabled")
        }
    }

    OnExport(*) {
        if this.state.items.Length = 0 {
            return
        }

        this.gui.Opt("+OwnDialogs")
        selectedFile := FileSelect("S16", A_ScriptDir . "\power-throttling-list.txt", "Export list", "Text (*.txt)")
        if selectedFile = "" {
            return
        }

        if !RegExMatch(selectedFile, "i)\.txt$") {
            selectedFile .= ".txt"
        }

        try {
            this.state.ExportToTxt(selectedFile)
        } catch Error as caughtError {
            this.ShowError("Failed to export the list.", caughtError.Message)
        }
    }

    OnImport(*) {
        this.gui.Opt("+OwnDialogs")
        selectedFile := FileSelect(3, , "Import list", "Text (*.txt)")
        if selectedFile = "" {
            return
        }

        try {
            entries := this.state.ReadEntriesFromTxt(selectedFile)
        } catch Error as caughtError {
            this.ShowError("Failed to read the TXT file.", caughtError.Message)
            return
        }

        if entries.Length = 0 {
            this.ShowError("The import file contains no valid entries.", selectedFile)
            return
        }

        this.ProcessCandidateEntries(entries, "Import")
    }

    OnDropFiles(guiObj, ctrl, fileArray, *) {
        if fileArray.Length > 0 {
            this.ProcessCandidateEntries(fileArray, "Drag and drop", false)
        }
    }

    OnListSelectionChanged(*) {
        this.UpdateCommandButtons()
    }

    OnListDoubleClick(listView, rowNumber, *) {
        if rowNumber <= 0 {
            return
        }

        item := this.state.GetItemByRow(rowNumber)
        if !item || item.kind != "path" {
            return
        }

        Run('explorer.exe /select,"' . item.fullPath . '"')
    }

    LoadGlobalThrottlingState() {
        regValue := 0
        try {
            regValue := RegRead(this.throttlingRegKey, "PowerThrottlingOff", 0)
        }
        this.throttlingCheckbox.Value := regValue != 1
    }

    OnToggleGlobalThrottling(*) {
        newValue := this.throttlingCheckbox.Value ? 0 : 1
        try {
            RegWrite(newValue, "REG_DWORD", this.throttlingRegKey, "PowerThrottlingOff")
        } catch Error as caughtError {
            this.LoadGlobalThrottlingState()
            this.ShowError("Failed to write PowerThrottlingOff to registry.", caughtError.Message)
        }
    }

    OnAbout(*) {
        global AppName, AppVersion, AppCopyright

        MsgBox(
            AppName . " v" . AppVersion
            . "`nCreated: 2026-06-11"
            . "`nCreators: " . AppCopyright
            . "`nHomepage: https://github.com/Drive4ik/power-throttling-manager"
            . "`n`nManage per-app power throttling exemptions via powercfg."
            . "`n`nMade in Ukraine 🇺🇦 with love!",
            "About",
            "Iconi"
        )
    }

    OnExit(*) {
        ExitApp()
    }

    ProcessCandidateEntries(candidates, actionName, alwaysShowSummary := true) {
        summary := this.CreateSummary(actionName)
        seenInBatch := Map()
        addedEntries := []

        for candidate in candidates {
            entry := this.NormalizeCandidateEntry(candidate, summary)
            if !entry {
                continue
            }

            normalizedKey := this.state.NormalizeEntryKey(entry)
            if seenInBatch.Has(normalizedKey) || this.state.HasEntry(entry) {
                summary.duplicates.Push(this.GetEntryLabel(entry))
                continue
            }

            seenInBatch[normalizedKey] := true

            try {
                this.service.DisableEntry(entry)
                this.state.AddEntry(entry)
                summary.added += 1
                addedEntries.Push(entry)
            } catch Error as caughtError {
                summary.failed.Push(this.GetEntryLabel(entry) . " -> " . this.FirstLine(caughtError.Message))
            }
        }

        if summary.added > 0 {
            this.RefreshFromSystem(addedEntries, true)
        }

        if alwaysShowSummary {
            this.ShowInfo(this.BuildSummaryMessage(summary))
        }

        return summary
    }

    CreateSummary(actionName) {
        return {
            actionName: actionName,
            added: 0,
            duplicates: [],
            skipped: [],
            failed: []
        }
    }

    NormalizeCandidateEntry(candidate, summary) {
        if IsObject(candidate) {
            if candidate.HasOwnProp("PFN") {
                return this.NormalizePfnCandidate(candidate, summary)
            }

            kind := candidate.HasOwnProp("kind") ? StrLower(candidate.kind) : ""
            if kind = "pfn" {
                return this.NormalizePfnCandidate(candidate, summary)
            }

            displayName := candidate.HasOwnProp("displayName") ? candidate.displayName : ""
            rawPath := candidate.HasOwnProp("value") ? candidate.value : (candidate.HasOwnProp("fullPath") ? candidate.fullPath : "")
            return this.NormalizeValueCandidate(rawPath, summary, displayName, kind)
        }

        return this.NormalizeValueCandidate(candidate, summary)
    }

    NormalizePfnCandidate(candidate, summary) {
        if candidate.HasOwnProp("PFN") {
            pfn := candidate.PFN
            displayName := candidate.HasOwnProp("DisplayName") ? candidate.DisplayName : ""
        } else {
            pfn := candidate.HasOwnProp("value") ? candidate.value : (candidate.HasOwnProp("pfn") ? candidate.pfn : "")
            displayName := candidate.HasOwnProp("displayName") ? candidate.displayName : ""
        }

        entry := this.state.CreatePfnEntry(pfn, displayName)
        if entry {
            return entry
        }

        summary.skipped.Push(this.GetEntryLabel(candidate))
        return false
    }

    NormalizeValueCandidate(rawValue, summary, displayName := "", hintedKind := "") {
        cleanedValue := this.state.CleanPath(rawValue)
        if cleanedValue = "" {
            summary.skipped.Push("<empty string>")
            return false
        }

        if this.IsShortcutPath(cleanedValue) {
            resolvedPath := this.ResolveShortcutTarget(cleanedValue)
            if resolvedPath = "" {
                summary.skipped.Push(cleanedValue)
                return false
            }

            return this.state.CreatePathEntry(resolvedPath, displayName)
        }

        if hintedKind = "pfn" {
            return this.state.CreatePfnEntry(cleanedValue, displayName)
        }

        if hintedKind = "path" || this.IsExecutablePath(cleanedValue) {
            return this.state.CreatePathEntry(cleanedValue, displayName)
        }

        return this.state.CreatePfnEntry(cleanedValue, displayName)
    }

    BuildSummaryMessage(summary) {
        lines := []
        lines.Push(summary.actionName . ":")
        lines.Push("Added: " . summary.added)

        if summary.duplicates.Length > 0 {
            lines.Push("Duplicates: " . summary.duplicates.Length)
        }
        if summary.skipped.Length > 0 {
            lines.Push("Skipped: " . summary.skipped.Length)
        }
        if summary.failed.Length > 0 {
            lines.Push("powercfg errors: " . summary.failed.Length)
        }

        detailLines := []
        this.AppendExamples(detailLines, "Duplicates", summary.duplicates)
        this.AppendExamples(detailLines, "Skipped lines and broken shortcuts", summary.skipped)
        this.AppendExamples(detailLines, "powercfg errors", summary.failed)

        if detailLines.Length > 0 {
            return this.JoinLines(lines) . "`n`n" . this.JoinLines(detailLines)
        }

        return this.JoinLines(lines)
    }

    AppendExamples(lines, label, items, maxExamples := 3) {
        if items.Length = 0 {
            return
        }

        lines.Push(label . ":")
        exampleCount := Min(items.Length, maxExamples)
        Loop exampleCount {
            lines.Push(" - " . items[A_Index])
        }
        if items.Length > exampleCount {
            lines.Push(" - ...")
        }
    }

    ResolveIconIndex(item) {
        if this.imageListId = 0 {
            return 0
        }

        if item.iconIndex > 0 {
            return item.iconIndex
        }

        cacheKey := item.kind . ":" . (item.kind = "path" ? item.normalizedPath : StrLower(item.pfn))
        if this.iconCache.Has(cacheKey) {
            item.iconIndex := this.iconCache[cacheKey]
            return item.iconIndex
        }

        iconIndex := item.kind = "path"
            ? IL_Add(this.imageListId, item.fullPath, 1)
            : this.AddStoreAppIcon(item.pfn)
        if iconIndex = 0 {
            iconIndex := this.fallbackIconIndex
        }

        this.iconCache[cacheKey] := iconIndex
        item.iconIndex := iconIndex
        return iconIndex
    }

    AddStoreAppIcon(pfn) {
        normalizedPfn := StrLower(this.state.CleanPfn(pfn))
        if normalizedPfn = "" || !this.storeAppAumidIndex.Has(normalizedPfn) {
            return 0
        }

        iconWidth := 16, iconHeight := 16
        DllCall("comctl32\ImageList_GetIconSize", "Ptr", this.imageListId, "Int*", &iconWidth, "Int*", &iconHeight)

        hBitmap := LoadShellItemIconBitmap("shell:AppsFolder\" . this.storeAppAumidIndex[normalizedPfn], iconWidth, iconHeight)
        if !hBitmap {
            return 0
        }

        iconIndex := DllCall("comctl32\ImageList_Add", "Ptr", this.imageListId, "Ptr", hBitmap, "Ptr", 0, "Int") + 1
        DllCall("gdi32\DeleteObject", "Ptr", hBitmap)
        return iconIndex
    }

    GetItemName(item) {
        if item.kind = "pfn" {
            return item.displayName != "" ? item.displayName : item.pfn
        }

        if item.displayName = "" {
            item.displayName := this.ResolveExeDisplayName(item.fullPath)
        }

        return item.displayName
    }

    GetItemValueText(item) {
        return item.kind = "pfn" ? item.pfn : item.fullPath
    }

    GetEntryLabel(entry) {
        if !IsObject(entry) {
            return this.state.CleanPath(entry)
        }

        if entry.HasOwnProp("PFN") {
            displayName := entry.HasOwnProp("DisplayName") ? entry.DisplayName : ""
            return this.BuildStoreLabel(displayName, entry.PFN)
        }

        kind := entry.HasOwnProp("kind") ? StrLower(entry.kind) : "path"
        if kind = "pfn" {
            pfn := entry.HasOwnProp("value") ? entry.value : (entry.HasOwnProp("pfn") ? entry.pfn : "")
            displayName := entry.HasOwnProp("displayName") ? entry.displayName : ""
            return this.BuildStoreLabel(displayName, pfn)
        }

        if entry.HasOwnProp("fullPath") {
            return entry.fullPath
        }

        return entry.HasOwnProp("value") ? this.state.CleanPath(entry.value) : ""
    }

    BuildStoreLabel(displayName, pfn) {
        cleanedPfn := this.state.CleanPfn(pfn)
        cleanedName := Trim(displayName)
        if cleanedName != "" && cleanedName != cleanedPfn {
            return cleanedName . " | " . cleanedPfn
        }

        return cleanedPfn
    }

    ApplyStoreDisplayNames() {
        hasStoreEntries := false
        for item in this.state.items {
            if item.kind = "pfn" {
                hasStoreEntries := true
                break
            }
        }

        if !hasStoreEntries {
            return
        }

        try {
            this.GetStoreApps()
        } catch {
            return
        }

        for item in this.state.items {
            if item.kind != "pfn" {
                continue
            }

            normalizedPfn := StrLower(item.pfn)
            if this.storeAppNameIndex.Has(normalizedPfn) {
                item.displayName := this.storeAppNameIndex[normalizedPfn]
            }
        }
    }

    ResolveExeDisplayName(exePath) {
        normalizedPath := StrLower(this.state.CleanPath(exePath))
        if normalizedPath = "" {
            return ""
        }

        if this.exeNameCache.Has(normalizedPath) {
            return this.exeNameCache[normalizedPath]
        }

        exeInfo := GetExeInfo(exePath)
        displayName := exeInfo.HasOwnProp("Name") ? Trim(exeInfo.Name) : ""
        if displayName = "" {
            SplitPath(exePath, , , , &fileNameNoExt)
            displayName := fileNameNoExt
        }

        this.exeNameCache[normalizedPath] := displayName
        return displayName
    }

    AdjustColumns() {
        this.listView.GetPos(,, &listWidth)
        if listWidth <= 0 {
            return
        }

        nameWidth := 250
        valueWidth := Max(340, listWidth - nameWidth - 24)
        this.listView.ModifyCol(1, nameWidth)
        this.listView.ModifyCol(2, valueWidth)
    }

    ApplySelection(entries) {
        if !IsObject(entries) || entries.Length = 0 {
            return
        }

        rows := []
        for entry in entries {
            rowNumber := this.FindRowNumberByEntry(entry)
            if rowNumber > 0 {
                rows.Push(rowNumber)
            }
        }

        if rows.Length = 0 {
            return
        }

        this.listView.Modify(0, "-Select")
        firstRow := rows[1]
        for index, rowNumber in rows {
            options := index = 1 ? "Select Focus Vis" : "Select"
            this.listView.Modify(rowNumber, options)
        }
        this.listView.Modify(firstRow, "Vis")
        ControlFocus(this.listView, "ahk_id " . this.gui.Hwnd)
    }

    FindRowNumberByEntry(entry) {
        normalizedKey := this.state.NormalizeEntryKey(entry)
        if normalizedKey = "" {
            return 0
        }

        for index, item in this.state.items {
            if item.normalizedKey = normalizedKey {
                return index
            }
        }

        return 0
    }

    IsExecutablePath(path) {
        return RegExMatch(path, "i)\.exe$")
    }

    IsShortcutPath(path) {
        return RegExMatch(path, "i)\.lnk$")
    }

    ResolveShortcutTarget(shortcutPath) {
        try {
            FileGetShortcut(shortcutPath, &targetPath)
            return this.state.CleanPath(targetPath)
        } catch {
            return ""
        }
    }

    FirstLine(text) {
        normalizedText := StrReplace(text, "`r`n", "`n")
        normalizedText := StrReplace(normalizedText, "`r", "`n")
        lines := StrSplit(normalizedText, "`n", "`r`t ")
        return lines.Length > 0 ? lines[1] : ""
    }

    JoinLines(lines, separator := "`n") {
        if lines.Length = 0 {
            return ""
        }

        text := lines[1]
        Loop lines.Length - 1 {
            text .= separator . lines[A_Index + 1]
        }

        return text
    }

    ShowInfo(message) {
        this.gui.Opt("+OwnDialogs")
        MsgBox(message, this.gui.Title, "Iconi")
    }

    ShowError(message, details := "") {
        fullMessage := message
        if details != "" {
            fullMessage .= "`n`n" . details
        }

        this.gui.Opt("+OwnDialogs")
        MsgBox(fullMessage, this.gui.Title, "Iconx")
    }

    GetStoreApps(forceReload := false) {
        if !forceReload && IsObject(this.storeAppsCache) {
            return this.storeAppsCache
        }

        apps := this.GetUWPApps()
        this.storeAppsCache := apps
        this.storeAppNameIndex := Map()
        this.storeAppAumidIndex := Map()

        for storeApp in apps {
            normalizedPfn := StrLower(this.state.CleanPfn(storeApp.PFN))
            if normalizedPfn = "" {
                continue
            }

            if !this.storeAppNameIndex.Has(normalizedPfn) {
                this.storeAppNameIndex[normalizedPfn] := storeApp.DisplayName
                this.storeAppAumidIndex[normalizedPfn] := storeApp.Aumid
            }
        }

        return apps
    }

    GetAvailableStoreApps(forceReload := false) {
        availableApps := []
        for storeApp in this.GetStoreApps(forceReload) {
            if !this.state.HasPfn(storeApp.PFN) {
                availableApps.Push(storeApp)
            }
        }

        return availableApps
    }

    ShowStorePicker(apps) {
        popupWidth := this.startWidth - (this.margin * 2)
        popupHeight := this.startHeight - (this.margin * 2)
        popupButtonWidth := this.buttonWidth
        bottomY := popupHeight - this.margin - this.buttonHeight
        listWidth := popupWidth - (this.margin * 2)
        listHeight := bottomY - this.gap - this.margin
        cancelX := popupWidth - this.margin - popupButtonWidth
        chooseX := cancelX - this.gap - popupButtonWidth

        popup := Gui("+Owner" . this.gui.Hwnd . " +ToolWindow -MinimizeBox -MaximizeBox", "Add from Store")
        listView := popup.Add("ListView", Format("x{} y{} w{} h{} Grid +Multi NoSort", this.margin, this.margin, listWidth, listHeight), ["Application", "PFN"])
        chooseButton := popup.Add("Button", Format("x{} y{} w{} h{}", chooseX, bottomY, popupButtonWidth, this.buttonHeight), "Select")
        cancelButton := popup.Add("Button", Format("x{} y{} w{} h{}", cancelX, bottomY, popupButtonWidth, this.buttonHeight), "Cancel")
        chooseButton.Enabled := false

        for storeApp in apps {
            listView.Add("", storeApp.DisplayName, storeApp.PFN)
        }

        listView.ModifyCol(1, "AutoHdr")
        nameWidth := SendMessage(0x101D, 0, 0, listView)
        nameWidth := Max(240, Min(nameWidth, listWidth - 220))
        listView.ModifyCol(1, nameWidth)
        listView.ModifyCol(2, Max(180, listWidth - nameWidth - 24))

        selection := {confirmed: false, apps: []}
        closeHandler := ObjBindMethod(this, "CloseStorePicker", popup)

        listView.OnEvent("ItemSelect", ObjBindMethod(this, "UpdateStorePickerChooseButton", listView, chooseButton))
        listView.OnEvent("DoubleClick", ObjBindMethod(this, "ConfirmStorePickerSelection", popup, listView, apps, selection))
        chooseButton.OnEvent("Click", ObjBindMethod(this, "ConfirmStorePickerSelection", popup, listView, apps, selection))
        cancelButton.OnEvent("Click", closeHandler)
        popup.OnEvent("Close", closeHandler)
        popup.OnEvent("Escape", closeHandler)

        popup.Show(Format("w{} h{} Center", popupWidth, popupHeight))
        WinWaitClose("ahk_id " . popup.Hwnd)

        return selection.confirmed ? selection.apps : false
    }

    UpdateStorePickerChooseButton(listView, chooseButton, *) {
        chooseButton.Enabled := this.CollectSelectedRows(listView).Length > 0
    }

    ConfirmStorePickerSelection(popup, listView, apps, selection, *) {
        selectedRows := this.CollectSelectedRows(listView)
        if selectedRows.Length = 0 {
            return
        }

        selectedApps := []
        for rowNumber in selectedRows {
            selectedApps.Push(apps[rowNumber])
        }

        selection.confirmed := true
        selection.apps := selectedApps
        this.gui.Opt("-Disabled")
        popup.Destroy()
    }

    CloseStorePicker(popup, *) {
        this.gui.Opt("-Disabled")
        popup.Destroy()
    }

    CreateGui() {
        global AppName
        this.gui := Gui(Format("+Resize +MinSize{}x{}", this.startWidth, this.startHeight), AppName)

        this.listView := this.gui.Add("ListView", "xm ym Grid +Multi NoSort", ["Name", "Path / PFN"])
        this.imageListId := IL_Create(24)
        if this.imageListId != 0 {
            this.listView.SetImageList(this.imageListId)
            this.fallbackIconIndex := IL_Add(this.imageListId, "shell32.dll", 3)
        } else {
            this.fallbackIconIndex := 0
        }

        this.addButton := this.gui.Add("Button", , "Add")
        this.removeButton := this.gui.Add("Button", , "Remove")
        this.exportButton := this.gui.Add("Button", , "Export")
        this.importButton := this.gui.Add("Button", , "Import")
        this.throttlingCheckbox := this.gui.Add("Checkbox", , "Global Throttling enabled")
        this.aboutButton := this.gui.Add("Button", , "About")
        this.exitButton := this.gui.Add("Button", , "Exit")

        ; BS_SPLITBUTTON cannot be set at creation time — the style must be applied after.
        static BS_SPLITBUTTON := 0x0C
        ControlSetStyle("+" . BS_SPLITBUTTON, this.addButton)
        WinRedraw(this.addButton.Hwnd)

        this.addMenu := Menu()
        this.addMenu.Add("Add from Store...", ObjBindMethod(this, "OnAddFromStore"))

        static BCN_DROPDOWN := -1248
        this.addButton.OnNotify(BCN_DROPDOWN, ObjBindMethod(this, "OnAddDropDown"))

        this.gui.OnEvent("Close", ObjBindMethod(this, "OnExit"))
        this.gui.OnEvent("Escape", ObjBindMethod(this, "OnExit"))
        this.gui.OnEvent("Size", ObjBindMethod(this, "OnSize"))
        this.gui.OnEvent("DropFiles", ObjBindMethod(this, "OnDropFiles"))

        this.addButton.OnEvent("Click", ObjBindMethod(this, "OnAdd"))
        this.removeButton.OnEvent("Click", ObjBindMethod(this, "OnRemove"))
        this.exportButton.OnEvent("Click", ObjBindMethod(this, "OnExport"))
        this.importButton.OnEvent("Click", ObjBindMethod(this, "OnImport"))
        this.throttlingCheckbox.OnEvent("Click", ObjBindMethod(this, "OnToggleGlobalThrottling"))
        this.aboutButton.OnEvent("Click", ObjBindMethod(this, "OnAbout"))
        this.exitButton.OnEvent("Click", ObjBindMethod(this, "OnExit"))
        this.listView.OnEvent("ItemSelect", ObjBindMethod(this, "OnListSelectionChanged"))
        this.listView.OnEvent("DoubleClick", ObjBindMethod(this, "OnListDoubleClick"))
        this.listView.OnNotify(-155, LV_KeyDown)

        LV_KeyDown(lv, lParam) {
            vKey := NumGet(lParam, 3 * A_PtrSize, "UShort")

            if vKey = 0x2E {  ; VK_DELETE
                this.OnRemove()
            }
        }

        this.EnableExplorerDragDrop()
        this.UpdateCommandButtons()
        this.LoadGlobalThrottlingState()
    }

    OnAddDropDown(guiCtrl, lParam) {
        rect := Buffer(16)
        DllCall("GetWindowRect", "Ptr", this.addButton.Hwnd, "Ptr", rect)
        CoordMode("Menu", "Screen")
        this.addMenu.Show(NumGet(rect, 0, "Int"), NumGet(rect, 12, "Int"))
        return 0
    }

    EnableExplorerDragDrop() {
        static MSGFLT_ALLOW := 1
        static WM_COPYGLOBALDATA := 0x0049
        static WM_COPYDATA := 0x004A
        static WM_DROPFILES := 0x0233

        DllCall("shell32\DragAcceptFiles", "Ptr", this.gui.Hwnd, "Int", true)
        for message in [WM_COPYGLOBALDATA, WM_COPYDATA, WM_DROPFILES] {
            try {
                DllCall("user32\ChangeWindowMessageFilterEx", "Ptr", this.gui.Hwnd, "UInt", message, "UInt", MSGFLT_ALLOW, "Ptr", 0)
            } catch {
            }
        }
    }

    GetUWPApps() {
        psCmd := 'powershell -NoProfile -Command "'
            . '[Console]::OutputEncoding = [Text.Encoding]::UTF8;'
            . "Get-StartApps | ? { $_.AppID -match '!' } | % {"
            . " $_.AppID + '|' + $_.Name"
            . '} | Sort -Unique"'

        result := StdoutToVar(psCmd,, "UTF-8")
        if result.ExitCode != 0 {
            details := Trim(result.Output)
            if details = "" {
                details := "powershell exited with code " . result.ExitCode . "."
            }

            throw Error(details)
        }

        apps := []
        seenPfns := Map()
        Loop Parse result.Output, "`n", "`r"
        {
            if !InStr(A_LoopField, "|")
                continue
            parts := StrSplit(A_LoopField, "|",, 2)
            aumid := Trim(parts[1])
            pfn := this.state.CleanPfn(StrSplit(aumid, "!")[1])
            displayName := Trim(parts[2])
            normalizedPfn := StrLower(pfn)
            if pfn = "" || seenPfns.Has(normalizedPfn)
                continue

            seenPfns[normalizedPfn] := true
            if displayName = ""
                displayName := pfn

            apps.Push({PFN: pfn, DisplayName: displayName, Aumid: aumid})
        }
        return apps
    }
}


EnsureAdminOrRestart() {
    global AppName
    if A_IsAdmin || IsLaunchedUnderDebugger() {
        return
    }

    if RegExMatch(GetCommandLineText(), " /restart(?!\S)") {
        MsgBox("Administrator privileges are required to run this program.", AppName, "Icon!")
        ExitApp()
    }

    try {
        if A_IsCompiled {
            Run('*RunAs "' . A_ScriptFullPath . '" /restart', A_ScriptDir)
        } else {
            Run('*RunAs "' . GetAutoHotkeyInterpreterPath() . '" "' . A_ScriptFullPath . '" /restart', A_ScriptDir)
        }
    } catch {
    }

    ExitApp()
}


; The VS Code (ahk2) debugger launches the interpreter with /Debug=host:port —
; elevation is skipped in that mode.
IsLaunchedUnderDebugger() {
    return RegExMatch(GetCommandLineText(), "i)(^|\s)/Debug(=\S+)?(\s|$)") != 0
}


GetCommandLineText() {
    return DllCall("GetCommandLine", "str")
}


GetAutoHotkeyInterpreterPath() {
    try {
        return ProcessGetPath(DllCall("GetCurrentProcessId"))
    } catch {
        return A_AhkPath
    }
}
