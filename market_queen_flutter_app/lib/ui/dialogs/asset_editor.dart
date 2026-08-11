import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/mq_dialog.dart';
import 'asset_studio.dart';

/// Changing an actor or a scene that already exists.
///
/// Deliberately not where one is *made*: that is [showAssetStudio], which is a
/// conversation with a model, and pouring it into the same card as a name field
/// is what made this screen read as a form with a picture stapled to it. What
/// is left here is the small stuff -- the name, the description, the references
/// -- plus the two doors back out to the studio and to the file picker when the
/// picture itself is what is wrong.
///
/// The voice is not here either. It belongs next to the script the actor is
/// going to read, and that is where it lives now: the actor panel on the
/// composer.
///
/// Returns the id if it was saved, or null.
Future<String?> showAssetEditor(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
  required LibraryAsset asset,
}) {
  return showMqModal<String>(
    context: context,
    // A form with half-typed text in it must not vanish on a stray click.
    dismissible: false,
    child: AssetEditor(app: app, kind: kind, asset: asset),
  );
}

class AssetEditor extends StatefulWidget {
  const AssetEditor({
    super.key,
    required this.app,
    required this.kind,
    required this.asset,
  });

  final AppState app;
  final AssetKind kind;
  final LibraryAsset asset;

  @override
  State<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<AssetEditor> {
  late final LibraryAsset _draft = widget.asset.copy();

  late final TextEditingController _name = TextEditingController(
    text: _draft.name,
  );
  late final TextEditingController _prompt = TextEditingController(
    text: _draft.prompt,
  );

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library =>
      _isActor ? widget.app.actors : widget.app.scenes;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _save() {
    _draft
      ..name = _name.text.trim()
      ..prompt = _prompt.text.trim();
    final id = _library.save(_draft);
    if (mounted) closeMqModal(context, id);
  }

  /// Back into the studio to shoot the picture again, carrying everything this
  /// one already knows -- so "same person, but outdoors" is one sentence rather
  /// than starting over.
  Future<void> _reshoot() async {
    _draft
      ..name = _name.text.trim()
      ..prompt = _prompt.text.trim();

    final id = await showAssetStudio(
      context,
      app: widget.app,
      kind: widget.kind,
      asset: _draft,
    );
    if (id != null && mounted) closeMqModal(context, id);
  }

  Future<void> _delete() async {
    final confirmed = await askToConfirm(
      context,
      title: _isActor ? tr('Delete this actor?') : tr('Delete this scene?'),
      message: _isActor
          ? tr('It is taken off every ad that cast it. Nothing already '
              'generated changes.')
          : tr('It is taken off every ad that used it. Nothing already '
              'generated changes.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) return;

    if (_isActor) {
      widget.app.deleteActor(_draft.id);
    } else {
      widget.app.deleteScene(_draft.id);
    }
    if (mounted) closeMqModal(context);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MqModalCard(
      width: 660,
      title: _isActor ? tr('Edit the actor') : tr('Edit the scene'),
      subtitle: _isActor
          ? tr('What they are called, what they look like, and the pictures '
              'they were built from.')
          : tr('What it is called, what it looks like, and the pictures it '
              'was built from.'),
      actions: [
        GhostButton(
          text: tr('Delete'),
          destructive: true,
          onPressed: _delete,
        ),
        GhostButton(
          text: tr('Cancel'),
          onPressed: () => closeMqModal(context),
        ),
        PrimaryButton(text: tr('Save'), onPressed: _save),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 176,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: mq.surfaceSecondary,
                          borderRadius: BorderRadius.circular(MqTheme.radius),
                          border: Border.all(color: mq.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _draft.thumbnail.isEmpty
                            ? Center(
                                child: MqIcon(
                                  _isActor ? 'user-smile-line' : 'scene-line',
                                  size: 24,
                                  color: mq.textTertiary,
                                ),
                              )
                            : LocalImage(_draft.thumbnail),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      text: tr('Shoot it again'),
                      onPressed: _reshoot,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MqTheme.gapLarge),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                      controller: _name,
                      label: tr('Name'),
                      placeholder: _library.suggestedName(),
                    ),
                    const SizedBox(height: MqTheme.gap),
                    LabeledArea(
                      controller: _prompt,
                      label: tr('Description'),
                      areaHeight: 76,
                      placeholder: _isActor
                          ? tr('A woman in her twenties, tired, no make-up, '
                              'plain grey t-shirt…')
                          : tr('A small bathroom, towels on the floor, one '
                              'window…'),
                      onChanged: (text) => _draft.prompt = text,
                    ),
                    const SizedBox(height: MqTheme.gap),
                    MediaDropZone(
                      paths: _draft.media,
                      title: tr('Reference pictures'),
                      hint: _isActor
                          ? tr('The first one is the face every shot keeps.')
                          : tr('The first one is the room every shot keeps.'),
                      tileSize: 56,
                      onAdded: (paths) => setState(() {
                        for (final path in paths) {
                          if (!_draft.media.contains(path)) {
                            _draft.media.add(path);
                          }
                        }
                      }),
                      onRemoved: (index) =>
                          setState(() => _draft.media.removeAt(index)),
                      onPrimary: (index) => setState(() {
                        _draft.media.insert(0, _draft.media.removeAt(index));
                      }),
                    ),
                    if (!_isActor) ...[
                      const SizedBox(height: MqTheme.gap),
                      FieldLabel(tr('Optional')),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tweak in SceneTweak.all)
                            MqChoiceChip(
                              label: tweak.label,
                              value: _draft.extraText(tweak.key),
                              onPicked: (value) => setState(
                                () => _draft.setExtra(tweak.key, value),
                              ),
                              options: [
                                for (final option in tweak.options)
                                  MenuOption(option.$1, option.$2),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
