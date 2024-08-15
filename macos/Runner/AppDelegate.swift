import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    private let channel = "com.example.hello_flutter/game_detect"
    private var model: TensorFlowModel?

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow!.contentViewController as! FlutterViewController
        let gameDetectChannel = FlutterMethodChannel(name: channel, binaryMessenger: controller.engine.binaryMessenger)

        let modelPath = Bundle.main.path(forResource: "saved_model", ofType: "pb", inDirectory: "models")!
        model = TensorFlowModel(modelPath: modelPath)

        gameDetectChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "game_detect" {
                guard let args = call.arguments as? [String: Any],
                      let floatData = args["image"] as? [Float] else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
                    return
                }

                floatData.withUnsafeBufferPointer { buffer in
                    let response = self.model?.runInference(UnsafeMutablePointer(mutating: buffer.baseAddress!), length: Int32(buffer.count))
                    result(response)
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
