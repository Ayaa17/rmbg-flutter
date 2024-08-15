import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'web_js_interop.dart' if (dart.library.io) 'stub_js_interop.dart';

import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:image/image.dart' as img;

var logger = Logger();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remove Portrait Background',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const ImagePickerScreen(),
    );
  }
}

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  _ImagePickerScreenState createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  static const platform =
      MethodChannel('com.example.hello_flutter/game_detect');
  Uint8List? _imageBytes;

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null) {
      if (kIsWeb) {
        logger.d(
            'Selected file name: ${result.files.single.name}, Web platform does not support file paths.');

        setState(() {
          _imageBytes = result.files.single.bytes;
        });
      } else {
        final path = result.files.single.path;
        if (path != null) {
          final bytes = await File(path).readAsBytes();
          setState(() {
            _imageBytes = bytes;
          });
        } else {
          logger.d('Selected file path is null');
        }
      }
    } else {
      logger.d('No image selected.');
    }
  }

  Uint8List resizeImage(Uint8List imageData,
      {int targetWidth = 224, int targetHeight = 224}) {
    img.Image? image = img.decodeImage(imageData);

    if (image != null) {
      img.Image resizedImage =
          img.copyResize(image, width: targetWidth, height: targetHeight);

      return Uint8List.fromList(img.encodePng(resizedImage));
    } else {
      return imageData;
    }
  }

  Future<Float32List> resizeAndNormalizeImage(img.Image image,
      {int targetWidth = 512, int targetHeight = 512}) async {
    img.Image resizedImage =
        img.copyResize(image, width: targetWidth, height: targetHeight);

    List<double> buffer = [];

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        int pixel = resizedImage.getPixel(x, y);

        int r = img.getRed(pixel);
        int g = img.getGreen(pixel);
        int b = img.getBlue(pixel);

        buffer.add(r / 255.0);
        buffer.add(g / 255.0);
        buffer.add(b / 255.0);
      }
    }

    return Float32List.fromList(buffer);
  }

  Future<Float32List> readResizeAndNormalizeImage(Uint8List imageData,
      {int targetWidth = 512, int targetHeight = 512}) async {
    img.Image? image = img.decodeImage(imageData);

    if (image != null) {
      img.Image resizedImage =
          img.copyResize(image, width: targetWidth, height: targetHeight);

      List<double> buffer = [];

      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          int pixel = resizedImage.getPixel(x, y);

          int r = img.getRed(pixel);
          int g = img.getGreen(pixel);
          int b = img.getBlue(pixel);

          buffer.add(r / 255.0);
          buffer.add(g / 255.0);
          buffer.add(b / 255.0);
        }
      }

      return Float32List.fromList(buffer);
    } else {
      throw Exception("Unable to decode image");
    }
  }

  Float32List transformDimensions(
      Float32List floatBytes, int n, int w, int h, int c) {
    int newSize = n * c * w * h;
    Float32List transformed = Float32List(newSize);

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < w; j++) {
        for (int k = 0; k < h; k++) {
          for (int l = 0; l < c; l++) {
            int oldIndex = i * (w * h * c) + j * (h * c) + k * c + l;
            int newIndex = i * (c * w * h) + l * (w * h) + j * h + k;
            transformed[newIndex] = floatBytes[oldIndex];
          }
        }
      }
    }

    return transformed;
  }

  Float32List resizeGrayscaleImage(
    Float32List input,
    int originalWidth,
    int originalHeight,
    int newWidth,
    int newHeight,
  ) {
    // 創建輸出的影像數據
    Float32List output = Float32List(newWidth * newHeight);

    // 計算縮放比例
    double xScale = originalWidth / newWidth;
    double yScale = originalHeight / newHeight;

    // 對新影像每個像素進行插值計算
    for (int y = 0; y < newHeight; y++) {
      for (int x = 0; x < newWidth; x++) {
        // 找到對應的原始影像位置
        int srcX = (x * xScale).floor();
        int srcY = (y * yScale).floor();

        // 計算在原始數組中的索引
        int srcIndex = srcY * originalWidth + srcX;

        // 設置輸出的影像數據
        output[y * newWidth + x] = input[srcIndex];
      }
    }

    return output;
  }

  Uint8List float32ListToUint8List1D(Float32List float32List) {
    int length = float32List.length;
    Uint8List uint8List = Uint8List(length);

    for (int i = 0; i < length; i++) {
      // 將 Float32 值乘以 255，並將結果轉換為 Uint8
      uint8List[i] = (float32List[i] * 255).clamp(0, 255).toInt();
    }
    return uint8List;
  }

  img.Image float32ListToImage(Float32List float32List, int width, int height) {
    final img.Image image = img.Image(width, height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int index = (y * width + x) * 4;
        final int r = (float32List[index] * 255).toInt();
        final int g = (float32List[index + 1] * 255).toInt();
        final int b = (float32List[index + 2] * 255).toInt();
        final int a = (float32List[index + 3] * 255).toInt();
        image.setPixel(x, y, img.getColor(r, g, b, a));
      }
    }
    return image;
  }

  Uint8List imageToUint8List(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  Uint8List float32ListToUint8List(
      Float32List float32List, int width, int height) {
    img.Image image = float32ListToImage(float32List, width, height);
    return imageToUint8List(image);
  }

  Float32List combineMatrices(
      Float32List matrixA, Float32List matrixB, int width, int height) {
    final int totalSize = width * height * 4;
    Float32List combinedMatrix = Float32List(totalSize);

    for (int i = 0; i < width * height; i++) {
      int indexA = i * 3;
      int indexB = i;
      int indexCombined = i * 4;

      combinedMatrix[indexCombined] = matrixA[indexA];
      combinedMatrix[indexCombined + 1] = matrixA[indexA + 1];
      combinedMatrix[indexCombined + 2] = matrixA[indexA + 2];
      combinedMatrix[indexCombined + 3] = matrixB[indexB];
    }

    return combinedMatrix;
  }

  img.Image maskImage(img.Image image, Uint8List mask, int width, int height) {
    final img.Image newImage = img.Image(width, height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int pixel = image.getPixel(x, y);

        int r = img.getRed(pixel);
        int g = img.getGreen(pixel);
        int b = img.getBlue(pixel);
        int a = mask[y * width + x];
        newImage.setPixel(x, y, img.getColor(r, g, b, a));
      }
    }
    return newImage;
  }

  void onImageTap() async {
    try {
      Float32List? output;

      final img.Image? image = img.decodeImage(_imageBytes!);
      final originWidth = image!.width;
      final originHeight = image!.height;

      logger.d('Width: $originWidth, Height: $originHeight');

      if (kIsWeb) {
        Uint8List bytes = _imageBytes!.buffer.asUint8List();
        output = await processImageForWeb(bytes);
      } else if (Platform.isAndroid || Platform.isIOS) {
        Uint8List bytes = _imageBytes!.buffer.asUint8List();
        final List<dynamic> byteArray =
            await platform.invokeMethod('game_detect', {'image': bytes});

        Uint8List uuu8 = Uint8List.fromList(byteArray.cast<int>());
        output = Float32List.view(uuu8.buffer);
      } else if (Platform.isWindows || Platform.isMacOS) {
        Float32List floatBytes = await resizeAndNormalizeImage(image,
            targetWidth: 512, targetHeight: 512);

        // floatBytes = transformDimensions(floatBytes, 1, 512, 512, 3);
        output =
            await platform.invokeMethod('game_detect', {'image': floatBytes});
      }

      Float32List filter = Float32List.fromList(output!);
      for (int y = 0; y < 512; y++) {
        for (int x = 0; x < 512; x++) {
          final int index = y * 512 + x;
          if (output[index] < 0.5) {
            filter[index] = 0.0;
          } else {
            filter[index] = 1.0;
          }
        }
      }

      Float32List resizeFilter =
          resizeGrayscaleImage(filter, 512, 512, originWidth, originHeight);

      Uint8List fliterU8 = float32ListToUint8List1D(resizeFilter);

      img.Image resultImg =
          maskImage(image, fliterU8, originWidth, originHeight);

      setState(() {
        _imageBytes = imageToUint8List(resultImg);
      });
    } on PlatformException catch (e) {
      logger.e("Failed to invoke: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remove Portrait Background'),
      ),
      body: Center(
        child: _imageBytes != null
            ? Image.memory(_imageBytes!)
            : Text('No image selected.'),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _pickImage,
            child: Icon(Icons.add_a_photo),
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              onImageTap();
            },
            child: Icon(Icons.save),
          ),
        ],
      ),
    );
  }
}
