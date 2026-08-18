import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

/// Every ad there is, as a list of names in the left column.
///
/// It replaced a tree of projects, and the reason is that the tree was
/// answering a question nobody asked. Making an ad meant first making a folder
/// to put it in, naming that, then naming the ad -- two dialogs and a decision
/// about taxonomy before a single word of script. What people actually do is
/// make one, then make another one, so this is the shape of that: a flat list,
/// newest at the top, one press to open, exactly like the conversation list of
/// a chat app.
class AdList extends StatelessWidget {
  const AdList({
    super.key,
    required this.app,
    required this.openAdId,
    required this.onNew,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final AppState app;

  /// The ad the editor is on, if any.
  final String openAdId;

  final VoidCallback onNew;
  final void Function(String projectId, String adId) onOpen;
  final void Function(String projectId, String adId) onRename;

  /// Asked for, not done: the caller confirms, deletes, and decides what the
  /// editor shows next if the ad being deleted is the one it is on.
  final void Function(String projectId, String adId) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.workspace,
      builder: (context, _) {
        final ads = app.workspace.allAds;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _NewRow(label: tr('+ New ad'), onTap: onNew),
            ),
            if (ads.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(
                  tr('Nothing here yet. Make your first ad.'),
                  style: TextStyle(
                    color: context.mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineBody,
                  ),
                ),
              )
            else
              // Takes the rest of the column and scrolls inside it: a hundred
              // ads must not push the status line off the bottom of the window.
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: ads.length,
                  itemBuilder: (context, index) {
                    final entry = ads[index];
                    return _AdRow(
                      label: entry.ad.name,
                      selected: entry.ad.id == openAdId,
                      onTap: () => onOpen(entry.projectId, entry.ad.id),
                      onRename: () => onRename(entry.projectId, entry.ad.id),
                      onDelete: () => onDelete(entry.projectId, entry.ad.id),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One ad. A name, and -- under the pointer or when it is the one you are on --
/// a pencil.
class _AdRow extends StatelessWidget {
  const _AdRow({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 4),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? mq.primarySubtle
              : states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: selected || states.active
                      ? mq.textPrimary
                      : mq.textSecondary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            // Its room is held whether or not it is showing, so a row does not
            // reflow under the pointer.
            SizedBox(
              width: 24,
              child: IgnorePointer(
                ignoring: !states.active && !selected,
                child: AnimatedOpacity(
                  opacity: states.active || selected ? 1 : 0,
                  duration: MqTheme.hoverDuration,
                  child: MqIconButton(
                    icon: 'edit-line',
                    tip: tr('Rename this ad'),
                    size: 24,
                    onPressed: onRename,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: IgnorePointer(
                ignoring: !states.active && !selected,
                child: AnimatedOpacity(
                  opacity: states.active || selected ? 1 : 0,
                  duration: MqTheme.hoverDuration,
                  child: MqIconButton(
                    icon: 'delete-bin-line',
                    tip: tr('Delete the ad'),
                    size: 24,
                    onPressed: onDelete,
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

/// "+ New ad". Plain text rather than a button: the list is a list of places,
/// and the way to make another one belongs in the list.
class _NewRow extends StatelessWidget {
  const _NewRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: states.active ? mq.textPrimary : mq.textTertiary,
            fontSize: MqTheme.fontLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
