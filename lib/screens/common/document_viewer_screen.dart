// Full-screen viewer for a document the API references by URL (e.g. the
// `qualification_pdf` field inside a branch payroll request's activity data).
//
// The backend returns either an absolute URL or a path relative to the host
// root ("storage/…"). The bytes are downloaded to a tmp file — flutter_pdfview
// needs a path on disk — and then rendered inline. Images are shown in a
// pinch-zoomable viewer.
//
// Built to never dead-end in production: the file type is decided by sniffing
// the actual bytes (not by trusting the extension), every failure path shows a
// readable message with Retry + "Open in browser", and nothing here can throw
// past the widget — a bad URL, an HTML error page served with status 200, an
// expired session or a corrupt PDF all land on the same handled error state.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// File extensions this viewer can render in-app.
const Set<String> _kViewableExtensions = {
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
};

/// What the downloaded bytes actually turned out to be.
enum _DocKind { pdf, image, unknown }

/// Lower-cased extension of a URL/path, ignoring any `?query` / `#fragment`.
/// Returns null when there is no plausible extension.
String? documentExtension(String raw) {
  final cleaned = raw.split('?').first.split('#').first.trim();
  final dot = cleaned.lastIndexOf('.');
  if (dot == -1 || dot == cleaned.length - 1) return null;
  final ext = cleaned.substring(dot + 1).toLowerCase();
  return ext.length <= 5 ? ext : null;
}

/// True when a raw API value looks like a viewable file reference rather than
/// plain text — an absolute URL or a host-relative path ending in a known
/// document/image extension.
///
/// Relative paths must be whitespace-free so a free-text remark that happens to
/// end in ".pdf" is never mistaken for an attachment; an absolute `http(s)://`
/// value is unambiguous enough that spaces in the filename are tolerated (they
/// get percent-encoded in [resolveFileUrl]).
bool isDocumentReference(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;
  final ext = documentExtension(value);
  if (ext == null || !_kViewableExtensions.contains(ext)) return false;
  final lower = value.toLowerCase();
  final isAbsolute =
      lower.startsWith('http://') || lower.startsWith('https://');
  if (isAbsolute) return true;
  return value.contains('/') && !value.contains(RegExp(r'\s'));
}

/// Turns a raw API file reference into an absolute, parseable URL. Absolute
/// URLs pass through; relative paths are resolved against the host root. Spaces
/// are percent-encoded so [Uri.parse] can't choke on a filename with a space.
///
/// A plain-`http` link to our own host is upgraded to https: iOS App Transport
/// Security blocks cleartext by default, so an http URL from the backend would
/// download fine on Android and silently fail on iPhone.
String resolveFileUrl(String raw) {
  final value = raw.trim().replaceAll(' ', '%20');
  final lower = value.toLowerCase();
  if (lower.startsWith('https://')) return value;
  if (lower.startsWith('http://')) {
    final host = ApiConstants.fileBaseUrl.replaceFirst('https://', '');
    return lower.startsWith('http://$host')
        ? 'https://${value.substring('http://'.length)}'
        : value;
  }
  final path = value.startsWith('/') ? value : '/$value';
  return '${ApiConstants.fileBaseUrl}$path';
}

class DocumentViewerScreen extends StatefulWidget {
  /// Absolute URL of the document. Use [resolveFileUrl] on raw API values.
  final String url;

  /// App-bar title (e.g. the activity-data field label).
  final String title;

  /// Bearer token sent with the download. Optional — public storage paths
  /// don't need it, but protected endpoints do.
  final String? authToken;

  const DocumentViewerScreen({
    super.key,
    required this.url,
    required this.title,
    this.authToken,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  String? _filePath;
  _DocKind _kind = _DocKind.unknown;
  bool _loading = true;
  String? _error;
  bool _sharing = false;

  /// Bumped on every [_load]; a late-arriving PDFView error from a previous
  /// attempt can't then clobber a successful reload.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    setState(() {
      _loading = true;
      _error = null;
      _filePath = null;
      _kind = _DocKind.unknown;
    });

    try {
      final uri = Uri.tryParse(widget.url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        _fail(attempt, 'This document link is not valid.');
        return;
      }

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/pdf,image/*,*/*',
              if (widget.authToken != null &&
                  widget.authToken!.trim().isNotEmpty)
                'Authorization': 'Bearer ${widget.authToken}',
            },
          )
          .timeout(const Duration(seconds: 60));

      if (!mounted || attempt != _attempt) return;

      if (response.statusCode != 200) {
        _fail(attempt, _messageForStatus(response.statusCode));
        return;
      }
      if (response.bodyBytes.isEmpty) {
        _fail(attempt, 'The document came back empty from the server.');
        return;
      }

      // Trust the bytes, not the file name. A Laravel error/login page served
      // with status 200 is the classic way an in-app PDF view goes blank.
      final kind = _sniff(
        response.bodyBytes,
        response.headers['content-type'] ?? '',
      );
      if (kind == _DocKind.unknown) {
        _fail(
          attempt,
          'The server did not return a viewable document. '
          'It may have been moved or removed.',
        );
        return;
      }

      final file = File(await _tempPathFor(kind));
      await file.writeAsBytes(response.bodyBytes, flush: true);

      if (!mounted || attempt != _attempt) return;
      setState(() {
        _loading = false;
        _kind = kind;
        _filePath = file.path;
      });
    } on SocketException {
      _fail(attempt, 'No internet connection. Check your network and retry.');
    } on http.ClientException {
      _fail(attempt, 'The download was interrupted. Please retry.');
    } catch (e) {
      debugPrint('DocumentViewer: failed to load ${widget.url} — $e');
      _fail(attempt, 'Could not open this document. Please retry.');
    }
  }

  /// Single funnel for every failure so no path can leave the spinner running.
  void _fail(int attempt, String message) {
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _loading = false;
      _error = message;
      _filePath = null;
    });
  }

  String _messageForStatus(int code) {
    switch (code) {
      case 401:
      case 403:
        return 'You are not allowed to view this document, or your session '
            'expired. Sign in again and retry.';
      case 404:
        return 'This document was not found on the server.';
      case 500:
      case 502:
      case 503:
        return 'The server could not serve this document right now. '
            'Please retry in a moment.';
      default:
        return 'Could not load this document (error $code).';
    }
  }

  /// Identifies the payload from its magic bytes, falling back to the
  /// Content-Type header.
  _DocKind _sniff(Uint8List bytes, String contentType) {
    bool startsWith(List<int> magic) {
      if (bytes.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith([0x25, 0x50, 0x44, 0x46])) return _DocKind.pdf; // %PDF
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return _DocKind.image; // PNG
    if (startsWith([0xFF, 0xD8, 0xFF])) return _DocKind.image; // JPEG
    if (startsWith([0x47, 0x49, 0x46, 0x38])) return _DocKind.image; // GIF
    if (startsWith([0x52, 0x49, 0x46, 0x46])) return _DocKind.image; // WEBP

    final type = contentType.toLowerCase();
    if (type.contains('pdf')) return _DocKind.pdf;
    if (type.startsWith('image/')) return _DocKind.image;
    return _DocKind.unknown;
  }

  /// Per-URL temp file name — hashing the URL keeps two documents that share a
  /// basename ("qualification.pdf") from overwriting each other.
  Future<String> _tempPathFor(_DocKind kind) async {
    final dir = await getTemporaryDirectory();
    final segments = Uri.tryParse(widget.url)?.pathSegments ?? const [];
    final base = segments.isNotEmpty && segments.last.trim().isNotEmpty
        ? segments.last.split('.').first
        : 'document';
    final safeBase = base
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .padRight(1, 'd');
    final ext = kind == _DocKind.pdf
        ? 'pdf'
        : (documentExtension(widget.url) ?? 'jpg');
    final stamp = widget.url.hashCode.toUnsigned(32).toRadixString(16);
    return '${dir.path}/doc_${stamp}_$safeBase.$ext';
  }

  Future<void> _share() async {
    final path = _filePath;
    if (path == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await Share.shareXFiles([XFile(path)], subject: widget.title);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open share sheet')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openExternally() async {
    final path = _filePath;
    if (path == null) return;
    try {
      final result = await OpenFile.open(path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'No app on this device can open the file.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file.')),
      );
    }
  }

  /// Last-resort escape hatch — hand the URL to the system browser, which
  /// carries its own session and its own PDF handling.
  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _filePath != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in another app',
            icon: Icon(
              Iconsax.export_3,
              color: ready ? Colors.white : Colors.white38,
            ),
            onPressed: ready ? _openExternally : null,
          ),
          IconButton(
            tooltip: 'Share',
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Iconsax.share,
                    color: ready ? Colors.white : Colors.white38,
                  ),
            onPressed: ready && !_sharing ? _share : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Loading document…',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    if (_error != null || _filePath == null) {
      return _errorState(_error ?? 'Could not open this document.');
    }

    if (_kind == _DocKind.pdf) {
      return PDFView(
        key: ValueKey(_filePath),
        filePath: _filePath!,
        enableSwipe: true,
        swipeHorizontal: true,
        pageSnap: true,
        pageFling: true,
        autoSpacing: true,
        fitPolicy: FitPolicy.BOTH,
        onError: (error) {
          debugPrint('DocumentViewer: PDF render error — $error');
          _fail(
            _attempt,
            'This PDF could not be displayed. It may be damaged or '
            'password-protected.',
          );
        },
        onPageError: (page, error) {
          debugPrint('DocumentViewer: PDF page $page error — $error');
        },
      ).animate().fadeIn(duration: 280.ms, curve: Curves.easeOut);
    }

    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(_filePath!),
          errorBuilder: (_, _, _) =>
              _errorState('This image could not be displayed.'),
        ),
      ),
    ).animate().fadeIn(duration: 280.ms, curve: Curves.easeOut);
  }

  /// Error state always offers a way forward: retry the download, or hand the
  /// URL to the browser.
  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.warning_2, size: 44, color: Color(0xFFF43F5E)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Iconsax.refresh, size: 16),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Iconsax.export_3, size: 16),
                  label: const Text('Open in browser'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
