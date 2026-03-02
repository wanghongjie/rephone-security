import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../utils/log_utils.dart';
import '../utils/navigation_service.dart';

Future<Map> getTurnCredential(String host, int port) async {
    HttpClient client = HttpClient(context: SecurityContext());
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      LogUtils.w('TURN', 'getTurnCredential: Allow self-signed certificate => $host:$port. ');
      return true;
    };
    var url = 'https://$host:$port/api/turn?service=turn&username=flutter-webrtc';
    var request = await client.getUrl(Uri.parse(url));
    var response = await request.close();
    if (response.statusCode == 401) {
      NavigationService.handleUnauthorized();
    }
    var responseBody = await response.transform(Utf8Decoder()).join();
    LogUtils.d('TURN', 'getTurnCredential:response => $responseBody.');
    Map data = JsonDecoder().convert(responseBody);
    return data;
  }
