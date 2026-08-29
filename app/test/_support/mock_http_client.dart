import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MockHttpClient extends http.BaseClient {
  final _routes = <String, _Route>{};
  void onPost(String path, dynamic Function(Map<String, dynamic> body) responder, {int status = 200}) {
    _routes['POST $path'] = _Route(responder, status);
  }
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.method} ${request.url.path}';
    final route = _routes[key];
    if (route == null) {
      return http.StreamedResponse(Stream.value([]), 404);
    }
    final body = request is http.Request ? jsonDecode(request.body) as Map<String, dynamic> : <String, dynamic>{};
    final payload = route.responder(body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload is String ? payload : jsonEncode(payload))),
      route.status,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _Route {
  final dynamic Function(Map<String, dynamic>) responder;
  final int status;
  _Route(this.responder, this.status);
}
