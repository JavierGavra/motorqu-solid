import 'package:motorqu_solid/models/turtle_utils.dart';

class OilRecord {
  final String id;
  final String motorcycleId;
  final DateTime performedAt;
  final int odometer;
  final String performedBy; // WebID pelaku
  final String? performedByName; // salinan nama saat record dibuat
  final DateTime createdAt;

  const OilRecord({
    required this.id,
    required this.motorcycleId,
    required this.performedAt,
    required this.odometer,
    required this.performedBy,
    this.performedByName,
    required this.createdAt,
  });

  OilRecord copyWith({String? id, String? motorcycleId}) {
    return OilRecord(
      id: id ?? this.id,
      motorcycleId: motorcycleId ?? this.motorcycleId,
      performedAt: performedAt,
      odometer: odometer,
      performedBy: performedBy,
      performedByName: performedByName,
      createdAt: createdAt,
    );
  }

  /// Satu record -> satu blok Turtle (tanpa prefix).
  String toTurtle() {
    final props = <String>[
      'moto:motorcycleId "${turtleEsc(motorcycleId)}"',
      'moto:performedAt ${turtleDt(performedAt)}',
      'moto:odometer $odometer',
      'moto:performedBy "${turtleEsc(performedBy)}"',
      // Perilaku sama dengan toMap() lama: nama jatuh ke performedBy.
      'moto:performedByName "${turtleEsc(performedByName ?? performedBy)}"',
      'schema:dateCreated ${turtleDt(createdAt)}',
    ];

    final b = StringBuffer('<#record-$id> a moto:OilRecord ;\n');
    for (var i = 0; i < props.length; i++) {
      b.writeln('    ${props[i]}${i == props.length - 1 ? ' .' : ' ;'}');
    }
    return b.toString();
  }

  /// Satu file Turtle -> satu record. ID diambil dari subjek `<#record-ID>`.
  factory OilRecord.fromTurtle(String turtle) {
    final idMatch = RegExp(r'<#record-([^>]+)>').firstMatch(turtle);
    if (idMatch == null) {
      throw const FormatException('Subjek <#record-ID> tidak ditemukan');
    }

    final p = turtleProps(turtle);
    String? one(String k) => p[k]?.first;

    return OilRecord(
      id: idMatch.group(1)!,
      motorcycleId: one('moto:motorcycleId') ?? '',
      performedAt:
          DateTime.tryParse(one('moto:performedAt') ?? '') ?? DateTime.now(),
      odometer: int.tryParse(one('moto:odometer') ?? '') ?? 0,
      performedBy: one('moto:performedBy') ?? '',
      performedByName: one('moto:performedByName'),
      createdAt:
          DateTime.tryParse(one('schema:dateCreated') ?? '') ?? DateTime.now(),
    );
  }

  /// Isi lengkap satu file .ttl (prefix + blok).
  String toTurtleFile() => turtlePrefixes + toTurtle();
}
