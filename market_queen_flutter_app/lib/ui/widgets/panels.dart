import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_state.dart';
import '../../core/log_model.dart';
import '../../i18n/translator.dart';
import '../../pipeline/pipeline.dart';
import '../format.dart';
import '../theme.dart';

/// What the next click on Generate is going to cost.
///
/// The caller passes the same request map the pipeline receives, so the figures
/// always describe the form as it stands. Everything is an estimate and says
/// so: a model whose price we do not know is counted separately rather than
/// folded into the total as zero.
class EstimateCard extends StatelessWidget {
  const EstimateCard({super.key, required this.app, required this.request});

  final AppState app;
  final Map<String, Object?> request;

  /// "2026-08-08" in the catalogue, in the reader's own date format.
  String get _checkedOn {
    final raw = app.pricing.updated;
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    return date == null ? raw : DateFormat.yMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final breakdown = app.pricing.estimate(request);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tr('Estimated cost'),
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_checkedOn.isNotEmpty)
                Text(
                  //: %1 is a date like "8 Aug 2026"
                  tr('prices %1').arg(_checkedOn),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in breakdown.lines) ...[
            Row(
              children: [
                Text(
                  Format.stepLabel(line.step),
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  Format.unitsLabel(line.units, line.unit),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
                const Spacer(),
                Text(
                  line.known ? Format.estimated(line.amount) : tr('?'),
                  style: TextStyle(
                    color: line.known ? mq.textPrimary : mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Container(height: 1, color: mq.divider),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                tr('Total'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                Format.estimated(breakdown.total),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontBody,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // Never silently under-report: if a model has no published price, the
          // total above is only part of the bill and has to say so.
          if (breakdown.unknownCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              //: %1 is a count of models
              tr(
                '+ %1 model(s) with no published price',
              ).arg(breakdown.unknownCount),
              style: TextStyle(
                color: mq.warningText,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            tr('An estimate, not a bill. Each provider charges you directly.'),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pipeline steps and where the run has got to.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.steps});

  final List<StepInfo> steps;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      children: [
        for (final step in steps)
          SizedBox(
            height: 30,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Center(child: _StateDot(state: step.state)),
                ),
                const SizedBox(width: 10),
                Text(
                  step.label,
                  style: TextStyle(
                    color: switch (step.state) {
                      StepPhase.running || StepPhase.done => mq.textPrimary,
                      StepPhase.failed => mq.error,
                      _ => mq.textTertiary,
                    },
                    fontSize: MqTheme.fontBody,
                    fontWeight: step.state == StepPhase.running
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    step.detail,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StateDot extends StatefulWidget {
  const _StateDot({required this.state});

  final StepPhase state;

  @override
  State<_StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<_StateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.state == StepPhase.running) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StateDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == StepPhase.running && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.state != StepPhase.running && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final fill = switch (widget.state) {
      StepPhase.done => mq.success,
      StepPhase.failed => mq.error,
      StepPhase.running => mq.primary,
      _ => Colors.transparent,
    };

    final glyph = switch (widget.state) {
      StepPhase.done => '✓',
      StepPhase.failed => '✕',
      StepPhase.skipped => '–',
      _ => '',
    };

    final dot = Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: switch (widget.state) {
            StepPhase.skipped => mq.borderStrong,
            StepPhase.done ||
            StepPhase.failed ||
            StepPhase.running => Colors.transparent,
            _ => mq.border,
          },
        ),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: switch (widget.state) {
            StepPhase.skipped => mq.textTertiary,
            StepPhase.running => mq.onPrimary,
            // Inverse rather than white: in the dark skin these fills are the
            // light ones, and a white tick on them is a smudge.
            _ => mq.textInverse,
          },
          fontSize: MqTheme.fontMicro,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );

    if (widget.state != StepPhase.running) return dot;

    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.35).animate(_pulse),
      child: dot,
    );
  }
}

/// The activity log: what the run said, as it said it.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.log});

  final LogModel log;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scroll = ScrollController();

  /// Follow the tail unless the user scrolled up to read something.
  bool _pinned = true;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _pinned = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _followTail() {
    if (!_pinned || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final entries = widget.log.entries;
        if (entries.length != _lastCount) {
          _lastCount = entries.length;
          _followTail();
        }

        return Container(
          height: 200,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mq.background,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(color: mq.border),
          ),
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    tr('Nothing yet.'),
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.clock,
                            style: TextStyle(
                              color: mq.textTertiary,
                              fontSize: MqTheme.fontSmall,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.message,
                              style: TextStyle(
                                color: mq.levelColor(entry.level.index),
                                fontSize: MqTheme.fontSmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// A thin progress bar that animates towards its new value.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: 4,
        decoration: BoxDecoration(
          color: mq.surfaceTertiary,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: constraints.maxWidth * value.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: mq.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
