import 'package:flutter/material.dart';
import '../services/admin_api_service.dart';

class ComplaintSheet extends StatefulWidget {
  final String jobId;
  final String customerName;
  final VoidCallback onDone;

  const ComplaintSheet({
    Key? key,
    required this.jobId,
    required this.customerName,
    required this.onDone,
  }) : super(key: key);

  @override
  State<ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<ComplaintSheet> {
  static const _reasons = [
    'Poor Cleaning',
    'Missed Spots',
    'Damage Reported',
    'Customer Dissatisfied',
    'Wrong Service Done',
    'Other',
  ];

  static const Color _skyBlue     = Color(0xFF38B6FF);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textMuted   = Color(0xFF64748B);
  static const Color _border      = Color(0xFFDDE8F5);
  static const Color _bg          = Color(0xFFF4F8FF);

  String? _reason;
  final _noteCtrl = TextEditingController();
  bool _saving    = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = "Please select a reason.");
      return;
    }
    setState(() { _saving = true; _error = null; });
    final result = await AdminApiService.raiseComplaint(
      jobId:  widget.jobId,
      reason: _reason!,
      note:   _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
      widget.onDone();
    } else {
      setState(() { _saving = false; _error = "Failed to raise complaint. Try again."; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 18),

          // Title
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.report_problem_rounded,
                  color: Colors.red, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Raise Complaint",
                    style: TextStyle(color: _textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(widget.customerName,
                    style: const TextStyle(color: _textMuted, fontSize: 12)),
              ],
            )),
          ]),
          const SizedBox(height: 20),

          // Reason
          const Text("Reason",
              style: TextStyle(color: _textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _reasons.map((r) {
              final selected = _reason == r;
              return GestureDetector(
                onTap: () => setState(() { _reason = r; _error = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? Colors.red : _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected
                            ? Colors.red
                            : _border),
                  ),
                  child: Text(r,
                      style: TextStyle(
                          color: selected ? Colors.white : _textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Optional note
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: const TextStyle(color: _textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Additional note (optional)",
              hintStyle: const TextStyle(color: _textMuted),
              filled: true, fillColor: _bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _skyBlue, width: 1.5)),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],

          const SizedBox(height: 18),

          // Submit button
          GestureDetector(
            onTap: (_reason == null || _saving) ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: _reason != null ? Colors.red : _border,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _reason != null ? [BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))] : [],
              ),
              child: Center(child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text("Raise Complaint",
                      style: TextStyle(
                          color: _reason != null ? Colors.white : _textMuted,
                          fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
        ],
      ),
    );
  }
}