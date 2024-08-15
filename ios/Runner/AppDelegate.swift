import UIKit
import Flutter
import TensorFlowLite
import Accelerate

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private let channelName = "com.example.hello_flutter/game_detect"
    private var interpreter: Interpreter?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window.rootViewController as! FlutterViewController
        let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            guard call.method == "game_detect" else {
                result(FlutterMethodNotImplemented)
                return
            }

            if let args = call.arguments as? [String: Any],
               let imageBytes = args["image"] as? FlutterStandardTypedData {
                self?.handleImageProcessing(imageBytes.data, result: result)
            } else {
                result(FlutterError(code: "UNAVAILABLE", message: "Image data not available.", details: nil))
            }
        }

        GeneratedPluginRegistrant.register(with: self)

        do {
            let modelPath = Bundle.main.path(forResource: "model", ofType: "tflite")!
            interpreter = try Interpreter(modelPath: modelPath)
            try interpreter?.allocateTensors()
        } catch {
            print("Failed to create interpreter: \(error.localizedDescription)")
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handleImageProcessing(_ imageData: Data, result: @escaping FlutterResult) {
        let batchSize = 1
        let inputChannels = 3
        let inputWidth = 512
        let inputHeight = 512

        guard let interpreter = interpreter else {
            result(FlutterError(code: "INTERPRETER_ERROR", message: "Interpreter is not initialized.", details: nil))
            return
        }

        guard let image = UIImage(data: imageData) else {
            result(FlutterError(code: "INVALID_IMAGE", message: "Failed to create UIImage from data.", details: nil))
            return
        }

        guard let pixelBuffer = image.pixelBuffer() else {
            result(FlutterError(code: "INVALID_IMAGE", message: "Failed to convert UIImage to CVPixelBuffer.", details: nil))
            return
        }

        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
               sourcePixelFormat == kCVPixelFormatType_32BGRA ||
               sourcePixelFormat == kCVPixelFormatType_32RGBA)

        let imageChannels = 4
        assert(imageChannels >= inputChannels)

        let scaledSize = CGSize(width: inputWidth, height: inputHeight)
        guard let thumbnailPixelBuffer = pixelBuffer.centerThumbnail(ofSize: scaledSize) else {
            result(-1)
            return
        }

        guard let rgbData = rgbDataFromBuffer(thumbnailPixelBuffer, byteCount: batchSize * inputWidth * inputHeight * inputChannels) else {
            result(FlutterError(code: "DATA_CONVERSION_ERROR", message: "Failed to convert image buffer to RGB data.", details: nil))
            return
        }

        do {
            try interpreter.copy(rgbData, toInputAt: 0)
            try interpreter.invoke()
            let outputTensor = try interpreter.output(at: 0)

            result(outputTensor.data)
        } catch {
            result(FlutterError(code: "PREDICTION_ERROR", message: "Failed to perform prediction.", details: error.localizedDescription))
        }
    }

    private func rgbDataFromBuffer(
        _ buffer: CVPixelBuffer,
        byteCount: Int
    ) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let mutableRawPointer = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let count = CVPixelBufferGetDataSize(buffer)
        let bufferData = Data(bytesNoCopy: mutableRawPointer, count: count, deallocator: .none)
        var rgbBytes = [Float](repeating: 0, count: byteCount)
        var index = 0
        let alphaComponent = (baseOffset: 4, moduloRemainder: 3)
        for component in bufferData.enumerated() {
            let offset = component.offset
            let isAlphaComponent = (offset % alphaComponent.baseOffset) == alphaComponent.moduloRemainder
            guard !isAlphaComponent else { continue }
            rgbBytes[index] = Float(component.element) / 255.0
            index += 1
        }
        return rgbBytes.withUnsafeBufferPointer(Data.init)
    }
}

extension UIImage {

  // Computes the pixel buffer from  UIImage
  func pixelBuffer() -> CVPixelBuffer? {

    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary

    // Allocates a new pixel buffer
    var pixelBuffer : CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(self.size.width), Int(self.size.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
    guard (status == kCVReturnSuccess) else {
      return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    // Gets the CGContext with the base address of newly allocated pixelBuffer
    let context = CGContext(data: pixelData, width: Int(self.size.width), height: Int(self.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

    // Translates the origin to bottom left before drawing the UIImage to pixel buffer, since Core Graphics expects origin to be at bottom left as opposed to top left expected by UIKit.
    context?.translateBy(x: 0, y: self.size.height)
    context?.scaleBy(x: 1.0, y: -1.0)

    // Draws the UIImage in the context to extract the CVPixelBuffer
    UIGraphicsPushContext(context!)
    self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
    UIGraphicsPopContext()
    CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

    return pixelBuffer
  }

}

extension CVPixelBuffer {

    /**
     Returns thumbnail by cropping pixel buffer to biggest square and scaling the cropped image to
     model dimensions.
     */
    func centerThumbnail(ofSize size: CGSize ) -> CVPixelBuffer? {

        let imageWidth = CVPixelBufferGetWidth(self)
        let imageHeight = CVPixelBufferGetHeight(self)
        let pixelBufferType = CVPixelBufferGetPixelFormatType(self)

        assert(pixelBufferType == kCVPixelFormatType_32BGRA)

        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
        let imageChannels = 4

        let thumbnailSize = min(imageWidth, imageHeight)
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

        var originX = 0
        var originY = 0

        if imageWidth > imageHeight {
            originX = (imageWidth - imageHeight) / 2
        }
        else {
            originY = (imageHeight - imageWidth) / 2
        }

        // Finds the biggest square in the pixel buffer and advances rows based on it.
        guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self)?.advanced(
            by: originY * inputImageRowBytes + originX * imageChannels) else {
                return nil
        }

        // Gets vImage Buffer from input image
        var inputVImageBuffer = vImage_Buffer(
            data: inputBaseAddress, height: UInt(thumbnailSize), width: UInt(thumbnailSize),
            rowBytes: inputImageRowBytes)

        let thumbnailRowBytes = Int(size.width) * imageChannels
        guard  let thumbnailBytes = malloc(Int(size.height) * thumbnailRowBytes) else {
            return nil
        }

        // Allocates a vImage buffer for thumbnail image.
        var thumbnailVImageBuffer = vImage_Buffer(data: thumbnailBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: thumbnailRowBytes)

        // Performs the scale operation on input image buffer and stores it in thumbnail image buffer.
        let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &thumbnailVImageBuffer, nil, vImage_Flags(0))

        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

        guard scaleError == kvImageNoError else {
            return nil
        }

        let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in

            if let pointer = pointer {
                free(UnsafeMutableRawPointer(mutating: pointer))
            }
        }

        var thumbnailPixelBuffer: CVPixelBuffer?

        // Converts the thumbnail vImage buffer to CVPixelBuffer
        let conversionStatus = CVPixelBufferCreateWithBytes(
            nil, Int(size.width), Int(size.height), pixelBufferType, thumbnailBytes,
            thumbnailRowBytes, releaseCallBack, nil, nil, &thumbnailPixelBuffer)

        guard conversionStatus == kCVReturnSuccess else {
            free(thumbnailBytes)
            return nil
        }

        return thumbnailPixelBuffer
    }
}