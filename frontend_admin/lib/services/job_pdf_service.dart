// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:share_plus/share_plus.dart';
// import 'package:http/http.dart' as http;
// import 'dart:io';
// import 'package:path_provider/path_provider.dart';

// class JobPdfService {
//   static Future<void> generateAndShare({
//     required Map<String, dynamic> job,
//     required Map<String, dynamic> customer,
//   }) async {
//     try {
//       final pdfBytes = await _buildPdf(job: job, customer: customer);
//       final fileName = _buildFileName(job);
//       await _sharePdf(pdfBytes, fileName);
//     } catch (e) {
//       print('[PDF] Error: $e');
//       rethrow;
//     }
//   }

//   static String _buildFileName(Map<String, dynamic> job) {
//     final jobCount      = job['serviceCount']      ?? 0;
//     final customerCount = job['customerId'] is Map
//         ? (job['customerId']['serviceCount'] ?? 0)
//         : 0;
//     final count    = jobCount > 0 ? jobCount : customerCount;
//     final countStr = count.toString().padLeft(2, '0');
//     final dateStr  = job['assignedDate'] ?? '';
//     String formattedDate = '';
//     if (dateStr.isNotEmpty) {
//       try {
//         final d = DateTime.parse(dateStr);
//         const months = ['JAN','FEB','MAR','APR','MAY','JUN',
//                         'JUL','AUG','SEP','OCT','NOV','DEC'];
//         final day   = d.day.toString().padLeft(2, '0');
//         final month = months[d.month - 1];
//         final year  = d.year.toString();
//         formattedDate = '$day $month $year';
//       } catch (_) {
//         formattedDate = dateStr;
//       }
//     }
//     return '#$countStr - $formattedDate.pdf';
//   }

//   static Future<Uint8List> _buildPdf({
//     required Map<String, dynamic> job,
//     required Map<String, dynamic> customer,
//   }) async {
//     final pdf = pw.Document();

//     const skyBlue   = PdfColor.fromInt(0xFF38B6FF);
//     const skyDark   = PdfColor.fromInt(0xFF1A90D9);
//     const bgColor   = PdfColor.fromInt(0xFFF4F8FF);
//     const textDark  = PdfColor.fromInt(0xFF0F172A);
//     const textMuted = PdfColor.fromInt(0xFF64748B);
//     const white     = PdfColors.white;
//     const border    = PdfColor.fromInt(0xFFDDE8F5);

//     final jobCount      = job['serviceCount'] ?? 0;
//     final customerCount = customer['serviceCount'] ?? 0;
//     final serviceCount  = jobCount > 0 ? jobCount : customerCount;
//     final serviceType   = job['serviceType']  ?? '';
//     final assignedDate  = job['assignedDate'] ?? '';
//     final images        = job['images'] as Map<String, dynamic>?;
//     final beforeUrl     = images?['before'] as String?;
//     final afterList     = (images?['after'] as List?) ?? [];

//     String? frontAngleUrl;
//     for (final item in afterList) {
//       if (item is Map) {
//         final label = (item['label'] ?? '').toString().toLowerCase();
//         if (label.contains('front')) {
//           frontAngleUrl = item['url']?.toString();
//           break;
//         }
//       }
//     }
//     if (frontAngleUrl == null && afterList.isNotEmpty) {
//       final first = afterList[0];
//       if (first is Map) frontAngleUrl = first['url']?.toString();
//     }

//     String displayDate = assignedDate;
//     try {
//       final d = DateTime.parse(assignedDate);
//       const months = ['January','February','March','April','May','June',
//                       'July','August','September','October','November','December'];
//       displayDate = '${d.day} ${months[d.month - 1]} ${d.year}';
//     } catch (_) {}

//     // Download + compress images
//     pw.ImageProvider? beforeImage;
//     pw.ImageProvider? frontImage;
//     if (beforeUrl != null && beforeUrl.isNotEmpty) {
//       beforeImage = await _downloadImage(beforeUrl);
//     }
//     if (frontAngleUrl != null && frontAngleUrl.isNotEmpty) {
//       frontImage = await _downloadImage(frontAngleUrl);
//     }

//     pdf.addPage(
//       pw.MultiPage(
//         pageFormat: PdfPageFormat.a4,
//         margin: pw.EdgeInsets.zero,
//         header: (ctx) => pw.Container(
//           width: double.infinity,
//           padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 20),
//           color: skyBlue,
//           child: pw.Row(
//             mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//             children: [
//               pw.Column(
//                 crossAxisAlignment: pw.CrossAxisAlignment.start,
//                 children: [
//                   pw.Text('LAUNDOOR',
//                       style: pw.TextStyle(color: PdfColors.white,
//                           fontSize: 22, fontWeight: pw.FontWeight.bold,
//                           letterSpacing: 2)),
//                   pw.Text('Car Wash Service Report',
//                       style: const pw.TextStyle(
//                           color: PdfColors.white, fontSize: 11)),
//                 ],
//               ),
//               pw.Container(
//                 padding: const pw.EdgeInsets.symmetric(
//                     horizontal: 16, vertical: 8),
//                 decoration: pw.BoxDecoration(
//                   color: PdfColors.white,
//                   borderRadius: const pw.BorderRadius.all(
//                       pw.Radius.circular(8)),
//                 ),
//                 child: pw.Column(
//                   crossAxisAlignment: pw.CrossAxisAlignment.center,
//                   children: [
//                     pw.Text(
//                       '#${serviceCount.toString().padLeft(2, '0')}',
//                       style: pw.TextStyle(color: skyBlue, fontSize: 20,
//                           fontWeight: pw.FontWeight.bold),
//                     ),
//                     pw.Text('Service Count',
//                         style: const pw.TextStyle(
//                             color: textMuted, fontSize: 9)),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//         build: (ctx) => [
//           pw.Container(
//             color: bgColor,
//             padding: const pw.EdgeInsets.all(24),
//             child: pw.Column(
//               crossAxisAlignment: pw.CrossAxisAlignment.start,
//               children: [
//                 // Customer card
//                 pw.Container(
//                   width: double.infinity,
//                   padding: const pw.EdgeInsets.all(16),
//                   decoration: pw.BoxDecoration(
//                     color: PdfColors.white,
//                     borderRadius: const pw.BorderRadius.all(
//                         pw.Radius.circular(12)),
//                     border: pw.Border.all(color: border),
//                   ),
//                   child: pw.Column(
//                     crossAxisAlignment: pw.CrossAxisAlignment.start,
//                     children: [
//                       pw.Row(
//                         mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                         children: [
//                           pw.Text(customer['customerName'] ?? '',
//                               style: pw.TextStyle(color: textDark,
//                                   fontSize: 16, fontWeight: pw.FontWeight.bold)),
//                           pw.Container(
//                             padding: const pw.EdgeInsets.symmetric(
//                                 horizontal: 10, vertical: 4),
//                             decoration: pw.BoxDecoration(
//                               color: PdfColor.fromInt(0xFFE8F5FF),
//                               borderRadius: const pw.BorderRadius.all(
//                                   pw.Radius.circular(6)),
//                             ),
//                             child: pw.Text(customer['carType'] ?? '',
//                                 style: pw.TextStyle(color: skyDark,
//                                     fontSize: 10, fontWeight: pw.FontWeight.bold)),
//                           ),
//                         ],
//                       ),
//                       pw.SizedBox(height: 10),
//                       pw.Divider(color: border, thickness: 0.5),
//                       pw.SizedBox(height: 8),
//                       _infoRow('Vehicle',  customer['carModel'] ?? '',      textMuted, textDark),
//                       pw.SizedBox(height: 5),
//                       _infoRow('Reg No',   customer['vehicleNumber'] ?? '', textMuted, textDark),
//                       pw.SizedBox(height: 5),
//                       _infoRow('Color',    customer['vehicleColor'] ?? '',  textMuted, textDark),
//                       pw.SizedBox(height: 5),
//                       _infoRow('Address',  customer['address'] ?? '',       textMuted, textDark),
//                     ],
//                   ),
//                 ),

//                 pw.SizedBox(height: 14),

//                 // Service + date row
//                 pw.Row(children: [
//                   pw.Expanded(
//                     child: pw.Container(
//                       padding: const pw.EdgeInsets.all(12),
//                       decoration: pw.BoxDecoration(
//                         color: PdfColor.fromInt(0xFFE8F5FF),
//                         borderRadius: const pw.BorderRadius.all(
//                             pw.Radius.circular(10)),
//                       ),
//                       child: pw.Column(
//                         crossAxisAlignment: pw.CrossAxisAlignment.start,
//                         children: [
//                           pw.Text('Service Type',
//                               style: const pw.TextStyle(
//                                   color: textMuted, fontSize: 9)),
//                           pw.SizedBox(height: 3),
//                           pw.Text(serviceType,
//                               style: pw.TextStyle(color: skyDark,
//                                   fontSize: 13, fontWeight: pw.FontWeight.bold)),
//                         ],
//                       ),
//                     ),
//                   ),
//                   pw.SizedBox(width: 12),
//                   pw.Expanded(
//                     child: pw.Container(
//                       padding: const pw.EdgeInsets.all(12),
//                       decoration: pw.BoxDecoration(
//                         color: PdfColors.white,
//                         borderRadius: const pw.BorderRadius.all(
//                             pw.Radius.circular(10)),
//                         border: pw.Border.all(color: border),
//                       ),
//                       child: pw.Column(
//                         crossAxisAlignment: pw.CrossAxisAlignment.start,
//                         children: [
//                           pw.Text('Date of Service',
//                               style: const pw.TextStyle(
//                                   color: textMuted, fontSize: 9)),
//                           pw.SizedBox(height: 3),
//                           pw.Text(displayDate,
//                               style: pw.TextStyle(color: textDark,
//                                   fontSize: 12, fontWeight: pw.FontWeight.bold)),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ]),

//                 pw.SizedBox(height: 18),

//                 // Before photo
//                 if (beforeImage != null) ...[
//                   pw.Text('BEFORE',
//                       style: pw.TextStyle(color: textMuted, fontSize: 9,
//                           fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
//                   pw.SizedBox(height: 8),
//                   pw.Image(beforeImage, fit: pw.BoxFit.contain),
//                   pw.SizedBox(height: 16),
//                 ],

//                 // After front angle
//                 if (frontImage != null) ...[
//                   pw.Text('AFTER - FRONT ANGLE',
//                       style: pw.TextStyle(color: textMuted, fontSize: 9,
//                           fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
//                   pw.SizedBox(height: 8),
//                   pw.Image(frontImage, fit: pw.BoxFit.contain),
//                 ],

//                 pw.SizedBox(height: 20),

//                 // Footer
//                 pw.Divider(color: border, thickness: 0.5),
//                 pw.SizedBox(height: 6),
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text('Generated by Laundoor',
//                         style: const pw.TextStyle(color: textMuted, fontSize: 9)),
//                     pw.Text(displayDate,
//                         style: const pw.TextStyle(color: textMuted, fontSize: 9)),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );

//     return pdf.save();
//   }

//   static pw.Widget _infoRow(String label, String value,
//       PdfColor labelColor, PdfColor valueColor) {
//     return pw.Row(
//       crossAxisAlignment: pw.CrossAxisAlignment.start,
//       children: [
//         pw.SizedBox(
//           width: 70,
//           child: pw.Text(label,
//               style: pw.TextStyle(color: labelColor, fontSize: 10)),
//         ),
//         pw.Text(': ', style: pw.TextStyle(color: labelColor, fontSize: 10)),
//         pw.Expanded(
//           child: pw.Text(value,
//               style: pw.TextStyle(color: valueColor,
//                   fontSize: 10, fontWeight: pw.FontWeight.bold)),
//         ),
//       ],
//     );
//   }

//   // Download and compress image to max 800px wide
//   static Future<pw.ImageProvider?> _downloadImage(String url) async {
//     try {
//       final response = await http.get(Uri.parse(url))
//           .timeout(const Duration(seconds: 20));
//       if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
//         final compressed = await _compressBytes(response.bodyBytes);
//         return pw.MemoryImage(compressed);
//       }
//     } catch (e) {
//       print('[PDF] Download failed: $url - $e');
//     }
//     return null;
//   }

//   // Resize to max 800px using dart:ui - no extra package needed
//   static Future<Uint8List> _compressBytes(Uint8List bytes) async {
//     try {
//       final codec = await ui.instantiateImageCodec(
//         bytes,
//         targetWidth: 800,
//       );
//       final frame    = await codec.getNextFrame();
//       final byteData = await frame.image.toByteData(
//           format: ui.ImageByteFormat.png);
//       frame.image.dispose();
//       if (byteData != null) {
//         return byteData.buffer.asUint8List();
//       }
//     } catch (e) {
//       print('[PDF] Compress failed, using original: $e');
//     }
//     return bytes;
//   }

//   static Future<void> _sharePdf(Uint8List bytes, String fileName) async {
//     final dir  = await getTemporaryDirectory();
//     final file = File('${dir.path}/$fileName');
//     await file.writeAsBytes(bytes);
//     await Share.shareXFiles(
//       [XFile(file.path, mimeType: 'application/pdf')],
//       subject: fileName.replaceAll('.pdf', ''),
//       text:    'Car wash service report from Laundoor',
//     );
//     Future.delayed(const Duration(minutes: 2), () {
//       if (file.existsSync()) file.deleteSync();
//     });
//   }
// }