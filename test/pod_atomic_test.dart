import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motorqu_solid/services/pod_atomic.dart';
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart' show AccessForbiddenException;

const _url = 'https://pod.example/alice/motorqu-solid/data/groups/g1.ttl';

/// Server Pod palsu: menyimpan isi + versi, menghormati If-Match.
class _FakePod {
  _FakePod(this.body, {this.sendEtag = true, this.weakEtag = false});

  String body;
  int version = 1;
  bool sendEtag;
  bool weakEtag;
  int? forceGetStatus;
  int? forcePutStatus;

  /// Server rusak: setiap PUT ber-If-Match ditolak 412 walau ETag cocok.
  bool brokenIfMatch = false;

  /// Dipanggil sebelum setiap PUT (simulasi perangkat lain menulis duluan).
  void Function()? beforePut;

  final gets = <http.Request>[];
  final puts = <http.Request>[];

  String get etag => weakEtag ? 'W/"v$version"' : '"v$version"';

  MockClient get client => MockClient((req) async {
    if (req.method == 'GET') {
      gets.add(req);
      if (forceGetStatus != null) return http.Response('', forceGetStatus!);
      return http.Response(
        body,
        200,
        headers: {if (sendEtag) 'etag': etag},
      );
    }
    if (req.method == 'PUT') {
      puts.add(req);
      beforePut?.call();
      if (forcePutStatus != null) return http.Response('', forcePutStatus!);
      final ifMatch = req.headers['If-Match'];
      if (ifMatch != null && (brokenIfMatch || ifMatch != etag)) {
        return http.Response('', 412);
      }
      body = req.body;
      version++;
      return http.Response('', 205);
    }
    return http.Response('', 405);
  });
}

PodAtomicWriter _writer(
  _FakePod pod, {
  int maxAttempts = 5,
  PodFallbackRead? fallbackRead,
  PodFallbackWrite? fallbackWrite,
}) {
  var n = 0;
  return PodAtomicWriter(
    client: pod.client,
    tokens: (url, method) async =>
        (accessToken: 'at', dPopToken: '$method-${n++}'),
    fallbackRead: fallbackRead ?? (_) async => fail('fallbackRead dipanggil'),
    fallbackWrite:
        fallbackWrite ?? (_, _, _) async => fail('fallbackWrite dipanggil'),
    maxAttempts: maxAttempts,
    backoff: (_) => Duration.zero,
  );
}

void main() {
  group('PodAtomicWriter', () {
    test('menulis dengan If-Match memakai ETag dari GET', () async {
      final pod = _FakePod('a');
      final written = await _writer(pod).update(_url, (c) => '${c}b');

      expect(written, isTrue);
      expect(pod.body, 'ab');
      expect(pod.puts.single.headers['If-Match'], '"v1"');
      expect(pod.gets.single.headers['Accept'], 'text/turtle');
      expect(pod.puts.single.headers['Content-Type'], startsWith('text/turtle'));
    });

    test('konflik 412: baca ulang dan terapkan transform pada data terbaru',
        () async {
      final pod = _FakePod('base');
      var raced = false;
      pod.beforePut = () {
        if (raced) return;
        raced = true;
        // Perangkat lain menulis tepat sebelum PUT kita.
        pod.body = 'base+other';
        pod.version++;
      };

      final seen = <String>[];
      await _writer(pod).update(_url, (c) {
        seen.add(c);
        return '$c+mine';
      });

      expect(seen, ['base', 'base+other']);
      expect(pod.body, 'base+other+mine', reason: 'perubahan lain tidak hilang');
      expect(pod.puts, hasLength(2));
    });

    test('tanpa ETag: PUT tanpa If-Match', () async {
      final pod = _FakePod('a', sendEtag: false);
      await _writer(pod).update(_url, (c) => '${c}b');

      expect(pod.body, 'ab');
      expect(pod.puts.single.headers.containsKey('If-Match'), isFalse);
    });

    test('ETag lemah (W/): PUT tanpa If-Match', () async {
      final pod = _FakePod('a', weakEtag: true);
      await _writer(pod).update(_url, (c) => '${c}b');

      expect(pod.body, 'ab');
      expect(pod.puts.single.headers.containsKey('If-Match'), isFalse);
    });

    test('transform null atau isi sama: tidak ada PUT', () async {
      final pod = _FakePod('a');
      expect(await _writer(pod).update(_url, (_) => null), isFalse);
      expect(await _writer(pod).update(_url, (c) => c), isFalse);
      expect(pod.puts, isEmpty);
    });

    test('404 dikenali PodUtils.isNotFound', () async {
      final pod = _FakePod('a')..forceGetStatus = 404;
      Object? error;
      try {
        await _writer(pod).update(_url, (c) => c);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(PodUtils.isNotFound(error!), isTrue);
    });

    test('403 menjadi AccessForbiddenException', () async {
      final pod = _FakePod('a')..forcePutStatus = 403;
      expect(
        _writer(pod).update(_url, (c) => '${c}b'),
        throwsA(isA<AccessForbiddenException>()),
      );
    });

    test('konflik terus-menerus: berhenti di maxAttempts', () async {
      final pod = _FakePod('a');
      pod.beforePut = () {
        pod.body = '${pod.body}x';
        pod.version++;
      };

      await expectLater(
        _writer(pod, maxAttempts: 3).update(_url, (c) => '${c}b'),
        throwsA(isA<PodUpdateConflictException>()),
      );
      expect(pod.puts, hasLength(3));
    });

    test('server selalu 412 dengan ETag & isi sama: tulis tanpa If-Match',
        () async {
      final pod = _FakePod('a')..brokenIfMatch = true;

      await _writer(pod).update(_url, (c) => '${c}b');

      final conditional = pod.puts.where(
        (r) => r.headers.containsKey('If-Match'),
      );
      expect(conditional, hasLength(2),
          reason: 'berhenti setelah 412 identik kedua');
      expect(pod.puts.last.headers.containsKey('If-Match'), isFalse);
      expect(pod.body, 'ab');
    });

    test('401: pakai jalur baca/tulis cadangan solidpod', () async {
      final pod = _FakePod('a')..forceGetStatus = 401;
      String? written;
      String? owner;
      await _writer(
        pod,
        fallbackRead: (_) async => 'from-solidpod',
        fallbackWrite: (url, content, ownerWebId) async {
          written = content;
          owner = ownerWebId;
        },
      ).update(_url, (c) => '$c!');

      expect(written, 'from-solidpod!');
      expect(owner, 'https://pod.example/alice/profile/card#me');
      expect(pod.puts, isEmpty);
    });

    test('createIfMissing: 404 -> buat dengan If-None-Match: *', () async {
      final pod = _FakePod('')..forceGetStatus = 404;
      final written = await _writer(pod).update(
        _url,
        (c) => c.isEmpty ? 'baru' : 'salah',
        createIfMissing: true,
      );
      expect(written, isTrue);
      expect(pod.body, 'baru');
      expect(pod.puts.single.headers['If-None-Match'], '*');
      expect(pod.puts.single.headers.containsKey('If-Match'), isFalse);
    });

    test('allowFallback false: 401 dilempar, bukan dialihkan', () async {
      final pod = _FakePod('a')..forceGetStatus = 401;
      await expectLater(
        _writer(pod).update(_url, (c) => '$c!', allowFallback: false),
        throwsException,
      );
      expect(pod.puts, isEmpty);
    });

    test('post: POST ke container dengan Slug', () async {
      http.Request? sent;
      final writer = PodAtomicWriter(
        client: MockClient((req) async {
          sent = req;
          return http.Response('', 201);
        }),
        tokens: (_, _) async => (accessToken: 'at', dPopToken: 'p'),
      );
      await writer.post(
        'https://pod.example/alice/motorqu-solid/data/group_requests/g1/',
        'isi',
        slug: 'req-1.ttl',
      );
      expect(sent!.method, 'POST');
      expect(sent!.headers['Slug'], 'req-1.ttl');
      expect(sent!.body, 'isi');
    });

    test('post: 403 menjadi AccessForbiddenException', () async {
      final writer = PodAtomicWriter(
        client: MockClient((_) async => http.Response('', 403)),
        tokens: (_, _) async => (accessToken: 'at', dPopToken: 'p'),
      );
      expect(
        writer.post('https://pod.example/c/', 'x'),
        throwsA(isA<AccessForbiddenException>()),
      );
    });

    test('token DPoP dibuat baru untuk setiap request', () async {
      final pod = _FakePod('a');
      await _writer(pod).update(_url, (c) => '${c}b');
      expect(
        pod.gets.single.headers['DPoP'],
        isNot(pod.puts.single.headers['DPoP']),
      );
    });
  });

  group('PodWriteQueue', () {
    test('menjalankan tugas satu per satu sesuai urutan', () async {
      final log = <String>[];
      final first = PodWriteQueue.run(() async {
        log.add('1 mulai');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        log.add('1 selesai');
      });
      final second = PodWriteQueue.run(() async => log.add('2'));
      await Future.wait([first, second]);

      expect(log, ['1 mulai', '1 selesai', '2']);
    });

    test('reentrant: panggilan bersarang tidak deadlock', () async {
      final result = await PodWriteQueue.run(
        () => PodWriteQueue.run(() async => 'dalam'),
      ).timeout(const Duration(seconds: 2));
      expect(result, 'dalam');
    });

    test('error satu tugas tidak menghentikan antrean', () async {
      await expectLater(
        PodWriteQueue.run<void>(() async => throw StateError('gagal')),
        throwsStateError,
      );
      expect(await PodWriteQueue.run(() async => 'lanjut'), 'lanjut');
    });
  });
}
