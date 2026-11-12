/// Utilitas Turtle bersama untuk model-model MotorQu.

/// Namespace vocabulary buatan sendiri (predikat `moto:`).
const motoNs = 'https://example.org/motorqu#'; // GANTI dengan milikmu

/// Prefix yang ditaruh di awal setiap file .ttl.
const turtlePrefixes =
    '@prefix schema: <https://schema.org/> .\n'
    '@prefix moto: <$motoNs> .\n'
    '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n';

/// Escape string agar aman dijadikan literal Turtle ("...").
String turtleEsc(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\r', '')
    .replaceAll('\n', r'\n');

String _unesc(String s) =>
    s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);

/// "teks"^^tipe -> teks ; angka/boolean mentah -> apa adanya.
String turtleLiteral(String raw) {
  final m = RegExp(r'^"((?:[^"\\]|\\.)*)"').firstMatch(raw.trim());
  return m != null ? _unesc(m.group(1)!) : raw.trim();
}

/// DateTime -> literal xsd:dateTime (UTC).
String turtleDt(DateTime d) => '"${d.toUtc().toIso8601String()}"^^xsd:dateTime';

/// Kumpulkan predikat -> daftar nilai dari satu blok Turtle.
/// Hanya untuk format yang ditulis oleh `toTurtle()` milik model sendiri.
Map<String, List<String>> turtleProps(String turtle) {
  final propRe = RegExp(r'^\s+(\w+:\w+)\s+(.+?)\s*[;.]\s*$');
  final props = <String, List<String>>{};
  for (final line in turtle.split('\n')) {
    final m = propRe.firstMatch(line);
    if (m != null) {
      props.putIfAbsent(m.group(1)!, () => []).add(turtleLiteral(m.group(2)!));
    }
  }
  return props;
}
