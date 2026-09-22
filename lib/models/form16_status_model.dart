// Form 16 availability, as returned by GET /api/form16/status.
//
// The certificate comes in two halves (Part A / Part B) and can be issued from
// two sources (TRACES / MECPL), so the payload is a source -> part -> status
// grid. A part carries an `id` only when it is available; that id is what
// /api/form16/download/{id} takes.
//
// {
//   "status": true,
//   "data": {
//     "financial_year": "2026-27",
//     "sources": {
//       "traces": { "part_a": {"id": 2, "available": true}, ... },
//       "mecpl":  { "part_a": {"id": null, "available": false}, ... }
//     }
//   }
// }

/// Which body issued the certificate. Matches the `sources` keys verbatim.
enum Form16Source {
  traces('traces'),
  mecpl('mecpl');

  const Form16Source(this.key);
  final String key;
}

/// Which half of the certificate. Matches the per-source keys verbatim.
enum Form16Part {
  partA('part_a', 'Part A'),
  partB('part_b', 'Part B');

  const Form16Part(this.key, this.label);
  final String key;
  final String label;
}

class Form16PartStatus {
  final int? id;
  final bool available;

  const Form16PartStatus({this.id, required this.available});

  /// Guards against `available: true` with a null id — without an id there is
  /// nothing to download, so treat it as unavailable rather than letting the
  /// UI offer a button that cannot work.
  bool get isDownloadable => available && id != null;

  factory Form16PartStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Form16PartStatus(available: false);
    final rawId = json['id'];
    return Form16PartStatus(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? ''),
      available: json['available'] == true,
    );
  }

  static const unavailable = Form16PartStatus(available: false);
}

class Form16Status {
  final String? financialYear;

  /// source key -> part key -> status.
  final Map<String, Map<String, Form16PartStatus>> _sources;

  const Form16Status({
    this.financialYear,
    required Map<String, Map<String, Form16PartStatus>> sources,
  }) : _sources = sources;

  /// Never throws: an absent source or part reads as unavailable, so a
  /// backend that drops a key degrades to "not available" instead of an error.
  Form16PartStatus partStatus(Form16Source source, Form16Part part) =>
      _sources[source.key]?[part.key] ?? Form16PartStatus.unavailable;

  factory Form16Status.fromJson(Map<String, dynamic> json) {
    // Accepts either the full envelope or just the `data` object.
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final rawSources = data['sources'];

    final sources = <String, Map<String, Form16PartStatus>>{};
    if (rawSources is Map) {
      rawSources.forEach((sourceKey, parts) {
        if (parts is! Map) return;
        final byPart = <String, Form16PartStatus>{};
        parts.forEach((partKey, status) {
          byPart['$partKey'] = Form16PartStatus.fromJson(
            status is Map<String, dynamic> ? status : null,
          );
        });
        sources['$sourceKey'] = byPart;
      });
    }

    return Form16Status(
      financialYear: data['financial_year']?.toString(),
      sources: sources,
    );
  }
}
