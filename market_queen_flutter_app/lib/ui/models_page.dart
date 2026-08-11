import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/key_field.dart';

/// Where the app is configured: five panels, one per kind of generation.
///
/// This used to be two screens that never referred to each other -- a wall of
/// API key fields in Settings, and a wall of model names here -- and nothing on
/// either said which key unlocked which model. That is not knowable by looking:
/// one OpenAI key covers the writer, the stills, Sora and the voice-over, while
/// LTX's covers a single row of one panel.
///
/// So a panel is now the whole answer for one kind of generation: the providers
/// that do it, the key each one needs, and which of its models the composer may
/// offer. Providers are filtered by what they actually do, so nobody scrolls
/// past a video house looking for somewhere to write a script.
///
/// Everything is on by default, and a model added in a future release arrives
/// switched on, because the stored setting is the *hidden* set.
class ModelsPage extends StatelessWidget {
  const ModelsPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Providers come and go with the keys that unlock them, and every tick
      // rewrites the stored set.
      listenable: Listenable.merge([app.settings, app.registry]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(MqTheme.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: tr('Models'),
              subtitle: tr(
                'Pick a provider, paste its key, tick what you want from it. '
                'Keys are encrypted on this machine and sent only to the '
                'provider they belong to.',
              ),
            ),
            const SizedBox(height: MqTheme.gapLarge),
            for (final panel in Registry.panels) ...[
              _Panel(app: app, panel: panel),
              const SizedBox(height: MqTheme.gapLarge),
            ],
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.app, required this.panel});

  final AppState app;
  final PanelEntry panel;

  @override
  Widget build(BuildContext context) {
    final providers = app.registry.providersForPanel(panel.id);
    if (providers.isEmpty) return const SizedBox.shrink();

    final credentials = app.registry.credentialsForPanel(panel.id);

    return SectionCard(
      title: tr(panel.title),
      subtitle: tr(panel.subtitle),
      children: [
        // Keys first, models second: a panel reads top to bottom as the order
        // the work is done in. A key that also unlocks another panel is drawn
        // in both, editing the one stored value.
        for (final credential in credentials)
          KeyField(app: app, credential: credential),
        if (credentials.isNotEmpty) const SizedBox(height: 2),
        for (final provider in providers)
          _ProviderBlock(app: app, provider: provider),
      ],
    );
  }
}

/// One provider and its catalogue.
class _ProviderBlock extends StatelessWidget {
  const _ProviderBlock({required this.app, required this.provider});

  final AppState app;
  final ProviderEntry provider;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final settings = app.settings;

    final ids = [for (final model in provider.models) model.id];
    final shown = ids.where((id) => settings.modelShown(provider.id, id)).length;
    final keyMissing = provider.credential.isNotEmpty &&
        !settings.hasApiKey(provider.credential);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                provider.label,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              // Not an error: a provider whose key is missing is still worth
              // shortlisting, and the field for it is a few lines up this same
              // panel now rather than on another screen.
              if (keyMissing)
                Text(
                  tr('no API key'),
                  style: TextStyle(
                    color: mq.warningText,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
              const Spacer(),
              Text(
                //: %1 is how many models are enabled, %2 how many there are
                tr('%1 of %2').arg(shown).arg(ids.length),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              MqLink(
                text: shown == ids.length ? tr('None') : tr('All'),
                onPressed: () => settings.setProviderModelsHidden(
                  provider.id,
                  ids,
                  shown == ids.length,
                ),
              ),
            ],
          ),
          if (provider.note.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              provider.note,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
          const SizedBox(height: MqTheme.gap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final model in provider.models)
                _ModelToggle(
                  app: app,
                  providerId: provider.id,
                  model: model,
                  // "Auto" is not a model and cannot be switched off: it is the
                  // instruction to pick the best of whatever is left on.
                  fixed: Registry.isAuto(model.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One model: its name, its unit price, and whether the composer may offer it.
class _ModelToggle extends StatelessWidget {
  const _ModelToggle({
    required this.app,
    required this.providerId,
    required this.model,
    required this.fixed,
  });

  final AppState app;
  final String providerId;
  final ModelEntry model;
  final bool fixed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final on = fixed || app.settings.modelShown(providerId, model.id);
    final price = Format.unitPriceLabel(app.pricing.unitPrice(model.id));

    return Pressable(
      enabled: !fixed,
      onTap: () =>
          app.settings.setModelHidden(providerId, model.id, on),
      tooltip: fixed
          ? tr('Auto always stays on: it picks from whatever is enabled.')
          : '',
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
        decoration: BoxDecoration(
          color: !on
              ? Colors.transparent
              : states.active
              ? mq.surfaceActive
              : mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: !on
                ? mq.borderSubtle
                : states.active
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A filled square with a tick, or an empty outline. The state is
            // the point of the row, so it leads.
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? mq.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? mq.primary : mq.borderStrong,
                ),
              ),
              child: on
                  ? MqIcon('check-line', size: 11, color: mq.onPrimary)
                  : null,
            ),
            const SizedBox(width: 9),
            Text(
              model.label,
              style: TextStyle(
                color: on ? mq.textPrimary : mq.textTertiary,
                fontSize: MqTheme.fontLabel,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            // The price is what the model costs once the free quota is gone,
            // so the two belong side by side rather than one instead of the
            // other: "Free tier" alone would read as "this is never billed".
            if (model.isFree) ...[
              const SizedBox(width: 10),
              Text(
                tr('Free tier'),
                style: TextStyle(
                  color: on ? mq.successText : mq.textDisabled,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (price.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                price,
                style: TextStyle(
                  color: on ? mq.textTertiary : mq.textDisabled,
                  fontSize: MqTheme.fontSmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
