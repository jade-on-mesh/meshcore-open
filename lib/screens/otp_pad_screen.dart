import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import '../models/otp_pad.dart';
import '../services/otp_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/qr_code_display.dart';
import '../widgets/qr_scanner_widget.dart';

/// Pad management screen for a contact or a channel — import via paste or
/// QR scan, pick A/B role, see live consumption, replace or clear.
///
/// Use [OtpPadScreen.forContact] or [OtpPadScreen.forChannel]; exactly one
/// of the two is ever set.
class OtpPadScreen extends StatefulWidget {
  final Contact? contact;
  final Channel? channel;

  const OtpPadScreen.forContact(Contact contact, {super.key})
    : contact = contact,
      channel = null;

  const OtpPadScreen.forChannel(Channel channel, {super.key})
    : contact = null,
      channel = channel;

  @override
  State<OtpPadScreen> createState() => _OtpPadScreenState();
}

class _OtpPadScreenState extends State<OtpPadScreen> {
  final _pasteController = TextEditingController();
  final _labelController = TextEditingController();
  OtpPadRole _selectedRole = OtpPadRole.a;
  int _generateBytes = 2048;
  bool _busy = false;
  String? _formError;

  bool get _isChannel => widget.channel != null;

  String get _targetName {
    if (widget.contact != null) return widget.contact!.name;
    final channel = widget.channel!;
    return channel.name.isEmpty ? 'Channel ${channel.index}' : channel.name;
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  OtpPad? _currentPad(MeshCoreConnector connector) => _isChannel
      ? connector.getChannelOtpPad(widget.channel!.index)
      : connector.getContactOtpPad(widget.contact!.publicKeyHex);

  int _maxPlaintextPerMessage(MeshCoreConnector connector) => _isChannel
      ? OtpService.maxPlaintextBytesForChannel(connector.selfName)
      : OtpService.maxPlaintextBytesForContact();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle('OTP Pad — $_targetName'),
        centerTitle: true,
      ),
      body: Consumer<MeshCoreConnector>(
        builder: (context, connector, _) {
          final pad = _currentPad(connector);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _buildHeroCard(context, connector, pad),
              if (pad != null) ...[
                const SectionHeader('Pad usage'),
                _buildUsageCard(context, connector, pad),
                const SectionHeader('Manage'),
                _buildManageCard(context, connector, pad),
              ] else ...[
                const SectionHeader('Set up encryption'),
                _buildSetupCard(context, connector),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Hero status card ────────────────────────────────────────────────

  Widget _buildHeroCard(
    BuildContext context,
    MeshCoreConnector connector,
    OtpPad? pad,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = pad?.enabled ?? false;
    final exhausted = pad?.isExhausted ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MeshRadii.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled && !exhausted
                ? [MeshPalette.blueDim, MeshPalette.blue]
                : [scheme.surfaceContainerHigh, scheme.surfaceContainerHigh],
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.18 : 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                enabled
                    ? (exhausted ? Icons.lock_clock : Icons.lock)
                    : Icons.lock_open,
                color: enabled ? Colors.white : scheme.onSurfaceVariant,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One-Time-Pad Encryption',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: enabled ? Colors.white : scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pad == null
                        ? 'No pad set up for this ${_isChannel ? 'channel' : 'contact'} yet'
                        : exhausted
                        ? 'Pad exhausted — replace it to keep messaging'
                        : enabled
                        ? 'Messages are being encrypted with this pad'
                        : 'Pad is loaded but encryption is turned off',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? Colors.white.withValues(alpha: 0.85)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (pad != null)
              Switch(
                value: enabled,
                onChanged: exhausted
                    ? null
                    : (value) => _setEnabled(connector, value),
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.white.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }

  // ── Usage card ───────────────────────────────────────────────────────

  Widget _buildUsageCard(
    BuildContext context,
    MeshCoreConnector connector,
    OtpPad pad,
  ) {
    final maxPerMsg = _maxPlaintextPerMessage(connector).clamp(1, 1 << 30);
    return MeshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                label: 'Role ${pad.role.label}',
                icon: Icons.badge_outlined,
                color: MeshPalette.blue,
              ),
              const Spacer(),
              Text(
                '${pad.totalBytes} bytes total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (pad.label != null && pad.label!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              pad.label!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 18),
          _usageRow(
            context,
            label: 'Your messages',
            usedFraction: pad.myUsageFraction,
            remainingBytes: pad.myBytesRemaining,
            color: MeshPalette.blue,
            approxMessages: (pad.myBytesRemaining / maxPerMsg).floor(),
          ),
          const SizedBox(height: 14),
          _usageRow(
            context,
            label: 'Their messages',
            usedFraction: pad.theirUsageFraction,
            remainingBytes: pad.theirBytesRemaining,
            color: MeshPalette.magenta,
            approxMessages: (pad.theirBytesRemaining / maxPerMsg).floor(),
          ),
          if (pad.myUsageFraction > 0.85 || pad.theirUsageFraction > 0.85) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MeshPalette.warnBg,
                borderRadius: BorderRadius.circular(MeshRadii.sm),
                border: Border.all(color: MeshPalette.warnLine),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: MeshPalette.warn,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pad.isExhausted
                          ? 'This pad is used up. Import a new one to keep sending encrypted messages.'
                          : 'Running low on pad — plan to exchange a fresh one soon.',
                      style: const TextStyle(
                        color: MeshPalette.warn,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _usageRow(
    BuildContext context, {
    required String label,
    required double usedFraction,
    required int remainingBytes,
    required Color color,
    required int approxMessages,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '$remainingBytes B left · ~$approxMessages msgs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(MeshRadii.pill),
          child: LinearProgressIndicator(
            value: usedFraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              usedFraction > 0.85 ? MeshPalette.warn : color,
            ),
          ),
        ),
      ],
    );
  }

  // ── Manage card (pad exists) ────────────────────────────────────────

  Widget _buildManageCard(
    BuildContext context,
    MeshCoreConnector connector,
    OtpPad pad,
  ) {
    return MeshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Show pad as QR'),
            subtitle: const Text(
              'Let the other device scan this exact pad — only do this once, privately',
            ),
            onTap: () => _showPadQr(pad),
          ),
          const Divider(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh, color: MeshPalette.warn),
            title: const Text('Replace pad'),
            subtitle: const Text('Import fresh pad material for this target'),
            onTap: () => setState(() {
              _pasteController.clear();
              _labelController.clear();
              _formError = null;
              // Re-render into setup mode by clearing the pad first is
              // destructive, so route through the same confirm+clear flow,
              // then the screen naturally falls into the setup card.
              _confirmAndClear(connector, andThenSetup: true);
            }),
          ),
          const Divider(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: MeshPalette.alert),
            title: const Text('Clear pad'),
            subtitle: const Text('Turns off OTP and forgets this pad'),
            onTap: () => _confirmAndClear(connector),
          ),
        ],
      ),
    );
  }

  // ── Setup card (no pad yet) ─────────────────────────────────────────

  Widget _buildSetupCard(BuildContext context, MeshCoreConnector connector) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Who are you in this pad?',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Agree with the other person beforehand — one of you is A, '
                'the other is B. Getting it backwards just means messages '
                "won't decrypt; nothing is silently reused.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<OtpPadRole>(
                segments: const [
                  ButtonSegment(
                    value: OtpPadRole.a,
                    label: Text('I am Party A'),
                    icon: Icon(Icons.looks_one_outlined),
                  ),
                  ButtonSegment(
                    value: OtpPadRole.b,
                    label: Text('I am Party B'),
                    icon: Icon(Icons.looks_two_outlined),
                  ),
                ],
                selected: {_selectedRole},
                onSelectionChanged: (selection) =>
                    setState(() => _selectedRole = selection.first),
              ),
            ],
          ),
        ),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pad material',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pasteController,
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Hex pad data (paste, scan, or generate below)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MeshRadii.sm),
                  ),
                  errorText: _formError,
                ),
                onChanged: (_) {
                  if (_formError != null) setState(() => _formError = null);
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.paste, size: 18),
                    label: const Text('Paste'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _scanQr,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan QR'),
                  ),
                ],
              ),
              const Divider(height: 28),
              Text(
                "Don't have a pad yet? Generate one here",
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Uses this device\'s secure random generator. Generate on '
                'one device, then have the other person scan or paste the '
                'exact same pad from here — never generate it twice.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _generateBytes,
                      decoration: InputDecoration(
                        labelText: 'Pad size',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MeshRadii.sm),
                        ),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 512, child: Text('512 B')),
                        DropdownMenuItem(value: 2048, child: Text('2 KB')),
                        DropdownMenuItem(value: 8192, child: Text('8 KB')),
                        DropdownMenuItem(value: 32768, child: Text('32 KB')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _generateBytes = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _generatePad,
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: const Text('Generate'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '~${(_generateBytes / 2 / max(1, _maxPlaintextPerMessage(connector))).floor()} '
                  'messages per side at this size',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. "Camp trip pad"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MeshRadii.sm),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _importPad(connector),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: const Text('Enable OTP with this pad'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _pasteController.text = text;
      _formError = null;
    });
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _OtpPadQrScanScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _pasteController.text = result;
        _formError = null;
      });
    }
  }

  void _generatePad() {
    final random = Random.secure();
    final bytes = List<int>.generate(_generateBytes, (_) => random.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    setState(() {
      _pasteController.text = hex;
      _formError = null;
    });
  }

  String? _normalizeHex(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    if (cleaned.length % 2 != 0) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) return null;
    return cleaned.toLowerCase();
  }

  Future<void> _importPad(MeshCoreConnector connector) async {
    final hex = _normalizeHex(_pasteController.text);
    if (hex == null) {
      setState(
        () => _formError =
            'Enter valid hex pad data (paste, scan, or generate one above)',
      );
      return;
    }
    if (hex.length < 8) {
      setState(() => _formError = 'Pad is too short to be useful');
      return;
    }
    setState(() => _busy = true);
    final label = _labelController.text.trim();
    if (_isChannel) {
      await connector.setChannelOtpPad(
        widget.channel!.index,
        hex,
        _selectedRole,
        label: label.isEmpty ? null : label,
      );
    } else {
      await connector.setContactOtpPad(
        widget.contact!.publicKeyHex,
        hex,
        _selectedRole,
        label: label.isEmpty ? null : label,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP pad imported and enabled')),
    );
  }

  Future<void> _setEnabled(MeshCoreConnector connector, bool value) async {
    if (_isChannel) {
      await connector.setChannelOtpEnabled(widget.channel!.index, value);
    } else {
      await connector.setContactOtpEnabled(widget.contact!.publicKeyHex, value);
    }
  }

  void _showPadQr(OtpPad pad) {
    QrCodeShareDialog.show(
      context: context,
      data: pad.padHex,
      title: 'Scan on the other device',
      instructions:
          'This shows the raw pad in plain sight — make sure no one else '
          'can see your screen while the other device scans it. The other '
          'person must pick the opposite role (${pad.role == OtpPadRole.a ? 'B' : 'A'}) '
          'when they import it.',
    );
  }

  Future<void> _confirmAndClear(
    MeshCoreConnector connector, {
    bool andThenSetup = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this pad?'),
        content: Text(
          andThenSetup
              ? "This forgets the current pad so you can import a new one. "
                    "Any unused bytes in the old pad are discarded — that's fine, "
                    "they were never reused anywhere else."
              : 'This turns off OTP for this ${_isChannel ? 'channel' : 'contact'} '
                    'and forgets the pad. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(andThenSetup ? 'Clear & replace' : 'Clear pad'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_isChannel) {
      await connector.clearChannelOtpPad(widget.channel!.index);
    } else {
      await connector.clearContactOtpPad(widget.contact!.publicKeyHex);
    }
  }
}

/// Thin wrapper around the app's existing [QrScannerWidget] that validates
/// scanned data looks like pad hex before returning it.
class _OtpPadQrScanScreen extends StatelessWidget {
  const _OtpPadQrScanScreen();

  bool _looksLikeHex(String data) {
    final cleaned = data.trim();
    return cleaned.length >= 8 &&
        cleaned.length % 2 == 0 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AdaptiveAppBarTitle('Scan OTP Pad'),
        centerTitle: true,
      ),
      body: QrScannerWidget(
        onScanned: (data) => Navigator.of(context).pop(data.trim()),
        validator: _looksLikeHex,
        onValidationFailed: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That QR code doesn\'t look like pad data'),
            ),
          );
        },
        instructions: 'Point the camera at the pad QR shown on the other device',
      ),
    );
  }
}
