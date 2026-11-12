import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';
import 'package:solidui/solidui.dart';

/// Snapshot data profil pengguna yang diambil dari Solid Pod & WebID Card.
class PodProfile {
  final String webId;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final String? serverUrl;
  final String? storageUrl;
  final String? username;
  final String? host;
  final bool isAuthenticated;

  const PodProfile({
    required this.webId,
    required this.displayName,
    this.email,
    this.photoUrl,
    this.photoBytes,
    this.serverUrl,
    this.storageUrl,
    this.username,
    this.host,
    this.isAuthenticated = false,
  });

  /// Alamat ringkas Pod untuk ditampilkan di kartu profil, misalnya `host/user`.
  String get shortPodAddress {
    if (host != null && host!.isNotEmpty) {
      return (username != null && username!.isNotEmpty)
          ? '$host/$username'
          : host!;
    }
    return WebIdParts.formatForDisplay(webId);
  }
}

/// Service autentikasi & pembacaan profil Solid Pod untuk MotorQu.
class AuthService {
  static const String _pimStoragePred = 'http://www.w3.org/ns/pim/space#storage';
  static const String _foafImgPred = '${foaf}img';
  static const String _foafDepictionPred = '${foaf}depiction';
  static const String _vcardValuePred = 'http://www.w3.org/2006/vcard/ns#value';

  Future<void> signInWithPod() async {}

  /// Mengambil WebID pengguna yang tersimpan pada sesi aktif.
  Future<String?> getCurrentWebId() async {
    try {
      return await getWebId();
    } on Object catch (e) {
      debugPrint('AuthService.getCurrentWebId gagal: $e');
      return null;
    }
  }

  /// Memeriksa apakah pengguna masih memiliki sesi Solid Pod yang valid.
  Future<bool> isLoggedIn() async {
    try {
      return await isUserLoggedIn();
    } on Object catch (e) {
      debugPrint('AuthService.isLoggedIn gagal: $e');
      return false;
    }
  }

  /// Mengambil data profil pengguna dari sesi aktif, `solidProfileNotifier`,
  /// serta dokumen WebID Profile Card (`profile/card`).
  Future<PodProfile?> loadPodProfile() async {
    final webId = await getCurrentWebId();
    if (webId == null || webId.trim().isEmpty) return null;

    final loggedIn = await isLoggedIn();
    final parts = WebIdParts.tryParse(webId);

    await _ensureAppDirInitialized();

    String? cardName;
    String? cardEmail;
    String? cardPhotoUrl;
    Uint8List? cardPhotoBytes;
    String? storageUrl;

    final cardUrl = _stripFragment(webId);
    final cardTtl = await _fetchProfileCardTtl(cardUrl, loggedIn: loggedIn);
    if (cardTtl != null && cardTtl.trim().isNotEmpty) {
      final parsed = _parseWebIdCard(cardTtl, webId, cardUrl);
      cardName = parsed.name;
      cardEmail = parsed.email;
      cardPhotoUrl = parsed.photoUrl;
      cardPhotoBytes = parsed.photoBytes;
      storageUrl = parsed.storageUrl;

      // Jika foto berada di host Pod yang sama, ambil via DPoP agar tetap tampil
      // meski resource foto tidak ber-ACL publik.
      if (cardPhotoBytes == null &&
          cardPhotoUrl != null &&
          loggedIn &&
          _isSameHost(cardPhotoUrl, webId)) {
        cardPhotoBytes = await _tryFetchPodBytes(cardPhotoUrl);
      }
    }

    final notifierName = solidProfileNotifier.displayName?.trim();
    final notifierAvatar = solidProfileNotifier.avatarBytes;

    final resolvedName = (notifierName != null && notifierName.isNotEmpty)
        ? notifierName
        : (cardName != null && cardName.isNotEmpty)
        ? cardName
        : (parts != null && parts.username.isNotEmpty)
        ? parts.username
        : 'Pengguna MotorQu';

    final resolvedPhotoBytes =
        (notifierAvatar != null && notifierAvatar.isNotEmpty)
        ? notifierAvatar
        : cardPhotoBytes;

    return PodProfile(
      webId: webId,
      displayName: resolvedName,
      email: cardEmail,
      photoUrl: cardPhotoUrl,
      photoBytes: resolvedPhotoBytes,
      serverUrl: parts?.serverUri,
      storageUrl: storageUrl,
      username: parts?.username,
      host: parts?.host,
      isAuthenticated: loggedIn,
    );
  }

  /// Mengambil daftar grup berbagi yang tersimpan di Solid Pod pengguna.
  Future<List<SharedGroup>> loadSharedGroups() async {
    try {
      if (!await isLoggedIn()) return const [];
      await _ensureAppDirInitialized();
      return await getSharedGroups();
    } on Object catch (e) {
      debugPrint('AuthService.loadSharedGroups gagal: $e');
      return const [];
    }
  }

  /// Keluar dari sesi Solid Pod dan membersihkan seluruh cache lokal terkait.
  Future<void> signOut() async {
    try {
      await logoutPod();
    } on Object catch (e) {
      debugPrint('AuthService.signOut logoutPod gagal: $e');
      try {
        await silentLogout();
      } on Object catch (_) {
        try {
          await deleteLogIn();
        } on Object catch (_) {}
      }
    } finally {
      SolidProfileService.instance.clearCache();
      SolidOwnerProfileService.instance.clearCache();
      solidLoginStatusNotifier.markLoggedOut();
      securityKeyNotifier.reset();
    }
  }

  Future<void> _ensureAppDirInitialized() async {
    try {
      if (SolidConstants.directories.app.isEmpty) {
        await setAppDirName('');
      }
    } on Object catch (e) {
      debugPrint('AuthService._ensureAppDirInitialized gagal: $e');
    }
  }

  Future<String?> _fetchProfileCardTtl(
    String cardUrl, {
    required bool loggedIn,
  }) async {
    if (loggedIn) {
      try {
        final bytes = await getResource(cardUrl);
        return utf8.decode(bytes);
      } on Object catch (e) {
        debugPrint('AuthService._fetchProfileCardTtl getResource gagal: $e');
      }
    }

    try {
      final response = await http
          .get(
            Uri.parse(cardUrl),
            headers: const {'Accept': 'text/turtle, text/n3;q=0.9'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return response.body;
      }
    } on Object catch (e) {
      debugPrint('AuthService._fetchProfileCardTtl http.get gagal: $e');
    }
    return null;
  }

  Future<Uint8List?> _tryFetchPodBytes(String url) async {
    try {
      return await getResource(url);
    } on Object catch (_) {
      return null;
    }
  }

  ({
    String? name,
    String? email,
    String? photoUrl,
    Uint8List? photoBytes,
    String? storageUrl,
  })
  _parseWebIdCard(String ttl, String webId, String cardUrl) {
    Map<String, Map<String, dynamic>> tripleMap;
    try {
      tripleMap = turtleToTripleMap(ttl);
    } on Object catch (_) {
      return (
        name: null,
        email: null,
        photoUrl: null,
        photoBytes: null,
        storageUrl: null,
      );
    }

    final personSubjects = _candidateSubjects(tripleMap, webId);

    final name = _findFirstString(personSubjects, [
      FoafPredicate.name.value,
      VcardPredicate.fn.value,
    ]);

    final rawEmail = _findFirstString(personSubjects, [
      VcardPredicate.hasEmail.value,
      FoafPredicate.mbox.value,
    ]);
    final email = _resolveEmailValue(rawEmail, tripleMap);

    final rawPhoto = _findFirstString(personSubjects, [
      VcardPredicate.hasPhoto.value,
      _foafImgPred,
      _foafDepictionPred,
    ]);
    final (:photoUrl, :photoBytes) = _resolvePhoto(rawPhoto, cardUrl);

    final rawStorage = _findFirstString(personSubjects, [_pimStoragePred]);
    final storageUrl = rawStorage != null
        ? _resolveUri(rawStorage, cardUrl)
        : null;

    return (
      name: name,
      email: email,
      photoUrl: photoUrl,
      photoBytes: photoBytes,
      storageUrl: storageUrl,
    );
  }

  List<Map<String, dynamic>> _candidateSubjects(
    Map<String, Map<String, dynamic>> tripleMap,
    String webId,
  ) {
    final result = <Map<String, dynamic>>[];
    final added = <Map<String, dynamic>>{};

    void addIfPresent(String key) {
      final entry = tripleMap[key];
      if (entry != null && added.add(entry)) {
        result.add(entry);
      }
    }

    addIfPresent(webId);
    final hashIndex = webId.indexOf('#');
    if (hashIndex >= 0) {
      addIfPresent(webId.substring(hashIndex));
    }
    addIfPresent('#me');

    for (final entry in tripleMap.values) {
      if (added.add(entry)) {
        result.add(entry);
      }
    }
    return result;
  }

  String? _findFirstString(
    List<Map<String, dynamic>> subjects,
    List<String> predicates,
  ) {
    for (final subject in subjects) {
      for (final predicate in predicates) {
        final raw = subject[predicate];
        final value = _firstNonEmptyString(raw);
        if (value != null) return value;
      }
    }
    return null;
  }

  String? _firstNonEmptyString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) {
          return item.trim();
        }
      }
    }
    return null;
  }

  String? _resolveEmailValue(
    String? rawEmail,
    Map<String, Map<String, dynamic>> tripleMap,
  ) {
    if (rawEmail == null || rawEmail.isEmpty) return null;
    var resolved = rawEmail;
    final linkedNode = tripleMap[rawEmail];
    if (linkedNode != null) {
      final nodeValue = _firstNonEmptyString(linkedNode[_vcardValuePred]);
      if (nodeValue != null) {
        resolved = nodeValue;
      }
    }
    if (resolved.startsWith('mailto:')) {
      resolved = resolved.substring('mailto:'.length);
    }
    return resolved.trim().isEmpty ? null : resolved.trim();
  }

  ({String? photoUrl, Uint8List? photoBytes}) _resolvePhoto(
    String? rawPhoto,
    String cardUrl,
  ) {
    if (rawPhoto == null || rawPhoto.isEmpty) {
      return (photoUrl: null, photoBytes: null);
    }

    const base64Marker = ';base64,';
    final markerIdx = rawPhoto.indexOf(base64Marker);
    if (rawPhoto.startsWith('data:') && markerIdx >= 0) {
      try {
        final bytes = base64Decode(
          rawPhoto.substring(markerIdx + base64Marker.length),
        );
        return (photoUrl: null, photoBytes: bytes);
      } on Object catch (_) {
        return (photoUrl: null, photoBytes: null);
      }
    }

    return (photoUrl: _resolveUri(rawPhoto, cardUrl), photoBytes: null);
  }

  String _resolveUri(String raw, String baseUrl) {
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) {
      return raw;
    }
    final base = Uri.tryParse(baseUrl);
    return base != null ? base.resolve(raw).toString() : raw;
  }

  String _stripFragment(String url) {
    final idx = url.indexOf('#');
    return idx >= 0 ? url.substring(0, idx) : url;
  }

  bool _isSameHost(String a, String b) {
    final uriA = Uri.tryParse(a);
    final uriB = Uri.tryParse(b);
    return uriA != null &&
        uriB != null &&
        uriA.host.isNotEmpty &&
        uriA.host == uriB.host;
  }
}
