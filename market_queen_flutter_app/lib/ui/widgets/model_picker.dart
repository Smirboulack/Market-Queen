import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../format.dart';
import '../theme.dart';
import 'fields.dart';

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
            final price =
                Format.unitPriceLabel(widget.app.pricing.unitPrice(model.id));
            return price.isEmpty ? model.label : '${model.label}   $price';
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
                  color: mq.textDim,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Spacer(),
            if (keyMissing)
              Text(
                tr('no API key'),
                style:
                    TextStyle(color: mq.warning, fontSize: MqTheme.fontSmall),
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
            style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
          ),
        ],
      ],
    );
  }
}
