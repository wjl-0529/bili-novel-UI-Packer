import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer_ios/api_client.dart';
import 'package:bili_novel_packer_ios/native_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'authenticated JSON requests set cookies before writing the body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? receivedCookie;
      Map<String, dynamic>? receivedBody;
      final subscription = server.listen((request) async {
        if (request.uri.path == '/api/login') {
          await utf8.decoder.bind(request).join();
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'bnp_session=test-session; Path=/; HttpOnly',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true}));
          await request.response.close();
          return;
        }
        if (request.uri.path == '/api/jobs' && request.method == 'POST') {
          receivedCookie = request.headers.value(HttpHeaders.cookieHeader);
          receivedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          request.response.statusCode = HttpStatus.created;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'jobs': <Object>[]}));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final client = ApiClient(
        Uri.parse('http://${server.address.address}:${server.port}'),
      );

      try {
        await client.login('password');
        await client.createJobs(
          const JobRequestModel(
            urlTemplate: 'https://example.com/{id}',
            rangeText: '1',
          ),
        );

        expect(receivedCookie, contains('bnp_session=test-session'));
        expect(receivedBody?['rangeText'], '1');
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
