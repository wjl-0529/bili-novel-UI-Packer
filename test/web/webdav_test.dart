import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test("default WebDAV fields are empty", () {
    const config = WebDavConfig();
    expect(config.serverUrl, isEmpty);
    expect(config.username, isEmpty);
    expect(config.password, isEmpty);
    expect(config.basePath, isEmpty);
  });

  test("config store keeps, redacts, and clears password", () async {
    final dir = await Directory.systemTemp.createTemp("bnp_webdav_config_");
    addTearDown(() => dir.delete(recursive: true));
    final store = WebDavConfigStore(dir.path);

    final saved = await store.saveFromPayload({
      "enabled": true,
      "serverUrl": " https://dav.example.com/dav/ ",
      "username": " user ",
      "password": "secret",
      "basePath": "/Books",
    });

    expect(saved.password, "secret");
    expect(saved.toSafeJson().containsKey("password"), isFalse);
    expect(saved.toSafeJson()["hasPassword"], isTrue);

    final retained = await store.saveFromPayload({
      "enabled": true,
      "serverUrl": "https://dav.example.com/next/",
      "username": "user",
      "password": "",
      "basePath": "/Books",
    });

    expect(retained.password, "secret");

    final cleared = await store.saveFromPayload({
      "enabled": true,
      "serverUrl": "https://dav.example.com/next/",
      "username": "user",
      "password": "",
      "clearPassword": true,
      "basePath": "/Books",
    });

    expect(cleared.password, isEmpty);
    expect(cleared.toSafeJson()["hasPassword"], isFalse);
  });

  test(
    "client creates directories and uploads files with basic auth",
    () async {
      final dir = await Directory.systemTemp.createTemp("bnp_webdav_upload_");
      addTearDown(() => dir.delete(recursive: true));
      final file = File(path.join(dir.path, "book.epub"));
      await file.writeAsString("epub");
      final seen = <String>[];
      final client = WebDavClient(
        client: MockClient((request) async {
          expect(
            request.headers["authorization"],
            "Basic ${base64Encode(utf8.encode("user:secret"))}",
          );
          seen.add("${request.method} ${request.url.pathSegments.join("/")}");
          if (request.method == "PUT") {
            expect(request.bodyBytes, utf8.encode("epub"));
            return http.Response("", 204);
          }
          return http.Response("", 201);
        }),
      );

      final result = await client.uploadFiles(
        config: const WebDavConfig(
          enabled: true,
          serverUrl: "https://dav.example.com/dav",
          username: "user",
          password: "secret",
          basePath: "/Books/Light Novels",
        ),
        sourceId: 42,
        title: "A/B",
        jobId: "abcd1234-zzzz",
        files: [file],
      );

      expect(seen, [
        "MKCOL dav/Books",
        "MKCOL dav/Books/Light Novels",
        "MKCOL dav/Books/Light Novels/42-A_B-abcd1234",
        "PUT dav/Books/Light Novels/42-A_B-abcd1234/book.epub",
      ]);
      expect(result.remoteFiles, [
        "/Books/Light Novels/42-A_B-abcd1234/book.epub",
      ]);
    },
  );

  test("client reports upload failure status", () async {
    final dir = await Directory.systemTemp.createTemp("bnp_webdav_failure_");
    addTearDown(() => dir.delete(recursive: true));
    final file = File(path.join(dir.path, "book.epub"));
    await file.writeAsString("epub");
    final client = WebDavClient(
      client: MockClient((request) async {
        if (request.method == "PUT") {
          return http.Response("nope", 507);
        }
        return http.Response("", 201);
      }),
    );

    expect(
      () => client.uploadFiles(
        config: const WebDavConfig(
          enabled: true,
          serverUrl: "https://dav.example.com/dav",
          username: "user",
          password: "secret",
          basePath: "/Books",
        ),
        sourceId: 42,
        title: "Book",
        jobId: "abcd1234",
        files: [file],
      ),
      throwsA(isA<WebDavException>()),
    );
  });

  test(
    "client treats missing remote delete target as already cleaned",
    () async {
      final seen = <String>[];
      final client = WebDavClient(
        client: MockClient((request) async {
          seen.add("${request.method} ${request.url.pathSegments.join("/")}");
          return http.Response("", 404);
        }),
      );

      await client.deleteDisplayPath(
        const WebDavConfig(
          enabled: true,
          serverUrl: "https://dav.example.com/dav",
          username: "user",
          password: "secret",
          basePath: "/Books",
        ),
        "/Books/old/book.epub",
      );

      expect(seen, ["DELETE dav/Books/old/book.epub"]);
    },
  );

  test("download job stores WebDAV password but safe json redacts it", () {
    final job = DownloadJob(
      id: "job-1",
      sourceId: 1,
      url: "https://example.test/novel/1.html",
      request: const JobRequest(
        urlTemplate: "https://example.test/novel/{id}.html",
        rangeText: "1",
        volumeRangeText: "",
        combineVolume: false,
        addChapterTitle: false,
        barkConfig: BarkConfig(),
      ),
      webDavConfig: const WebDavConfig(
        enabled: true,
        serverUrl: "https://dav.example.com/dav",
        username: "user",
        password: "secret",
        basePath: "/Books",
      ),
    );

    expect(job.toJson()["webDavConfig"]["password"], "secret");
    final safeConfig =
        job.toJson(includeSecrets: false)["webDavConfig"]
            as Map<String, dynamic>;
    expect(safeConfig.containsKey("password"), isFalse);
    expect(safeConfig["hasPassword"], isTrue);
  });

  test("download job deserializes legacy upload fields", () {
    final job = DownloadJob.fromJson({
      "id": "job-1",
      "sourceId": 1,
      "url": "https://example.test/novel/1.html",
      "request": {
        "urlTemplate": "https://example.test/novel/{id}.html",
        "rangeText": "1",
        "volumeRangeText": "",
        "combineVolume": false,
        "addChapterTitle": false,
        "barkConfig": <String, dynamic>{},
      },
      "createdAt": DateTime.now().toIso8601String(),
    });

    expect(job.uploadStatus, "disabled");
    expect(job.uploadedFiles, isEmpty);
    expect(job.uploadError, isNull);
  });
}
