import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class JobShareService {

  // ── Photo label constants ────────────────────────────────────────────────
  static const String _exteriorAfterLabel  = 'Front Angle';
  static const String _interiorBeforeLabel = 'Driver mat';
  static const String _interiorAfterLabel  = 'Driver mat';

  // Find a photo URL by exact label match from a list
  static String? _findByLabel(List items, String label) {
    for (final item in items) {
      if (item is Map &&
          (item['label'] ?? '').toString() == label &&
          item['url'] != null &&
          item['url'].toString().isNotEmpty) {
        return item['url'].toString();
      }
    }
    return null;
  }

  // Fallback: first non-empty URL in list
  static String? _firstUrl(List items) {
    for (final item in items) {
      if (item is Map &&
          item['url'] != null &&
          item['url'].toString().isNotEmpty) {
        return item['url'].toString();
      }
    }
    return null;
  }

  static Future<void> shareJobPhotos({
    required Map<String, dynamic> job,
    required Map<String, dynamic>? customer,
  }) async {
    final status       = job['status'] ?? '';
    final cancelPhoto  = job['cancelPhotoUrl'] as String?;
    final cancelReason = job['cancelReason']   as String?;
    final cancelledAt  = job['cancelledAt']    as String?;

    // ── CANCELLED JOB SHARE ─────────────────────────────────────────────
    if (status == 'Cancelled') {
      if (cancelPhoto == null || cancelPhoto.isEmpty) {
        throw Exception("No cancellation photo available");
      }
      final dir   = await getTemporaryDirectory();
      final files = <XFile>[];
      final bytes = await _download(cancelPhoto);
      if (bytes != null) {
        final f = File('${dir.path}/cancel_${job['_id']}.jpg');
        await f.writeAsBytes(bytes);
        files.add(XFile(f.path, mimeType: 'image/jpeg'));
      }
      if (files.isEmpty) throw Exception("Could not download cancel photo");
      final cancelTime = _formatDateTime(cancelledAt);
      final reason     = (cancelReason != null && cancelReason.isNotEmpty)
          ? cancelReason : 'No reason provided';
      await Share.shareXFiles(files,
          text: 'Cancelled ❌\n$cancelTime\nReason: $reason');
      _cleanupLater(files);
      return;
    }

    // ── COMPLETED JOB SHARE ─────────────────────────────────────────────
    final images         = job['images'] as Map<String, dynamic>?;
    final serviceType    = job['serviceType']?.toString() ?? '';
    final isInterior     = serviceType == 'Interior Standard' ||
                           serviceType == 'Interior Premium';
    final interiorBefore = (images?['interiorBefore'] as List?) ?? [];
    final interiorAfter  = (images?['interiorAfter']  as List?) ?? [];
    final afterList      = (images?['after']          as List?) ?? [];

    // Resolve before URL
    String? beforeUrl;
    if (isInterior) {
      beforeUrl = _findByLabel(interiorBefore, _interiorBeforeLabel)
                ?? _firstUrl(interiorBefore);
    } else {
      beforeUrl = images?['before'] as String?;
    }

    // Resolve after URL
    String? afterUrl;
    if (isInterior) {
      afterUrl = _findByLabel(interiorAfter, _interiorAfterLabel)
               ?? (interiorAfter.isNotEmpty
                   ? interiorAfter.last['url']?.toString() : null);
    } else {
      afterUrl = _findByLabel(afterList, _exteriorAfterLabel)
               ?? _firstUrl(afterList);
    }

    if (beforeUrl == null || beforeUrl.isEmpty) {
      throw Exception("Before photo not available");
    }

    final count        = job['serviceCount'] ?? 0;
    final countStr     = '#${count.toString().padLeft(2, '0')}';
    final beforeTime   = _formatDateTime(job['beforeUploadedAt'] ?? job['updatedAt']);
    final afterTime    = _formatDateTime(job['completedAt']      ?? job['updatedAt']);
    final beforeCaption = 'Before\n$beforeTime';
    final afterCaption  = 'After $countStr\n$afterTime';

    final dir   = await getTemporaryDirectory();
    final files = <XFile>[];

    final beforeBytes = await _download(beforeUrl);
    if (beforeBytes != null) {
      final f = File('${dir.path}/before_${job['_id']}.jpg');
      await f.writeAsBytes(beforeBytes);
      files.add(XFile(f.path, mimeType: 'image/jpeg'));
    }

    if (afterUrl != null) {
      final afterBytes = await _download(afterUrl);
      if (afterBytes != null) {
        final f = File('${dir.path}/after_${job['_id']}.jpg');
        await f.writeAsBytes(afterBytes);
        files.add(XFile(f.path, mimeType: 'image/jpeg'));
      }
    }

    if (files.isEmpty) throw Exception("Could not download photos");
    await Share.shareXFiles(files, text: '$beforeCaption\n\n$afterCaption');
    _cleanupLater(files);
  }

  static void _cleanupLater(List<XFile> files) {
    Future.delayed(const Duration(minutes: 2), () {
      for (final f in files) {
        final file = File(f.path);
        if (file.existsSync()) file.deleteSync();
      }
    });
  }

  static Future<Uint8List?> _download(String url) async {
    try {
      final res = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (e) { print('[Share] Download failed: $url - $e'); }
    return null;
  }

  static String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final day = d.day.toString().padLeft(2, '0');
      final mon = months[d.month - 1];
      final h   = d.hour > 12 ? d.hour - 12 : d.hour == 0 ? 12 : d.hour;
      final m   = d.minute.toString().padLeft(2, '0');
      final ap  = d.hour >= 12 ? 'PM' : 'AM';
      return '$day $mon ${d.year}, $h:$m $ap';
    } catch (_) { return ''; }
  }
}