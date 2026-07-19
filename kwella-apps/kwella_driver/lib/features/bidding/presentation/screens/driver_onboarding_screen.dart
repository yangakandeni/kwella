import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Onboarding Screen
// 5-step document upload checklist with segmented progress bar.
// ─────────────────────────────────────────────────────────────────────────────

enum _DocStatus { pending, uploaded, verified }

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final List<_Document> _docs = [
    _Document(
        icon: Icons.credit_card_rounded,
        label: "Driver's Licence",
        status: _DocStatus.verified),
    _Document(
        icon: Icons.directions_bus_rounded,
        label: 'PrDP',
        status: _DocStatus.uploaded),
    _Document(
        icon: Icons.article_rounded,
        label: 'Vehicle Registration',
        status: _DocStatus.pending),
    _Document(
        icon: Icons.local_taxi_rounded,
        label: 'CATA Sticker Photo',
        status: _DocStatus.pending),
    _Document(
        icon: Icons.camera_front_rounded,
        label: 'Selfie Verification',
        status: _DocStatus.pending),
  ];

  int get _completedSteps =>
      _docs.where((d) => d.status != _DocStatus.pending).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Get Verified',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Outfit',
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_completedSteps of ${_docs.length} completed',
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 13,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Segmented progress bar ──────────────────────────────
                  Row(
                    children: List.generate(_docs.length, (i) {
                      final done = i < _completedSteps;
                      return Expanded(
                        child: Container(
                          height: 6,
                          margin: EdgeInsets.only(right: i < _docs.length - 1 ? 4 : 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: done
                                ? const Color(0xFFDFFF00)
                                : const Color(0xFF2C2C2C),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                itemCount: _docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final doc = _docs[i];
                  return _DocCard(
                    doc: doc,
                    onUpload: doc.status == _DocStatus.pending
                        ? () => setState(() {
                              _docs[i] = _Document(
                                icon: doc.icon,
                                label: doc.label,
                                status: _DocStatus.uploaded,
                              );
                            })
                        : null,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: AnimatedOpacity(
                opacity: _completedSteps == _docs.length ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    key: const Key('submit_onboarding_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDFFF00),
                      foregroundColor: const Color(0xFF1A1A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _completedSteps == _docs.length
                        ? () => Navigator.pop(context)
                        : null,
                    child: const Text(
                      'Submit for Review',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _Document {
  const _Document(
      {required this.icon, required this.label, required this.status});
  final IconData icon;
  final String label;
  final _DocStatus status;
}

// ── Card widget ───────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.onUpload});
  final _Document doc;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusLabel;
    switch (doc.status) {
      case _DocStatus.verified:
        statusColor = const Color(0xFF00C853);
        statusLabel = 'Verified ✓';
        break;
      case _DocStatus.uploaded:
        statusColor = const Color(0xFFFFAB40);
        statusLabel = 'Under Review';
        break;
      case _DocStatus.pending:
        statusColor = const Color(0xFF606060);
        statusLabel = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: doc.status == _DocStatus.verified
              ? const Color(0x3000C853)
              : const Color(0xFF2C2C2C),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(doc.icon,
                color: doc.status == _DocStatus.verified
                    ? const Color(0xFFDFFF00)
                    : const Color(0xFFA0A0A0),
                size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onUpload != null)
            TextButton(
              onPressed: onUpload,
              child: const Text(
                'Upload',
                style: TextStyle(
                  color: Color(0xFFDFFF00),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
