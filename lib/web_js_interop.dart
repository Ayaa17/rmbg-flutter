import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:js/js.dart';

@JS('callJsFunction')
external void callJsFunction(String url);

@JS('setupMessageListener')
external void setupMessageListener(Function(Float32List) callback);

Future<Float32List> processImageForWeb(Uint8List bytes) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final completer = Completer<Float32List>();

  void callback(Float32List result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  setupMessageListener(allowInterop(callback));
  callJsFunction(url);
  return completer.future;
}
