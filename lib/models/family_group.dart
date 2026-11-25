class FamilyGroup {
  final String id;
  final String name;
  final String ownerId; // WebID pembuat grup utama
  final List<String> ownerIds; // Daftar WebID admin/owner grup
  final List<String> memberUids; // Daftar WebID seluruh anggota
  final List<String>
  sharedMotorUrls; // URL lengkap motorcycle.ttl anggota di grup
  final String groupResourceUrl; // URL lengkap file group.ttl di Pod owner
  final String? activeInviteCode; // Token sekali pakai untuk QR
  final DateTime? inviteExpiresAt;
  final DateTime createdAt;

  FamilyGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    this.ownerIds = const [],
    required this.memberUids,
    this.sharedMotorUrls = const [],
    this.groupResourceUrl = '',
    this.activeInviteCode,
    this.inviteExpiresAt,
    required this.createdAt,
  });

  bool isOwner(String uid) =>
      ownerIds.contains(uid) || (ownerId.isNotEmpty && ownerId == uid);

  FamilyGroup copyWith({
    String? id,
    String? name,
    String? ownerId,
    List<String>? ownerIds,
    List<String>? memberUids,
    List<String>? sharedMotorUrls,
    String? groupResourceUrl,
    String? activeInviteCode,
    DateTime? inviteExpiresAt,
    DateTime? createdAt,
    bool clearInvite = false,
  }) {
    return FamilyGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      ownerIds: ownerIds ?? this.ownerIds,
      memberUids: memberUids ?? this.memberUids,
      sharedMotorUrls: sharedMotorUrls ?? this.sharedMotorUrls,
      groupResourceUrl: groupResourceUrl ?? this.groupResourceUrl,
      activeInviteCode: clearInvite
          ? null
          : (activeInviteCode ?? this.activeInviteCode),
      inviteExpiresAt: clearInvite
          ? null
          : (inviteExpiresAt ?? this.inviteExpiresAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const _grpNs = 'https://example.org/motorqu-group#';

  static const turtlePrefixes =
      '@prefix schema: <https://schema.org/> .\n'
      '@prefix grp: <$_grpNs> .\n'
      '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n';

  String toTurtle() {
    final effectiveOwners = ownerIds.isNotEmpty
        ? ownerIds
        : (ownerId.isNotEmpty ? <String>[ownerId] : <String>[]);

    final props = <String>[
      'schema:name "${_esc(name)}"',
      'grp:ownerId "${_esc(ownerId)}"',
      if (groupResourceUrl.isNotEmpty)
        'grp:groupResourceUrl "${_esc(groupResourceUrl)}"',
      for (final oid in effectiveOwners) 'grp:ownerUid "${_esc(oid)}"',
      for (final mid in memberUids) 'grp:memberUid "${_esc(mid)}"',
      for (final mUrl in sharedMotorUrls) 'grp:sharedMotorUrl "${_esc(mUrl)}"',
      if (activeInviteCode != null)
        'grp:activeInviteCode "${_esc(activeInviteCode!)}"',
      if (inviteExpiresAt != null)
        'grp:inviteExpiresAt ${_dt(inviteExpiresAt!)}',
      'schema:dateCreated ${_dt(createdAt)}',
    ];

    final b = StringBuffer('<#group-$id> a grp:FamilyGroup ;\n');
    for (var i = 0; i < props.length; i++) {
      b.writeln('    ${props[i]}${i == props.length - 1 ? ' .' : ' ;'}');
    }
    return b.toString();
  }

  factory FamilyGroup.fromTurtle(String turtle, {String? fallbackUrl}) {
    final idMatch = RegExp(r'<#group-([^>]+)>').firstMatch(turtle);
    if (idMatch == null) {
      throw const FormatException('Subjek <#group-ID> tidak ditemukan');
    }

    final propRe = RegExp(r'^\s+(\w+:\w+)\s+(.+?)\s*[;.]\s*$');
    final p = <String, List<String>>{};
    for (final line in turtle.split('\n')) {
      final m = propRe.firstMatch(line);
      if (m != null) {
        p.putIfAbsent(m.group(1)!, () => []).add(_literal(m.group(2)!));
      }
    }
    String? one(String k) => p[k]?.first;

    final ownerId = one('grp:ownerId') ?? '';
    final parsedOwners = p['grp:ownerUid'] ?? const [];
    final ownerIdsList = parsedOwners.isNotEmpty
        ? parsedOwners
        : (ownerId.isNotEmpty ? <String>[ownerId] : <String>[]);

    return FamilyGroup(
      id: idMatch.group(1)!,
      name: one('schema:name') ?? '',
      ownerId: ownerId,
      ownerIds: ownerIdsList,
      memberUids: p['grp:memberUid'] ?? const [],
      sharedMotorUrls: p['grp:sharedMotorUrl'] ?? const [],
      groupResourceUrl: one('grp:groupResourceUrl') ?? (fallbackUrl ?? ''),
      activeInviteCode: one('grp:activeInviteCode'),
      inviteExpiresAt: DateTime.tryParse(one('grp:inviteExpiresAt') ?? ''),
      createdAt:
          DateTime.tryParse(one('schema:dateCreated') ?? '') ?? DateTime.now(),
    );
  }
}

String _esc(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\r', '')
    .replaceAll('\n', r'\n');

String _unesc(String s) =>
    s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);

String _literal(String raw) {
  final m = RegExp(r'^"((?:[^"\\]|\\.)*)"').firstMatch(raw.trim());
  return m != null ? _unesc(m.group(1)!) : raw.trim();
}

String _dt(DateTime d) => '"${d.toUtc().toIso8601String()}"^^xsd:dateTime';
