import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "devfrp.dev-ports"
  ipcTarget: "devfrp.dev-ports"
  manageIpc: true

  property var servers: []
  property string tailscaleIp: ""

  readonly property string scriptDir: Qt.resolvedUrl(".").toString().replace("file://", "") + "/bin"
  readonly property int refreshIntervalSec: Number(root.setting("refreshIntervalSec", 5))
  readonly property int maxPort: Number(root.setting("maxPort", 32767))
  readonly property bool hideWhenEmpty: !!root.setting("hideWhenEmpty", true)
  readonly property string ignore: String(root.setting("ignore", "Discord,kdeconnectd,wayvnc,steam,spotify,cupsd"))
  readonly property bool hidden: root.hideWhenEmpty && root.servers.length === 0 && !root.opened

  // Nerd Font glyphs as codepoints so editors can't mangle the private-use area.
  readonly property string serverGlyph: String.fromCodePoint(0xF048B)
  readonly property string openGlyph: String.fromCodePoint(0xF059F)
  readonly property string copyGlyph: String.fromCodePoint(0xF018F)
  readonly property string networkGlyph: String.fromCodePoint(0xF0317)
  readonly property string stopGlyph: String.fromCodePoint(0xF04DB)

  function refresh() {
    if (listProc.running) return
    listProc.command = [root.scriptDir + "/dev-ports", root.ignore, String(root.maxPort)]
    listProc.running = true
  }

  function urlFor(server, host) {
    return "http://" + (host || "localhost") + ":" + server.port
  }

  function projectName(server) {
    if (!server.cwd) return ""
    var parts = server.cwd.split("/")
    return parts[parts.length - 1] || server.cwd
  }

  function copy(text) {
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function openUrl(server) {
    Quickshell.execDetached(["omarchy-launch-browser", root.urlFor(server)])
    root.close()
  }

  function stop(server) {
    Quickshell.execDetached(["kill", String(server.pid)])
    stopRefresh.restart()
  }

  Component.onCompleted: {
    root.refresh()
    tailscaleProc.running = true
  }

  onOpenedChanged: if (opened) refresh()
  onIgnoreChanged: refresh()
  onMaxPortChanged: refresh()

  Timer {
    interval: Math.max(2, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: stopRefresh
    interval: 700
    onTriggered: root.refresh()
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.servers = JSON.parse(String(text || "[]")) }
        catch (e) { /* keep previous list */ }
      }
    }
  }

  Process {
    id: tailscaleProc
    command: ["bash", "-c", "tailscale ip -4 2>/dev/null | head -n1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tailscaleIp = String(text || "").trim()
    }
  }

  visible: !root.hidden
  implicitWidth: root.hidden ? 0 : button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.servers.length > 0 ? root.serverGlyph + " " + root.servers.length : root.serverGlyph
    dimmed: root.servers.length === 0
    tooltipText: root.servers.length === 0
      ? "No dev server running"
      : root.servers.map(function(s) { return ":" + s.port + "  " + s.name }).join("\n")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton && root.servers.length > 0) root.openUrl(root.servers[0])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: panelColumn
        width: scrollArea.availableWidth
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Dev Ports"
          meta: root.servers.length === 0
            ? "No dev server running"
            : root.servers.length + (root.servers.length > 1 ? " servers listening" : " server listening")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconOpacity: root.servers.length > 0 ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              text: root.serverGlyph
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground; visible: root.servers.length > 0 }

        Repeater {
          model: root.servers

          RowLayout {
            id: row
            required property var modelData
            width: panelColumn.width
            spacing: Style.spacing.sm

            Text {
              text: ":" + row.modelData.port
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              Layout.preferredWidth: Style.space(72)
              Layout.alignment: Qt.AlignVCenter
            }

            Column {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: row.modelData.name + (root.projectName(row.modelData) ? "  ·  " + root.projectName(row.modelData) : "")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: (row.modelData.scope === "local" ? "local only" : "exposed on " + (row.modelData.scope === "all" ? "all interfaces" : row.modelData.addr))
                  + "  ·  pid " + row.modelData.pid
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              iconText: root.openGlyph
              tooltipText: "Open in browser"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.openUrl(row.modelData)
            }

            PanelActionButton {
              iconText: root.copyGlyph
              tooltipText: "Copy " + root.urlFor(row.modelData)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.copy(root.urlFor(row.modelData))
            }

            PanelActionButton {
              visible: row.modelData.scope === "all" && root.tailscaleIp !== ""
              iconText: root.networkGlyph
              tooltipText: "Copy Tailscale URL " + root.urlFor(row.modelData, root.tailscaleIp)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.copy(root.urlFor(row.modelData, root.tailscaleIp))
            }

            PanelActionButton {
              iconText: root.stopGlyph
              tooltipText: "Stop (kill " + row.modelData.pid + ")"
              foreground: root.bar.foreground
              hoverColor: root.bar.urgent
              fontFamily: root.bar.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.stop(row.modelData)
            }
          }
        }

        Item { width: parent.width; height: Style.space(4) }
      }
    }
  }
}
