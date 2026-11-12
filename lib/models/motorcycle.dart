class Motorcycle {
  final String id;
  final String name;
  final String brand;
  final String model;
  final String? plate;
  final String? year;
  final String? color;
  final String groupId; // Bisa berisi 'private_{uid}' atau 'groupId_familia'
  final bool isGroupMotor;
  final int reminderIntervalKm;
  final int lastOdometer;
  final DateTime? lastServiceAt;
  final List<String> memberUids;
  final String createdBy;
  final DateTime createdAt;

  Motorcycle({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    this.plate,
    this.year,
    this.color,
    required this.groupId,
    this.isGroupMotor = false,
    this.reminderIntervalKm = 2000,
    this.lastOdometer = 0,
    this.lastServiceAt,
    this.memberUids = const [],
    required this.createdBy,
    required this.createdAt,
  });

  /// Target KM berikutnya: lastOdometer + reminderIntervalKm
  int get nextDueKm => lastOdometer + reminderIntervalKm;

  /// Status penggantian oli
  String get status {
    // Status dihitung manual oleh user atau nanti bisa ditambah update otomatis.
    return 'Aman';
  }

  Motorcycle copyWith({
    String? id,
    String? name,
    String? brand,
    String? model,
    String? plate,
    String? year,
    String? color,
    String? groupId,
    bool? isGroupMotor,
    int? reminderIntervalKm,
    int? lastOdometer,
    DateTime? lastServiceAt,
    List<String>? memberUids,
    String? createdBy,
    DateTime? createdAt,
    bool clearPlate = false,
    bool clearYear = false,
    bool clearColor = false,
    bool clearLastServiceAt = false,
  }) {
    return Motorcycle(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      plate: clearPlate ? null : (plate ?? this.plate),
      year: clearYear ? null : (year ?? this.year),
      color: clearColor ? null : (color ?? this.color),
      groupId: groupId ?? this.groupId,
      isGroupMotor: isGroupMotor ?? this.isGroupMotor,
      reminderIntervalKm: reminderIntervalKm ?? this.reminderIntervalKm,
      lastOdometer: lastOdometer ?? this.lastOdometer,
      lastServiceAt: clearLastServiceAt
          ? null
          : (lastServiceAt ?? this.lastServiceAt),
      memberUids: memberUids ?? this.memberUids,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const turtlePrefixes =
      '@prefix schema: <https://schema.org/> .\n'
      '@prefix moto: <$_motoNs> .\n'
      '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n';

  /// Satu motor -> satu blok Turtle (tanpa prefix).
  String toTurtle() {
    final props = <String>[
      'schema:name "${_esc(name)}"',
      'moto:brand "${_esc(brand)}"',
      'moto:model "${_esc(model)}"',
      if (plate != null) 'moto:plate "${_esc(plate!)}"',
      if (year != null) 'moto:year "${_esc(year!)}"',
      if (color != null) 'schema:color "${_esc(color!)}"',
      'moto:groupId "${_esc(groupId)}"',
      'moto:isGroupMotor $isGroupMotor',
      'moto:reminderIntervalKm $reminderIntervalKm',
      'moto:lastOdometer $lastOdometer',
      if (lastServiceAt != null) 'moto:lastServiceAt ${_dt(lastServiceAt!)}',
      for (final uid in memberUids) 'moto:memberUid "${_esc(uid)}"',
      'moto:createdBy "${_esc(createdBy)}"',
      'schema:dateCreated ${_dt(createdAt)}',
    ];

    final b = StringBuffer('<#moto-$id> a moto:Motorcycle ;\n');
    for (var i = 0; i < props.length; i++) {
      b.writeln('    ${props[i]}${i == props.length - 1 ? ' .' : ' ;'}');
    }
    return b.toString();
  }

  /// Satu blok Turtle -> satu motor. ID diambil dari subjek `<#moto-ID>`.
  factory Motorcycle.fromTurtle(String turtle) {
    final idMatch = RegExp(r'<#moto-([^>]+)>').firstMatch(turtle);
    if (idMatch == null) {
      throw const FormatException('Subjek <#moto-ID> tidak ditemukan');
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

    return Motorcycle(
      id: idMatch.group(1)!,
      name: one('schema:name') ?? '',
      brand: one('moto:brand') ?? '',
      model: one('moto:model') ?? '',
      plate: one('moto:plate'),
      year: one('moto:year'),
      color: one('schema:color'),
      groupId: one('moto:groupId') ?? '',
      isGroupMotor: one('moto:isGroupMotor') == 'true',
      reminderIntervalKm:
          int.tryParse(one('moto:reminderIntervalKm') ?? '') ?? 2000,
      lastOdometer: int.tryParse(one('moto:lastOdometer') ?? '') ?? 0,
      lastServiceAt: DateTime.tryParse(one('moto:lastServiceAt') ?? ''),
      memberUids: p['moto:memberUid'] ?? const [],
      createdBy: one('moto:createdBy') ?? '',
      createdAt:
          DateTime.tryParse(one('schema:dateCreated') ?? '') ?? DateTime.now(),
    );
  }

  /// Daftar motor <-> isi satu file .ttl
  static String listToTurtle(List<Motorcycle> list) =>
      turtlePrefixes + list.map((m) => m.toTurtle()).join('\n');

  static List<Motorcycle> listFromTurtle(String turtle) {
    return turtle
        .split(RegExp(r'(?=^<#moto-)', multiLine: true))
        .where((block) => block.trimLeft().startsWith('<#moto-'))
        .map(Motorcycle.fromTurtle)
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Motorcycle && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

const _motoNs = 'https://example.org/motorqu#'; // GANTI dengan milikmu

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
