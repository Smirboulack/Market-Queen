import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

/// The studio, unfolded in the left column.
///
/// The studio is four screens deep -- projects, that project's ads, the ad, its
/// run -- and until this existed the only way sideways was back up the crumb
/// trail and down again: two clicks and two page loads to look at the ad next
/// to the one you are on. Everything the trail can reach is a row here instead,
/// and the row you are on is lit, so the nav answers "where am I" and "what
/// else is there" at once.
///
/// It is capped and scrolls rather than growing without limit. Twenty projects
/// must not push Settings off the bottom of the window.
class StudioTree extends StatefulWidget {
  const StudioTree({
    super.key,
    required this.app,
    required this.openProjectId,
    required this.openAdId,
    required this.onNewProject,
    required this.onNewAd,
    required this.onOpenProject,
    required this.onOpenAd,
  });

  final AppState app;

  /// What the studio is showing. Empty means the project list.
  final String openProjectId;
  final String openAdId;

  final VoidCallback onNewProject;
  final ValueChanged<String> onNewAd;
  final ValueChanged<String> onOpenProject;
  final void Function(String projectId, String adId) onOpenAd;

  /// As tall as the tree is allowed to get before its rows start scrolling.
  static const double maxHeight = 340;

  @override
  State<StudioTree> createState() => _StudioTreeState();
}

class _StudioTreeState extends State<StudioTree> {
  /// Folded and unfolded by hand. The project you are in is always unfolded
  /// whatever this says -- you are looking at its ads, so hiding them would be
  /// a lie -- and this is only consulted for the others.
  final Set<String> _unfolded = {};

  bool _isUnfolded(String id) =>
      id == widget.openProjectId || _unfolded.contains(id);

  void _toggle(String id) {
    setState(() {
      if (!_unfolded.remove(id)) _unfolded.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app.workspace,
      builder: (context, _) {
        final projects = widget.app.workspace.byRecency;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: StudioTree.maxHeight),
          child: Padding(
            // Indented under the Studio row, and hung off a hairline so the
            // block reads as belonging to it rather than as five more nav
            // entries that happen to be smaller.
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NewRow(
                  label: tr('+ New project'),
                  onTap: widget.onNewProject,
                ),
                if (projects.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final project in projects) ...[
                            _TreeRow(
                              label: project.name,
                              icon: 'folder-line',
                              selected: project.id == widget.openProjectId &&
                                  widget.openAdId.isEmpty,
                              onTap: () => widget.onOpenProject(project.id),
                              unfolded: _isUnfolded(project.id),
                              onFold: project.ads.isEmpty
                                  ? null
                                  : () => _toggle(project.id),
                            ),
                            if (_isUnfolded(project.id)) ...[
                              for (final ad
                                  in widget.app.workspace.adsByRecency(
                                project.id,
                              ))
                                _TreeRow(
                                  label: ad.name,
                                  icon: 'clapperboard-line',
                                  depth: 1,
                                  selected: ad.id == widget.openAdId,
                                  onTap: () =>
                                      widget.onOpenAd(project.id, ad.id),
                                ),
                              _NewRow(
                                label: tr('+ New ad'),
                                depth: 1,
                                onTap: () => widget.onNewAd(project.id),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One project or one ad.
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.depth = 0,
    this.unfolded = false,
    this.onFold,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  /// 0 for a project, 1 for one of its ads.
  final int depth;

  final bool unfolded;

  /// Null on a project with no ads, and on every ad. The chevron is a second
  /// target rather than a second meaning for the row: pressing a project always
  /// opens it, which is what you do far more often than fold it away.
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 30,
        padding: EdgeInsets.only(left: 4.0 + depth * 14, right: 6),
        margin: const EdgeInsets.only(bottom: 1),
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
            SizedBox(
              width: 18,
              child: onFold == null
                  ? null
                  : Pressable(
                      onTap: onFold,
                      focusRadius: MqTheme.radiusSmall,
                      builder: (context, chevron) => MqIcon(
                        unfolded ? 'arrow-down-s-line' : 'arrow-right-s-line',
                        size: 16,
                        color: chevron.active
                            ? mq.textPrimary
                            : mq.textTertiary,
                      ),
                    ),
            ),
            MqIcon(
              icon,
              size: 15,
              color: selected ? mq.textPrimary : mq.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected || states.active
                      ? mq.textPrimary
                      : mq.textSecondary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+ New project", "+ New ad". Plain text rather than a button: the tree is a
/// list of places, and the way to make another one belongs in the list.
class _NewRow extends StatelessWidget {
  const _NewRow({required this.label, required this.onTap, this.depth = 0});

  final String label;
  final VoidCallback onTap;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 30,
        padding: EdgeInsets.only(left: 22.0 + depth * 14, right: 6),
        margin: const EdgeInsets.only(bottom: 1),
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
