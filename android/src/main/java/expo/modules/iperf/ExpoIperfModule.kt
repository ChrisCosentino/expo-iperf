//package expo.modules.iperf
//
//import expo.modules.kotlin.modules.Module
//import expo.modules.kotlin.modules.ModuleDefinition
//
//class ExpoIperfModule : Module() {
//  private var isRunning = false
//
//  override fun definition() = ModuleDefinition {
//    Name("ExpoIperf")
//
//    // Defines event names that the module can send to JavaScript.
//    Events("log", "state")
//
//    // Get theme (placeholder for now)
//    Function("getTheme") {
//      "system"
//    }
//
//    // Set theme (placeholder for now)
//    Function("setTheme") { theme: String ->
//      // Implementation for setting theme
//    }
//
//    // Start iperf server
//    Function("start") { options: Map<String, Any?> ->
//      val port = options["port"] as? Int ?: 5201
//      val json = options["json"] as? Boolean ?: true
//      val protocol = options["protocol"] as? String ?: "tcp"
//
//      isRunning = true
//
//      // Send state event
//      sendEvent("state", mapOf("value" to "started"))
//
//      // TODO: Implement actual iperf functionality here
//      // For now, just log the options
//      sendEvent("log", mapOf("line" to "Starting iperf on port $port with protocol $protocol"))
//    }
//
//    // Stop iperf server
//    Function("stop") {
//      isRunning = false
//      sendEvent("state", mapOf("value" to "stopped"))
//      sendEvent("log", mapOf("line" to "Stopping iperf"))
//    }
//
//    // Check if running
//    Function("isRunning") {
//      isRunning
//    }
//  }
//}

package expo.modules.iperf

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoIperfModule : Module() {
  private val iperfRunner = IperfRunner.getInstance()

  override fun definition() = ModuleDefinition {
    Name("ExpoIperf")

    // Defines event names that the module can send to JavaScript.
    Events("log", "state")

    // Get theme (placeholder for now)
    Function("getTheme") {
      "system"
    }

    // Set theme (placeholder for now)
    Function("setTheme") { theme: String ->
      // Implementation for setting theme
    }

    // Start iperf server
    Function("start") { options: Map<String, Any?> ->
      val port = options["port"] as? Int ?: 5201
      val json = options["json"] as? Boolean ?: true
      val protocol = options["protocol"] as? String ?: "tcp"
      val udp = protocol == "udp"

      // Send state event
      sendEvent("state", mapOf("value" to "started"))

      // Start iperf with callback
      iperfRunner.start(port, json, udp, object : IperfRunner.LogCallback {
        override fun onLog(line: String) {
          sendEvent("log", mapOf("line" to line))
        }
      })
    }

    // Stop iperf server
    Function("stop") {
      iperfRunner.stop()
      sendEvent("state", mapOf("value" to "stopped"))
      sendEvent("log", mapOf("line" to "Stopping iperf"))
    }

    // Check if running
    Function("isRunning") {
      iperfRunner.isRunning()
    }
  }
}