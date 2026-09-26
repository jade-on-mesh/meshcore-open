import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../models/companion_radio_stats.dart';
import 'radio_stats_entry.dart' show pushCompanionRadioStatsScreen;

/// Coarse RSSI-margin signal-quality grade ("excellent"/"good"/"fair"/
/// "poor"/"very poor"/"no data"), ported back by request to match the
/// grading the Lua apps use (OTP_2_RC16.lua's rssi_grade/sig_grade_for_
/// margin, carried into OTP_3_RC1.lua's signal_tick) - the same five
/// margin thresholds and the same fixed, theme-independent traffic-
/// light colors, so "good" means the same thing and looks the same
/// regardless of which app someone's looking at.
///
/// Margin here is simply the companion radio's own last-received-
/// packet RSSI minus its noise floor (CompanionRadioStats, from the
/// STATS_TYPE_RADIO frame) - "how well is my own radio hearing
/// anything right now." This is deliberately a different metric from
/// the existing SNRIndicator already in this app's app bar, which
/// grades SNR to one specific known direct repeater (a path-specific
/// signal, not a general one) - the two aren't meant to replace each
/// other, they answer different questions.
const int sigRed = 0xFFE74C3C;
const int sigOrange = 0xFFE67E22;
const int sigYellow = 0xFFF1C40F;
const int sigGreen = 0xFF2ECC71;
const int sigGreenBright = 0xFF39FF14;

class SignalGrade {
  final String label;
  final Color color;
  const SignalGrade(this.label, this.color);
}

SignalGrade signalGradeForStats(CompanionRadioStats? stats) {
  if (stats == null) {
    return const SignalGrade('no data', Color(sigRed));
  }
  final margin = stats.lastRssiDbm - stats.noiseFloorDbm;
  if (margin >= 20) return const SignalGrade('excellent', Color(sigGreenBright));
  if (margin >= 12) return const SignalGrade('good', Color(sigGreen));
  if (margin >= 6) return const SignalGrade('fair', Color(sigYellow));
  if (margin >= 0) return const SignalGrade('poor', Color(sigOrange));
  return const SignalGrade('very poor', Color(sigRed));
}

IconData iconForSignalGrade(String label) {
  switch (label) {
    case 'excellent':
      return Icons.signal_cellular_4_bar;
    case 'good':
      return Icons.signal_cellular_alt;
    case 'fair':
      return Icons.signal_cellular_alt_2_bar;
    case 'poor':
    case 'very poor':
      return Icons.signal_cellular_alt_1_bar;
    default:
      return Icons.signal_cellular_off;
  }
}

/// Small tappable "Signal: <grade>" readout for the chat/channel chat
/// app bars - taps through to the existing CompanionRadioStatsScreen
/// for the raw dBm numbers, same as RadioStatsIconButton right next to
/// it. Reuses the connector's existing ref-counted radio-stats polling
/// (acquireRadioStatsPolling/releaseRadioStatsPolling) - safe to mount
/// alongside RadioStatsIconButton, which already polls the same data.
class SignalGradeIndicator extends StatefulWidget {
  const SignalGradeIndicator({super.key});

  @override
  State<SignalGradeIndicator> createState() => _SignalGradeIndicatorState();
}

class _SignalGradeIndicatorState extends State<SignalGradeIndicator> {
  MeshCoreConnector? _connector;

  @override
  void initState() {
    super.initState();
    final c = context.read<MeshCoreConnector>();
    _connector = c;
    c.acquireRadioStatsPolling();
  }

  @override
  void dispose() {
    _connector?.releaseRadioStatsPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MeshCoreConnector, ({bool connected, bool supported})>(
      selector: (_, c) =>
          (connected: c.isConnected, supported: c.supportsCompanionRadioStats),
      builder: (context, state, _) {
        if (!state.connected || !state.supported) {
          return const SizedBox.shrink();
        }
        final connector = context.read<MeshCoreConnector>();
        return ValueListenableBuilder<CompanionRadioStats?>(
          valueListenable: connector.radioStatsNotifier,
          builder: (context, stats, _) {
            final grade = signalGradeForStats(stats);
            return Tooltip(
              message: 'Signal: ${grade.label}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => pushCompanionRadioStatsScreen(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconForSignalGrade(grade.label),
                        size: 16,
                        color: grade.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        grade.label,
                        style: TextStyle(fontSize: 10, color: grade.color),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
