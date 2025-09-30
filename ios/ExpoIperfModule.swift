import ExpoModulesCore

public class ExpoIperfModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ExpoIperf')` in JavaScript.
    Name("ExpoIperf")
      
      Function("getTheme") { () -> String in
          UserDefaults.standard.string(forKey: "theme") ?? "system"
      }
      
      Function("setTheme") { (theme: String) -> Void in
          UserDefaults.standard.set(theme, forKey: "theme")
      }
      
      Function("start") { (options: [String: Any]) in
          print("Starting Server")
           let port = options["port"] as? Int ?? 5201
           let json = options["json"] as? Bool ?? true
           let udp  = (options["protocol"] as? String) == "udp"
          
          

          IperfRunner.shared().start(onPort: Int32(port), json: json, udp: udp) { line in
              print(line)
             self.sendEvent("log", ["line": line])
           }
           self.sendEvent("state", ["value": "started"])
         }
      
      Function("stop") {
          IperfRunner.shared().stop()
          self.sendEvent("state", ["value": "stopped"])
      }
      
      Function("isRunning") {
            return IperfRunner.shared().isRunning
      }


    // Defines constant property on the module.
    Constant("PI") {
      Double.pi
    }

    // Defines event names that the module can send to JavaScript.
    Events("onChange")

    // Defines a JavaScript synchronous function that runs the native code on the JavaScript thread.
    Function("hello") {
      return "Hello world! 👋"
    }

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("setValueAsync") { (value: String) in
      // Send an event to JavaScript.
      self.sendEvent("onChange", [
        "value": value
      ])
    }

  }
}
