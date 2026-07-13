import BlikCore
import Foundation

enum DashboardView {

    static func render(state: AppState, terminal: Terminal) {
        let termSize = terminal.size

        // Hide output during render to prevent flicker
        terminal.beginSyncUpdate()

        // Title
        var row = 1
        terminal.moveTo(row: row, col: 1)
        terminal.write(ANSIRenderer.color(" .blik v\(Constants.appVersion)", .bold, .cyan))
        row += 2

        let grouped = Dictionary(grouping: state.sensors, by: { $0.group })

        // Layout calculations
        let colCount = Constants.dashboardColumnCount
        let gap = Constants.dashboardColumnGap
        let colWidth = max(Constants.dashboardMinColumnWidth, (termSize.cols - gap * (colCount - 1)) / colCount)
        let nameW = max(6, colWidth - 12)

        let colPositions = [
            1,
            colWidth + gap + 1,
            (colWidth + gap) * 2 + 1,
            (colWidth + gap) * 3 + 1,
        ]

        let cpuSensors = grouped[.cpuCores] ?? []
        let eSensors = grouped[.npuECores] ?? []
        let gpuSensors = grouped[.gpuCores] ?? []
        let maxTempRows = max(cpuSensors.count, max(eSensors.count, gpuSensors.count))

        // Render columns
        let fanColEnd = renderFanColumn(state: state, grouped: grouped, terminal: terminal, colWidth: colWidth, nameWidth: nameW, startRow: row, startCol: colPositions[0], maxTempRows: maxTempRows)

        let sensorColEnd = renderSensorColumns(grouped: grouped, terminal: terminal, colWidth: colWidth, nameWidth: nameW, startRow: row, colPositions: Array(colPositions[1...3]), maxTempRows: maxTempRows)

        row = max(fanColEnd, sensorColEnd) + 1

        // Control bar
        let fullWidth = min((colWidth + gap) * colCount - gap, termSize.cols)
        row = renderControlBar(state: state, terminal: terminal, width: fullWidth, startRow: row, startCol: 1)

        // Clear remaining rows
        clearRemaining(terminal: terminal, fromRow: row, totalRows: termSize.rows)

        // End synchronized update -- flush all at once (no flicker)
        terminal.endSyncUpdate()
    }

    // MARK: - Column Renderers

    /// Renders column 1: fan tile + other sensors tile. Returns the row after the last tile.
    private static func renderFanColumn(state: AppState, grouped: [SensorGroup: [SensorInfo]], terminal: Terminal, colWidth: Int, nameWidth: Int, startRow: Int, startCol: Int, maxTempRows: Int) -> Int {
        let otherSensors = grouped[.other] ?? []

        // --- Fan tile ---
        var fanLines: [String] = []
        for fan in state.fans {
            let mode = fan.isForced
                ? ANSIRenderer.color("MANUAL", .yellow)
                : ANSIRenderer.color("AUTO", .green)
            let speedColor = ANSIRenderer.fanSpeedColor(actual: fan.actualSpeed, max: fan.maximumSpeed)
            let speed = min(max(fan.actualSpeed, 0), Constants.maxDisplayRPM)
            let rpm = ANSIRenderer.color(String(format: "%4d", Int(speed)), speedColor)
            let bar = ANSIRenderer.progressBar(value: fan.actualSpeed, max: fan.maximumSpeed, width: Constants.fanProgressBarWidth, filledColor: speedColor)
            fanLines.append("  Fan \(fan.id) \(rpm) \(bar) \(mode)")
        }
        if state.currentPreset > 0 {
            fanLines.append(ANSIRenderer.color("  Пресет: \(state.currentPreset)%", .cyan))
        }
        if state.isUnlocking {
            fanLines.append(ANSIRenderer.color("  Разблокировка управления...", .yellow))
        }
        if let error = state.lastError {
            let maxLen = colWidth - 4
            let truncated = error.count > maxLen ? String(error.prefix(maxLen - 1)) + "…" : error
            fanLines.append(ANSIRenderer.color(" \u{26A0} \(truncated)", .red))
        }
        let fanEnd = renderTile(title: "\u{041A}\u{0443}\u{043B}\u{0435}\u{0440}\u{044B}", lines: fanLines, width: colWidth, startRow: startRow, startCol: startCol, terminal: terminal)

        // --- Other sensors tile ---
        let rightColTotalRows = maxTempRows + 2  // +2 for top/bottom border
        let fanTileRows = fanEnd - startRow
        let otherTileContentRows = max(Constants.minVisibleOtherSensors, rightColTotalRows - fanTileRows - 2)  // -2 for other's own borders

        var otherLines: [String] = []
        if !otherSensors.isEmpty {
            let totalOther = otherSensors.count
            let maxVisible = min(otherTileContentRows, totalOther)
            let offset = min(state.otherSensorsScrollOffset, max(0, totalOther - maxVisible))
            let visibleSlice = Array(otherSensors.dropFirst(offset).prefix(maxVisible))
            otherLines = visibleSlice.map { tempLine($0, nameWidth: nameWidth) }
            if totalOther > maxVisible {
                otherLines.append(ANSIRenderer.color("[\(offset+1)-\(offset+visibleSlice.count)/\(totalOther)] \u{2191}\u{2193}", .dim))
            }
        }
        while otherLines.count < otherTileContentRows {
            otherLines.append("")
        }
        let otherEnd = renderTile(title: "\u{041E}\u{0441}\u{0442}\u{0430}\u{043B}\u{044C}\u{043D}\u{044B}\u{0435}", lines: otherLines, width: colWidth, startRow: fanEnd, startCol: startCol, terminal: terminal)

        return otherEnd
    }

    /// Renders columns 2-4: CPU, E-Core, GPU sensor tiles. Returns the max row after all tiles.
    private static func renderSensorColumns(grouped: [SensorGroup: [SensorInfo]], terminal: Terminal, colWidth: Int, nameWidth: Int, startRow: Int, colPositions: [Int], maxTempRows: Int) -> Int {
        let cpuSensors = grouped[.cpuCores] ?? []
        let eSensors = grouped[.npuECores] ?? []
        let gpuSensors = grouped[.gpuCores] ?? []

        let cpuLines = padLines(cpuSensors.map { tempLine($0, nameWidth: nameWidth) }, to: maxTempRows)
        let eLines = padLines(eSensors.map { tempLine($0, nameWidth: nameWidth) }, to: maxTempRows)
        let gLines = padLines(gpuSensors.map { tempLine($0, nameWidth: nameWidth) }, to: maxTempRows)

        let cpuEnd = renderTile(title: "CPU", lines: cpuLines, width: colWidth, startRow: startRow, startCol: colPositions[0], terminal: terminal)
        let eEnd = renderTile(title: "E-Core", lines: eLines, width: colWidth, startRow: startRow, startCol: colPositions[1], terminal: terminal)
        let gEnd = renderTile(title: "GPU", lines: gLines, width: colWidth, startRow: startRow, startCol: colPositions[2], terminal: terminal)

        return max(cpuEnd, max(eEnd, gEnd))
    }

    /// Renders the bottom control bar. Returns the row after the tile.
    @discardableResult
    private static func renderControlBar(state: AppState, terminal: Terminal, width: Int, startRow: Int, startCol: Int) -> Int {
        var row = startRow

        // Уведомление об обновлении
        if let version = state.updateAvailable {
            let updateLine = ANSIRenderer.color(
                " \u{26A0} Доступно обновление v\(version). Перейдите в выпадающее окно строки меню.",
                .yellow
            )
            terminal.moveTo(row: row, col: startCol)
            let visualLen = stripANSI(updateLine).count
            let padding = max(0, width - visualLen)
            terminal.write(updateLine + String(repeating: " ", count: padding))
            row += 1
        }

        var ctrlLines: [String] = []
        if state.readOnlyMode {
            ctrlLines.append(ANSIRenderer.color("Q", .bold) + " \u{0412}\u{044B}\u{0445}\u{043E}\u{0434}")
        } else {
            ctrlLines.append(
                ANSIRenderer.color("1", .bold) + " 0%(Авто)  " +
                ANSIRenderer.color("2", .bold) + " 25%  " +
                ANSIRenderer.color("3", .bold) + " 50%  " +
                ANSIRenderer.color("4", .bold) + " 75%  " +
                ANSIRenderer.color("5", .bold) + " 100%  " +
                ANSIRenderer.color("↑↓", .bold) + " Скролл  " +
                ANSIRenderer.color("Q", .bold) + " Выход"
            )
        }
        return renderTile(title: "\u{0423}\u{043F}\u{0440}\u{0430}\u{0432}\u{043B}\u{0435}\u{043D}\u{0438}\u{0435}", lines: ctrlLines, width: width, startRow: row, startCol: startCol, terminal: terminal)
    }

    /// Clears all rows from `fromRow` to `totalRows`.
    private static func clearRemaining(terminal: Terminal, fromRow: Int, totalRows: Int) {
        var row = fromRow
        while row <= totalRows {
            terminal.moveTo(row: row, col: 1)
            terminal.clearToEndOfLine()
            row += 1
        }
    }

    // MARK: - Tile Renderer

    @discardableResult
    static func renderTile(title: String, lines: [String], width: Int, startRow: Int, startCol: Int, terminal: Terminal) -> Int {
        let innerWidth = width - 2
        var row = startRow

        let titleStr = " \(title) "
        let titleVisualLen = stripANSI(titleStr).count
        let borderLen = max(0, innerWidth - titleVisualLen - 1)
        terminal.moveTo(row: row, col: startCol)
        terminal.write("\u{250C}\u{2500}" + ANSIRenderer.color(titleStr, .bold) + String(repeating: "\u{2500}", count: borderLen) + "\u{2510}")
        row += 1

        for line in lines {
            terminal.moveTo(row: row, col: startCol)
            let visualLen = stripANSI(line).count
            let padding = max(1, innerWidth - visualLen - 1)
            terminal.write("\u{2502} " + line + String(repeating: " ", count: padding) + "\u{2502}")
            row += 1
        }

        if lines.isEmpty {
            terminal.moveTo(row: row, col: startCol)
            terminal.write("\u{2502}" + String(repeating: " ", count: innerWidth) + "\u{2502}")
            row += 1
        }

        terminal.moveTo(row: row, col: startCol)
        terminal.write("\u{2514}" + String(repeating: "\u{2500}", count: innerWidth) + "\u{2518}")
        row += 1

        return row
    }

    // MARK: - Helpers

    private static func tempLine(_ sensor: SensorInfo, nameWidth: Int) -> String {
        let color = ANSIRenderer.temperatureColor(sensor.temperature)
        let temp = ANSIRenderer.color(String(format: "%.1f\u{00B0}C", sensor.temperature), color)
        let name = sensor.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        return "\(name) \(temp)"
    }

    private static func padLines(_ lines: [String], to count: Int) -> [String] {
        var result = lines
        while result.count < count {
            result.append("")
        }
        return result
    }

    static func stripANSI(_ str: String) -> String {
        str.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
