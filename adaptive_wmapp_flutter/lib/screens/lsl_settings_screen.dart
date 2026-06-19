import 'package:flutter/material.dart';
import '../models/lsl_config.dart';

/// Editable settings panel for LSL EEG stream discovery.
/// Returns the updated [LslConfig] via [Navigator.pop] when saved.
class LslSettingsScreen extends StatefulWidget {
  final LslConfig initial;
  const LslSettingsScreen({super.key, required this.initial});

  @override
  State<LslSettingsScreen> createState() => _LslSettingsScreenState();
}

class _LslSettingsScreenState extends State<LslSettingsScreen> {
  late final TextEditingController _eegTypeCtr;
  late final TextEditingController _eegNameCtr;
  late final TextEditingController _eegPeersCtr;
  late final TextEditingController _timeoutCtr;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _eegTypeCtr = TextEditingController(text: c.eegStreamType);
    _eegNameCtr = TextEditingController(text: c.eegStreamName);
    _eegPeersCtr = TextEditingController(text: c.eegKnownPeers.join(', '));
    _timeoutCtr =
        TextEditingController(text: c.resolveTimeoutSeconds.toString());
  }

  @override
  void dispose() {
    _eegTypeCtr.dispose();
    _eegNameCtr.dispose();
    _eegPeersCtr.dispose();
    _timeoutCtr.dispose();
    super.dispose();
  }

  List<String> _splitPeers(String raw) => raw
      .split(RegExp(r'[,;\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _save() {
    final config = LslConfig(
      eegStreamType: _eegTypeCtr.text.trim().isEmpty
          ? 'EEG'
          : _eegTypeCtr.text.trim(),
      eegStreamName: _eegNameCtr.text.trim(),
      eegKnownPeers: _splitPeers(_eegPeersCtr.text),
      resolveTimeoutSeconds:
          double.tryParse(_timeoutCtr.text) ?? 5.0,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        title: const Text(
          'LSL Stream Settings',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, color: Color(0xFF14B8A6)),
            label: const Text(
              'Save',
              style: TextStyle(color: Color(0xFF14B8A6)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
                'EEG LSL Source', Icons.bolt, const Color(0xFF14B8A6)),
            const SizedBox(height: 12),
            _field(_eegTypeCtr, 'Stream Type',
                hint: 'EEG (default)',
                helper:
                    'LSL stream type. Also tries "EEG" as fallback.'),
            const SizedBox(height: 12),
            _field(_eegNameCtr, 'Stream Name (optional)',
                hint: 'Leave empty to match any EEG stream',
                helper:
                    'Partial name match. E.g. "LiveAmp" or "OpenBCI"'),
            const SizedBox(height: 12),
            _field(_eegPeersCtr, 'Known Peer IPs (optional)',
                hint: '192.168.1.100, 192.168.1.101',
                helper:
                    'Comma-separated IPs for direct LSL resolution over WiFi'),
            const SizedBox(height: 30),
            _sectionHeader(
                'Resolution', Icons.timer_outlined, Colors.orange),
            const SizedBox(height: 12),
            _field(_timeoutCtr, 'Resolve Timeout (seconds)',
                hint: '5.0',
                keyboardType: TextInputType.number,
                helper:
                    'How long to wait for LSL stream resolution. 5s recommended.'),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2333),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'About LSL Discovery',
                      style: TextStyle(
                          color: Colors.amber, fontWeight: FontWeight.bold),
                    ),
                  ]),
                  SizedBox(height: 8),
                  Text(
                    'LSL streams are discovered automatically over the local '
                    'network (WiFi).\n\n'
                    '• For LiveAmp / OpenBCI: ensure liblsl is installed and '
                    'broadcasting.\n'
                    '• Android requires both devices to be on the same WiFi '
                    'subnet.\n'
                    '• If auto-discovery fails, enter the server\'s IP in '
                    '"Known Peer IPs".',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctr,
    String label, {
    String hint = '',
    String helper = '',
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctr,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white30),
        helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF1C2333),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF14B8A6)),
        ),
      ),
    );
  }
}
