import 'package:solidpod/solidpod.dart';

/// Shared helpers for Solid Pod path resolution and error classification.
class PodUtils {
  PodUtils._();

  static bool isNotFound(Object e) {
    final s = e.toString();
    return e.runtimeType.toString() == 'ResourceNotExistException' ||
        s.contains('does not exist') ||
        s.contains('404');
  }

  /// Versi ketat dari [isNotFound]: HANYA `ResourceNotExistException`.
  ///
  /// Wajib dipakai di jalur yang menghapus/mengembalikan data ke pribadi.
  /// [isNotFound] mencocokkan teks "404", yang bisa muncul di URL (UUID grup,
  /// nama Pod) pada galat lain seperti HTTP 500.
  static bool isDefinitelyNotFound(Object e) => e is ResourceNotExistException;

  static String lastSegment(String s) =>
      Uri.parse(s).pathSegments.where((e) => e.isNotEmpty).last;

  static Future<String> ownDataRootPrefix() async {
    final baseDirUrl = await getDirUrl('motorqu-solid/data');
    return baseDirUrl.endsWith('/') ? baseDirUrl : '$baseDirUrl/';
  }

  static Future<bool> isExternalUrl(String? resourceUrl) async {
    if (resourceUrl == null || resourceUrl.isEmpty) return false;
    final ownPrefix = await ownDataRootPrefix();
    return !resourceUrl.startsWith(ownPrefix);
  }

  static String resolveOwnerWebId(
    String resourceUrl, {
    required String fallback,
  }) {
    final markerIndex = resourceUrl.indexOf('/motorqu-solid/');
    if (markerIndex != -1) {
      final podBase = resourceUrl.substring(0, markerIndex);
      return '$podBase/profile/card#me';
    }
    return fallback;
  }
}
