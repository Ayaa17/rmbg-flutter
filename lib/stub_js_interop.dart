import 'dart:typed_data';
import 'dart:async';

void callJsFunction(String url) {
  throw UnsupportedError("Cannot call JavaScript function on non-web platform");
}

Future<Float32List> processImageForWeb(Uint8List bytes) {
  throw UnsupportedError("Cannot process on non-web platform");
}

void setupMessageListener(Function(int) callback) {
  throw UnsupportedError("Cannot process on non-web platform");
}