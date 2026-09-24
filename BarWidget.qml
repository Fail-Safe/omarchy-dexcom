import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DexcomModel.js" as DexcomModel

BarWidget {
  id: root
  moduleName: "failsafe.dexcom"

  property var anchorItem: button

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property int mgdl: service ? service.mgdl : -1
  readonly property string arrow: service ? service.arrow : ""
  readonly property string trend: service ? service.trend : "None"
  readonly property int ageSec: service ? service.ageSec : -1
  readonly property string ageText: service ? service.ageText : "unknown"
  readonly property bool checking: service ? service.checking : false
  readonly property bool paused: service ? service.paused : false
  readonly property string lastError: service ? service.lastError : "Service unavailable"
  readonly property color healthColor: service ? service.healthColor : "#6b7280"
  readonly property string badgeText: service ? service.badgeText : "--"
  readonly property int chartHours: service ? service.chartHours : 4
  readonly property var chartPoints: service ? service.chartPoints : []
  readonly property var chartStats: service ? service.chartStats : ({ count: 0, min: -1, max: -1, avg: -1 })
  readonly property int lowMgdl: service ? service.lowMgdl : 70
  readonly property int highMgdl: service ? service.highMgdl : 180
  readonly property int historyCount: service && service.history ? service.history.length : 0
  property int hoverIndex: -1
  property real hoverMouseX: -1
  readonly property bool opened: panel.opened

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function syncServiceSettings() { if (service) service.settings = settings || ({}) }
  onServiceChanged: syncServiceSettings()
  onSettingsChanged: syncServiceSettings()

  function refresh() { if (service) service.refresh() }
  function togglePause() { if (service) service.togglePause() }
  function setChartHours(hours) { if (service) service.setChartHours(hours) }
  function open() { panel.controller.show(); refresh() }
  function close() { panel.controller.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  readonly property bool popoutSwitchClosing: false

  function paintChart(canvas) {
    var ctx = canvas.getContext("2d")
    if (!ctx) return
    var w = canvas.width
    var h = canvas.height
    if (w < 10 || h < 10) return
    ctx.reset()
    ctx.clearRect(0, 0, w, h)

    var points = root.chartPoints || []
    var padL = 34
    var padR = 10
    var padT = 10
    var padB = root.chartHours >= 4 ? 28 : 22
    var plotW = Math.max(1, w - padL - padR)
    var plotH = Math.max(1, h - padT - padB)
    var bounds = DexcomModel.chartBounds(points, root.lowMgdl, root.highMgdl)
    var yMin = bounds.min
    var yMax = bounds.max
    var nowSec = Math.floor(Date.now() / 1000)
    var xMin = nowSec - root.chartHours * 3600
    var xMax = nowSec
    var dim = "#9ca3af"
    var line = String(root.healthColor)

    function xPos(epoch) {
      return padL + ((epoch - xMin) / Math.max(1, xMax - xMin)) * plotW
    }
    function yPos(mg) {
      return padT + (1 - ((mg - yMin) / Math.max(1, yMax - yMin))) * plotH
    }

    ctx.fillStyle = "rgba(255,255,255,0.05)"
    ctx.fillRect(padL, padT, plotW, plotH)

    var bandTop = Math.min(yMax, root.highMgdl)
    var bandBottom = Math.max(yMin, root.lowMgdl)
    if (bandTop > bandBottom) {
      ctx.fillStyle = "rgba(34,197,94,0.12)"
      ctx.fillRect(padL, yPos(bandTop), plotW, Math.max(1, yPos(bandBottom) - yPos(bandTop)))
    }

    ctx.strokeStyle = "rgba(255,255,255,0.12)"
    ctx.fillStyle = dim
    ctx.font = "11px sans-serif"
    ctx.lineWidth = 1
    var ticks = [yMin, Math.round((yMin + yMax) / 2), yMax]
    for (var t = 0; t < ticks.length; t++) {
      var y = yPos(ticks[t])
      ctx.beginPath()
      ctx.moveTo(padL, y)
      ctx.lineTo(padL + plotW, y)
      ctx.stroke()
      ctx.textAlign = "right"
      ctx.textBaseline = "middle"
      ctx.fillText(String(ticks[t]), padL - 6, y)
    }

    var guides = [root.lowMgdl, root.highMgdl]
    ctx.strokeStyle = "rgba(245,158,11,0.55)"
    for (var g = 0; g < guides.length; g++) {
      var level = guides[g]
      if (level < yMin || level > yMax) continue
      var gy = yPos(level)
      ctx.beginPath()
      ctx.moveTo(padL, gy)
      ctx.lineTo(padL + plotW, gy)
      ctx.stroke()
    }

    if (!points.length) {
      ctx.fillStyle = dim
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText(root.historyCount > 0 ? "No points in this range" : "No history yet", padL + plotW / 2, padT + plotH / 2)
      return
    }

    ctx.strokeStyle = line
    ctx.lineWidth = 2
    ctx.beginPath()
    for (var i = 0; i < points.length; i++) {
      var px = xPos(points[i].epochSec)
      var py = yPos(points[i].mgdl)
      if (i === 0) ctx.moveTo(px, py)
      else ctx.lineTo(px, py)
    }
    ctx.stroke()

    var last = points[points.length - 1]
    ctx.fillStyle = line
    ctx.beginPath()
    ctx.arc(xPos(last.epochSec), yPos(last.mgdl), 3.5, 0, Math.PI * 2)
    ctx.fill()

    // Hover snap-to crosshair
    if (root.hoverIndex >= 0 && root.hoverIndex < points.length) {
      var hp = points[root.hoverIndex]
      var hx = xPos(hp.epochSec)
      var hy = yPos(hp.mgdl)

      ctx.strokeStyle = "rgba(255,255,255,0.45)"
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(hx, padT)
      ctx.lineTo(hx, padT + plotH)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(padL, hy)
      ctx.lineTo(padL + plotW, hy)
      ctx.stroke()

      ctx.fillStyle = "#ffffff"
      ctx.beginPath()
      ctx.arc(hx, hy, 4.5, 0, Math.PI * 2)
      ctx.fill()
      ctx.fillStyle = line
      ctx.beginPath()
      ctx.arc(hx, hy, 3, 0, Math.PI * 2)
      ctx.fill()

      var label = hp.mgdl + " mg/dL"
      var sub = DexcomModel.formatClock(hp.epochSec)
      if (hp.ageSec >= 0) sub = sub + (sub !== "" ? " · " : "") + DexcomModel.formatAge(hp.ageSec)
      ctx.font = "bold 12px sans-serif"
      var labelW = Math.max(ctx.measureText(label).width, ctx.measureText(sub).width) + 16
      var labelH = 36
      var boxX = hx + 10
      if (boxX + labelW > padL + plotW) boxX = hx - 10 - labelW
      if (boxX < padL) boxX = padL
      var boxY = hy - labelH - 8
      if (boxY < padT) boxY = hy + 8

      ctx.fillStyle = "rgba(17,24,39,0.92)"
      ctx.beginPath()
      // rounded-ish rect without roundRect for older canvas
      ctx.rect(boxX, boxY, labelW, labelH)
      ctx.fill()
      ctx.fillStyle = "#ffffff"
      ctx.textAlign = "left"
      ctx.textBaseline = "top"
      ctx.fillText(label, boxX + 8, boxY + 6)
      ctx.font = "11px sans-serif"
      ctx.fillStyle = "#d1d5db"
      ctx.fillText(sub, boxX + 8, boxY + 20)
    }

    // X-axis ticks: dense marks, sparse clock labels on long ranges
    ctx.fillStyle = dim
    ctx.textAlign = "center"
    ctx.textBaseline = "top"
    ctx.font = "10px sans-serif"
    if (root.chartHours >= 4) {
      // Tick density vs label density:
      //  4h  → 30m ticks, label every hour
      // 12h  → 1h ticks,  label every 3 hours
      // 24h  → 1h ticks,  label every 4 hours
      var stepSec = root.chartHours >= 12 ? 3600 : 1800
      var labelEverySec = root.chartHours >= 24 ? 4 * 3600 : (root.chartHours >= 12 ? 3 * 3600 : 3600)
      var edgePad = 28
      var firstTick = Math.ceil(xMin / stepSec) * stepSec
      for (var tx = firstTick; tx < xMax; tx += stepSec) {
        var xx = xPos(tx)
        if (xx < padL + 2 || xx > padL + plotW - 2) continue
        var major = (tx % 3600 === 0)
        var labeled = (tx % labelEverySec === 0)
        ctx.strokeStyle = labeled ? "rgba(255,255,255,0.22)" : (major ? "rgba(255,255,255,0.14)" : "rgba(255,255,255,0.07)")
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(xx, padT)
        ctx.lineTo(xx, padT + plotH)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(xx, padT + plotH)
        ctx.lineTo(xx, padT + plotH + (labeled ? 5 : (major ? 4 : 2)))
        ctx.stroke()
        if (labeled && xx > padL + edgePad && xx < padL + plotW - edgePad) {
          ctx.fillStyle = dim
          ctx.fillText(DexcomModel.formatClock(tx), xx, padT + plotH + 6)
        }
      }
      ctx.fillStyle = dim
      ctx.textAlign = "right"
      ctx.fillText("now", padL + plotW, padT + plotH + 6)
    } else {
      ctx.fillText(root.chartHours + "h ago", padL + 18, padT + plotH + 4)
      ctx.fillText("now", padL + plotW - 12, padT + plotH + 4)
    }
  }
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: Style.space(52)
    active: false
    useActiveColor: false
    tooltipText: root.mgdl < 0
      ? ("Dexcom: offline" + (root.lastError !== "" ? " — " + root.lastError : ""))
      : ("Dexcom: " + root.mgdl + " mg/dL " + root.arrow + " · " + root.ageText + (root.paused ? " (paused)" : ""))

    Rectangle {
      anchors.centerIn: parent
      width: Math.max(Style.space(36), badgeLabel.implicitWidth + Style.space(12))
      height: Style.space(21)
      radius: height / 2
      color: root.healthColor
      opacity: root.paused ? 0.55 : 1

      Behavior on color { ColorAnimation { duration: 160 } }
      Behavior on opacity { NumberAnimation { duration: 120 } }

      Text {
        id: badgeLabel
        anchors.centerIn: parent
        text: root.badgeText
        textFormat: Text.PlainText
        color: root.service ? root.service.badgeTextColor : "#ffffff"
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.refresh()
      else if (code === Qt.RightButton) root.togglePause()
      else root.toggle()
    }
  }

  Panel {
    id: panel
    moduleName: root.moduleName
    manageIpc: false

    readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

    function switchPanel(direction) {
      if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root, direction)
      return false
    }

    KeyboardPanel {
      anchorItem: root.anchorItem
      owner: root
      bar: root.bar
      open: panel.opened
      focusTarget: keyCatcher
      contentWidth: fittedContentWidth(Style.space(420))
      contentHeight: fittedContentHeight(content.implicitHeight, Style.space(640))

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onCloseRequested: root.close()
        onTabRequested: direction => panel.switchPanel(direction)
        onTextKey: function(text) {
          if (text === "r" || text === "R") root.refresh()
          if (text === "p" || text === "P") root.togglePause()
          if (text === "1") root.setChartHours(1)
          if (text === "4") root.setChartHours(4)
          if (text === "2") root.setChartHours(12)
          if (text === "8") root.setChartHours(24)
        }

        Flickable {
          anchors.fill: parent
          contentWidth: width
          contentHeight: content.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          // Don't steal chart hover when content fits the panel.
          interactive: contentHeight > height + 1

          ColumnLayout {
            id: content
            width: parent.width
            spacing: Style.space(12)

            PanelHero {
              Layout.fillWidth: true
              title: root.mgdl < 0 ? "Offline" : root.mgdl + " mg/dL " + root.arrow
              meta: root.mgdl < 0 ? "Dexcom Share" : (root.trend + " · " + root.ageText)
              foreground: root.healthColor
              fontFamily: panel.fontFamily
              iconComponent: Component {
                Text {
                  // nf-md-water
                  text: "󰖌"
                  textFormat: Text.PlainText
                  color: root.healthColor
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            Text {
              Layout.fillWidth: true
              text: root.paused ? "Monitoring paused" : root.checking ? "Fetching…" : root.lastError
              textFormat: Text.PlainText
              visible: text !== ""
              color: root.lastError !== "" && !root.paused && !root.checking ? "#ef4444" : panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              Layout.fillWidth: true
              text: "HISTORY"
              textFormat: Text.PlainText
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)
              Repeater {
                model: [1, 4, 12, 24]
                delegate: Button {
                  required property int modelData
                  Layout.fillWidth: true
                  text: (root.chartHours === modelData ? "● " : "○ ") + modelData + "h"
                  onClicked: root.setChartHours(modelData)
                }
              }
            }

            Rectangle {
              id: chartFrame
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(180)
              implicitHeight: Style.space(180)
              radius: Style.cornerRadius
              color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, 0.04)
              clip: true

              function updateHover(mx) {
                root.hoverMouseX = mx
                var padL = 34
                var padR = 10
                var plotW = Math.max(1, chartCanvas.width - padL - padR)
                var idx = DexcomModel.nearestPointIndex(
                  root.chartPoints, mx, padL, plotW, root.chartHours, Math.floor(Date.now() / 1000)
                )
                if (root.hoverIndex !== idx) {
                  root.hoverIndex = idx
                  chartCanvas.requestPaint()
                } else {
                  chartCanvas.requestPaint()
                }
              }

              function clearHover() {
                if (root.hoverIndex === -1 && root.hoverMouseX < 0) return
                root.hoverIndex = -1
                root.hoverMouseX = -1
                chartCanvas.requestPaint()
              }

              Canvas {
                id: chartCanvas
                anchors.fill: parent
                anchors.margins: Style.space(4)
                antialiasing: true
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                onPaint: root.paintChart(chartCanvas)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) Qt.callLater(requestPaint)
                Component.onCompleted: Qt.callLater(requestPaint)
              }

              // Sibling overlay — Canvas children often never receive hover.
              // preventStealing keeps Flickable from eating mouse moves.
              MouseArea {
                id: chartHover
                anchors.fill: chartCanvas
                z: 10
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.NoButton
                cursorShape: containsMouse && root.chartPoints && root.chartPoints.length ? Qt.CrossCursor : Qt.ArrowCursor
                onPositionChanged: chartFrame.updateHover(mouseX)
                onEntered: chartFrame.updateHover(mouseX)
                onExited: chartFrame.clearHover()
              }

              Connections {
                target: root
                function onChartPointsChanged() { chartCanvas.requestPaint() }
                function onChartHoursChanged() { chartFrame.clearHover(); chartCanvas.requestPaint() }
                function onHealthColorChanged() { chartCanvas.requestPaint() }
                function onLowMgdlChanged() { chartCanvas.requestPaint() }
                function onHighMgdlChanged() { chartCanvas.requestPaint() }
                function onHistoryCountChanged() { chartCanvas.requestPaint() }
                function onHoverIndexChanged() { chartCanvas.requestPaint() }
                function onOpenedChanged() {
                  if (root.opened) Qt.callLater(chartCanvas.requestPaint)
                  else chartFrame.clearHover()
                }
              }
            }

            Text {
              Layout.fillWidth: true
              text: root.chartStats.count > 0
                ? (root.chartStats.count + " readings · min " + root.chartStats.min + " · avg " + root.chartStats.avg + " · max " + root.chartStats.max)
                : (root.historyCount > 0 ? ("Loaded " + root.historyCount + " points · pick a range") : "Waiting for history…")
              textFormat: Text.PlainText
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
              Layout.fillWidth: true
              Button { Layout.fillWidth: true; text: root.checking ? "Fetching…" : "Refresh  (R)"; enabled: !root.checking && !root.paused; onClicked: root.refresh() }
              Button { Layout.fillWidth: true; text: root.paused ? "Resume  (P)" : "Pause  (P)"; onClicked: root.togglePause() }
            }

            Text {
              Layout.fillWidth: true
              text: "Unofficial community project — not affiliated with Dexcom. Not a medical device. For informational monitoring only — do not use for treatment decisions. Always follow your clinician’s guidance and your CGM/pump’s own alerts."
              textFormat: Text.PlainText
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              opacity: 0.85
            }

            Text {
              Layout.fillWidth: true
              text: "Left: details · Middle: refresh · Right: pause"
              textFormat: Text.PlainText
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }
}
