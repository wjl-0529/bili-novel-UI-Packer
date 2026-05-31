import 'dart:convert';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test("does not send when disabled", () async {
    var called = false;
    final client = BarkClient(
      client: MockClient((request) async {
        called = true;
        return http.Response("{}", 200);
      }),
    );

    final sent = await client.notify(
      config: const BarkConfig(enabled: false, deviceKey: "abc"),
      event: "success",
      title: "Done",
      body: "OK",
    );

    expect(sent, isFalse);
    expect(called, isFalse);
  });

  test("sends JSON payload for enabled event", () async {
    Uri? seenUri;
    Map<String, dynamic>? seenBody;
    final client = BarkClient(
      client: MockClient((request) async {
        seenUri = request.url;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response("{}", 200);
      }),
    );

    final sent = await client.notify(
      config: const BarkConfig(
        enabled: true,
        serverUrl: "https://api.day.app",
        deviceKey: "device-key",
        events: BarkEvents(success: true),
      ),
      event: "success",
      title: "下载完成",
      body: "任务完成",
    );

    expect(sent, isTrue);
    expect(seenUri.toString(), "https://api.day.app/device-key");
    expect(seenBody?["title"], "下载完成");
    expect(seenBody?["body"], "任务完成");
    expect(seenBody?["group"], "轻小说打包器");
  });
}
