// Everything the employee has on file for the current financial year, as
// returned by GET /api/my-documents (see docs/my-documents-api.md).
//
// One call covers three things:
//   * Form 16 TRACES — Part A and Part B, one file each (latest version).
//   * Form 16 MECPL  — a *list* of Part B files, each with its own version.
//   * Health card    — a single medical card PDF.
// Every downloadable item carries an upload `id`; that id is what
// /form16/download/{id} and /health-card/download/{id} take.
//
// {
//   "status": true,
//   "data": {
//     "financial_year": "26-27",
//     "form16": {
//       "traces": { "part_a": {"id": 42, "available": true}, "part_b": {...} },
//       "mecpl":  { "count": 3, "available": true, "files": [
//         {"id": 101, "filename": "AAOPW6536B.pdf", "version": 1}, ...
//       ]}
//     },
//     "health_card": { "id": 55, "available": true }
//   }
// }

/// A single downloadable document: an id when it exists, plus the server's
/// own availability flag.
class DocumentRef {
  final int? id;
  final bool available;

  const DocumentRef({this.id, required this.available});

  /// Guards against `available: true` with a null id — without an id there is
  /// nothing to fetch, so treat it as unavailable rather than letting the UI
  /// offer a button that cannot work.
  bool get isDownloadable => available && id != null;

  factory DocumentRef.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DocumentRef(available: false);
    final rawId = json['id'];
    return DocumentRef(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? ''),
      available: json['available'] == true,
    );
  }

  static const unavailable = DocumentRef(available: false);
}

/// One MECPL-issued Part B file. Employees can have several, distinguished by
/// [version].
class MecplForm16File {
  final int id;
  final String filename;
  final int version;

  const MecplForm16File({
    required this.id,
    required this.filename,
    required this.version,
  });

  static MecplForm16File? fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return null; // unusable without a download id
    final rawVersion = json['version'];
    return MecplForm16File(
      id: id,
      filename: json['filename']?.toString() ?? 'form16_$id.pdf',
      version: rawVersion is int
          ? rawVersion
          : int.tryParse(rawVersion?.toString() ?? '') ?? 1,
    );
  }
}

class MyDocuments {
  final String? financialYear;
  final DocumentRef tracesPartA;
  final DocumentRef tracesPartB;
  final List<MecplForm16File> mecplFiles;
  final DocumentRef healthCard;

  const MyDocuments({
    this.financialYear,
    this.tracesPartA = DocumentRef.unavailable,
    this.tracesPartB = DocumentRef.unavailable,
    this.mecplFiles = const [],
    this.healthCard = DocumentRef.unavailable,
  });

  bool get hasMecplFiles => mecplFiles.isNotEmpty;

  /// Tolerant of missing keys throughout: a backend that drops a block reads
  /// as "not available" instead of throwing.
  factory MyDocuments.fromJson(Map<String, dynamic> json) {
    // Accepts either the full envelope or just the `data` object.
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    Map<String, dynamic>? mapAt(dynamic value) =>
        value is Map<String, dynamic> ? value : null;

    final form16 = mapAt(data['form16']);
    final traces = mapAt(form16?['traces']);
    final mecpl = mapAt(form16?['mecpl']);

    final files = <MecplForm16File>[];
    final rawFiles = mecpl?['files'];
    if (rawFiles is List) {
      for (final entry in rawFiles) {
        if (entry is! Map<String, dynamic>) continue;
        final file = MecplForm16File.fromJson(entry);
        if (file != null) files.add(file);
      }
    }

    return MyDocuments(
      financialYear: data['financial_year']?.toString(),
      tracesPartA: DocumentRef.fromJson(mapAt(traces?['part_a'])),
      tracesPartB: DocumentRef.fromJson(mapAt(traces?['part_b'])),
      mecplFiles: files,
      healthCard: DocumentRef.fromJson(mapAt(data['health_card'])),
    );
  }
}
