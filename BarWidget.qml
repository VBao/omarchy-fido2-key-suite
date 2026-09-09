import QtQuick
import Quickshell.Io
import qs.Ui

// The lock screen's key glyph, on the bar: lit while an authenticator is
// attached, dim while none is, click to open the management panel.
//
// Presence is the service's answer rather than a second enumeration of the USB
// bus -- but it arrives over the shell's IPC rather than by holding the
// service. Omarchy marks the built-in lock plugin
// `capabilities: ["authentication"]`, and a clone inherits that through
// `omarchy.clonedFrom`; an authentication service is deliberately kept out of
// the registry `shell.serviceFor` reads, so credential-bearing QML is never
// reachable from a bar surface. `serviceFor("erijl.lock")` returns null here
// however healthy the service is, which is why this asks over `lock presence`
// instead. That call is also how the widget registers its interest: it renews
// the presence lease that makes the service watch for the key while the
// session is unlocked, the role Service.watchPresence() used to play.
BarWidget {
  id: root
  moduleName: "erijl.lock"

  property bool keyPresent: false
  property bool configured: false

  // Matched to the service's own presence poll (fido2DetectTimer), which is
  // what actually re-reads the key; asking faster would only re-read the same
  // value. The lease outlives three of these, so an indicator that is still
  // mounted never lets the watch lapse between ticks.
  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!presenceProc.running) presenceProc.running = true
  }

  Process {
    id: presenceProc
    running: false
    // Bounded like every other collected command in this plugin: a wedged
    // shell must not leave the poll hanging for the rest of the session.
    command: ["bash", "-c",
              "timeout -k 2 5 omarchy-shell lock presence 2>/dev/null | head -c 4096"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reading = null
        try {
          reading = JSON.parse(String(text || ""))
        } catch (e) {
          // The shell is not up yet, or answered something that is not JSON.
          // Keep the last good reading rather than blinking the glyph.
          return
        }
        if (!reading) return
        root.configured = reading.fido2 === true
        root.keyPresent = reading.fido2Token === true
      }
    }
  }

  implicitWidth: keyButton.implicitWidth
  implicitHeight: keyButton.implicitHeight

  WidgetButton {
    id: keyButton
    anchors.fill: parent
    bar: root.bar
    // U+EB11, written as an escape: a Private Use Area codepoint survives no
    // round trip through anything that sanitises text, and this one went
    // missing exactly that way once.
    text: "\ueb11"
    dimmed: !root.keyPresent
    tooltipText: !root.configured
      ? "Security key not set up"
      : (root.keyPresent ? "Security key attached" : "No security key attached")
    onPressed: function(pressedButton) {
      if (root.bar) root.bar.run("omarchy-shell shell toggle erijl.lock '{}'")
    }
  }
}
