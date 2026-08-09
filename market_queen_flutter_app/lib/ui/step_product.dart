import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/fields.dart';
import 'widgets/image_drop_grid.dart';

/// Step 1 -- what is being sold.
///
/// This step is pure context: nothing here is generated, everything here is fed
/// to every step that follows.
class StepProduct extends StatefulWidget {
  const StepProduct({super.key, required this.app});

  final AppState app;

  @override
  State<StepProduct> createState() => _StepProductState();
}

class _StepProductState extends State<StepProduct> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _audience = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resync();
    // The fields hold their own text once the user is typing, so a change made
    // behind their back -- Start over, mostly -- has to be pushed in.
    widget.app.project.cleared.addListener(_resync);
  }

  @override
  void dispose() {
    widget.app.project.cleared.removeListener(_resync);
    _name.dispose();
    _description.dispose();
    _audience.dispose();
    super.dispose();
  }

  void _resync() {
    final product = widget.app.project.product;
    _name.text = '${product['name'] ?? ''}';
    _description.text = '${product['description'] ?? ''}';
    _audience.text = '${product['audience'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.app.project;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: tr('What are you selling?'),
          subtitle: tr(
            'Everything the actor says and everything on screen is '
            'built from this.',
          ),
        ),
        const SizedBox(height: MqTheme.gapLarge),

        SectionCard(
          children: [
            LabeledField(
              controller: _name,
              label: tr('Product or service'),
              placeholder: tr('e.g. Lumen glow serum'),
              onChanged: (text) => project.setProductField('name', text),
            ),
            LabeledArea(
              controller: _description,
              label: tr('What it is'),
              placeholder: tr(
                'A vitamin C serum that clears dull skin in two weeks. '
                'Fragrance free, 30 ml.',
              ),
              onChanged: (text) => project.setProductField('description', text),
            ),
            LabeledField(
              controller: _audience,
              label: tr('Who it is for'),
              placeholder: tr('e.g. women 25-35 who care about clean beauty'),
              onChanged: (text) => project.setProductField('audience', text),
            ),
          ],
        ),
        const SizedBox(height: MqTheme.gapLarge),

        SectionCard(
          title: tr('Reference pictures'),
          subtitle: tr(
            'A picture of the real product keeps it recognisable in every shot.',
          ),
          children: [
            ImageDropGrid(
              images: project.imagesFor('product'),
              onFilesAdded: (paths) => project.addImages('product', paths),
              onRemoveRequested: (index) =>
                  project.removeImage('product', index),
              onPrimaryRequested: (index) =>
                  project.setPrimaryImage('product', index),
            ),
          ],
        ),
        const SizedBox(height: MqTheme.gapLarge),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PrimaryButton(
              text: tr('Next: the scenario'),
              enabled: project.stepStates[0].valid,
              onPressed: () => project.currentStep = 1,
            ),
          ],
        ),
      ],
    );
  }
}
