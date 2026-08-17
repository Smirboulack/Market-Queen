import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../dialogs/api_key_dialog.dart';
import '../format.dart';
import '../theme.dart';
import 'chip.dart';
import 'fields.dart';

/// The model a one-off generation will be bought from, as a chip.
///
/// It exists because the app is bring-your-own-keys: every screen that spends
/// money has to name what it is about to spend it on, and be able to change it
/// on the spot. The full two-combo [ModelPicker] is right on a settings page
/// and far too heavy to sit in a prompt bar.
///
/// Every model the app can reach is in the menu, with its account's mark beside
/// it and its price after it. A model on an account with no key is listed too,
/// greyed, saying so -- and pressing it asks for that key rather than sending
/// you to the Models page to find the right card among fifteen. The chip itself
/// shows the name alone: the price is what you want while choosing and noise
/// afterwards.
class ModelChip extends StatelessWidget {
  const ModelChip({super.key, required this.app, required this.category});

  final AppState app;
  final String category;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.registry]),
      builder: (context, _) {
        final registry = app.registry;
        final settings = app.settings;

        final providers = registry.providers(category);
        final named = providers.length > 1;

        final options = <MenuOption<String>>[];
        for (final provider in providers) {
          final locked = provider.credential.isNotEmpty &&
              !settings.hasApiKey(provider.credential);
          for (final model in provider.models) {
            final price = Format.unitPriceLabel(
              app.pricing.unitPrice(model.id),
            );
            options.add(
              MenuOption(
                [
                  if (named) '${provider.label} · ',
                  model.label,
                  // A price on a row you cannot buy from is noise.
                  if (price.isNotEmpty && !locked) '   $price',
                ].join(),
                '${provider.id}|${model.id}',
                mark: provider.credential,
                locked: locked,
                note: locked ? lockedByKeyLabel : '',
              ),
            );
          }
        }

        final providerId = _providerId;
        final modelId = _modelId(providerId);

        return Builder(
          builder: (anchor) => MqChip(
            label: options.isEmpty
                ? tr('None enabled')
                : registry.modelLabel(providerId, modelId),
            icon: 'layout-line',
            opensMenu: true,
            active: true,
            enabled: options.isNotEmpty,
            tooltip: tr('Which model this is generated with'),
            onPressed: () async {
              final picked = await showChipMenu<String>(
                anchor,
                options: options,
                current: '$providerId|$modelId',
                width: 380,
                onLocked: (option) => askForApiKey(
                  context,
                  app: app,
                  credentialId: option.mark,
                ),
              );
              if (picked == null) return;
              final parts = picked.split('|');
              if (parts.length != 2) return;
              settings
                ..setPref('${category}Provider', parts[0])
                ..setPref('${category}Model', parts[1]);
            },
          ),
        );
      },
    );
  }

  String get _providerId {
    final saved = app.settings.prefString('${category}Provider');
    final known = app.registry
        .providers(category)
        .any((provider) => provider.id == saved);
    return known ? saved : app.registry.defaultProvider(category);
  }

  String _modelId(String providerId) {
    final saved = app.settings.prefString('${category}Model');
    if (saved.isNotEmpty) return saved;
    return app.registry.provider(providerId)?.defaultModel ?? '';
  }
}

/// Provider + model. Both are fixed lists; the model list ends with an
/// "Other..." entry so a brand-new model id can still be pasted in without
/// waiting for a release.
class ModelPicker extends StatefulWidget {
  const ModelPicker({
    super.key,
    required this.app,
    required this.category,
    required this.label,
  });

  final AppState app;
  final String category;
  final String label;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  String _providerId = '';
  String _modelId = '';

  @override
  void initState() {
    super.initState();

    final settings = widget.app.settings;
    final registry = widget.app.registry;

    final savedProvider = settings.prefString('${widget.category}Provider');
    final known = registry
        .providers(widget.category)
        .any((provider) => provider.id == savedProvider);
    _providerId =
        known ? savedProvider : registry.defaultProvider(widget.category);

    final savedModel = settings.prefString('${widget.category}Model');
    _modelId = savedModel.isNotEmpty
        ? savedModel
        : registry.provider(_providerId)?.defaultModel ?? '';

    settings.apiKeysChanged.addListener(_onChanged);
    registry.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.app.settings.apiKeysChanged.removeListener(_onChanged);
    widget.app.registry.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final registry = widget.app.registry;
    final settings = widget.app.settings;

    final providers = registry.providers(widget.category);
    final info = registry.provider(_providerId);
    final credential = info?.credential ?? '';
    final keyMissing = credential.isNotEmpty && !settings.hasApiKey(credential);

    // Seeing "$0.28/s" while choosing is what stops the total on the right
    // being a surprise; a model we have no price for is simply left plain.
    final pricedModels = <MenuEntry<String>>[
      for (final model in info?.models ?? const <ModelEntry>[])
          MenuEntry<String>(
            () {
              final price = Format.unitPriceLabel(
                widget.app.pricing.unitPrice(model.id),
              );
              return [
                model.label,
                if (price.isNotEmpty) '   $price',
              ].join();
            }(),
            model.id,
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.label.isNotEmpty)
              Text(
                widget.label,
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Spacer(),
            if (keyMissing)
              Text(
                tr('no API key'),
                style:
                    TextStyle(color: mq.warningText, fontSize: MqTheme.fontSmall),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StyledCombo<String>(
              width: 170,
              options: [
                for (final provider in providers)
                  MenuEntry(provider.label, provider.id),
              ],
              value: _providerId,
              onPicked: (picked) {
                setState(() {
                  _providerId = picked;
                  // Model ids do not carry over between providers.
                  _modelId = registry.provider(picked)?.defaultModel ?? '';
                });
                settings.setPref('${widget.category}Provider', picked);
                settings.setPref('${widget.category}Model', _modelId);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PickerWithCustom(
                options: pricedModels,
                value: _modelId,
                customLabel: tr('Other model id...'),
                customPlaceholder: tr('e.g. fal-ai/some-new-model'),
                onValueEdited: (value) {
                  setState(() => _modelId = value);
                  settings.setPref('${widget.category}Model', value);
                },
              ),
            ),
          ],
        ),
        if ((info?.note ?? '').isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            info!.note,
            style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
          ),
        ],
      ],
    );
  }
}
