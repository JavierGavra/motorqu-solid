import 'package:motorqu_solid/models/turtle_utils.dart';

/// Permintaan bergabung grup yang ditulis calon anggota ke container
/// `group_requests/<groupId>/` di Pod host grup (izin Append saja).
class JoinRequest {
  const JoinRequest({
    required this.groupId,
    required this.memberWebId,
    required this.code,
    required this.requestedAt,
  });

  final String groupId;
  final String memberWebId;
  final String code;
  final DateTime requestedAt;

  static const _grpNs = 'https://example.org/motorqu-group#';

  String toTurtle() =>
      '@prefix grp: <$_grpNs> .\n'
      '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n'
      '<#request> a grp:JoinRequest ;\n'
      '    grp:groupId "${turtleEsc(groupId)}" ;\n'
      '    grp:memberUid "${turtleEsc(memberWebId)}" ;\n'
      '    grp:code "${turtleEsc(code)}" ;\n'
      '    grp:requestedAt ${turtleDt(requestedAt)} .\n';

  /// Mengembalikan `null` bila isi tidak sesuai format (mis. spam).
  static JoinRequest? tryParse(String turtle) {
    final p = turtleProps(turtle);
    String? one(String k) => p[k]?.first;
    final groupId = one('grp:groupId');
    final member = one('grp:memberUid');
    final code = one('grp:code');
    final at = DateTime.tryParse(one('grp:requestedAt') ?? '');
    if (groupId == null || member == null || code == null || at == null) {
      return null;
    }
    return JoinRequest(
      groupId: groupId,
      memberWebId: member,
      code: code.trim().toUpperCase(),
      requestedAt: at,
    );
  }
}
