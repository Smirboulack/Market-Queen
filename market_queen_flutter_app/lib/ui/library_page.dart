import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import '../models/library_model.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/image_drop_grid.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: app.library,
      builder: (context, _) {
        final library = app.library;

        return Padding(
          padding: const EdgeInsets.all(MqTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageHeader(
                          title: tr('Library'),
                          subtitle: library.count == 0
                              ? tr('Everything you generate lands here.')
                              : tr('%1 project(s) in %2')
                                    .arg(library.count)
                                    .arg(app.settings.projectsDir),
                        ),
                        if (library.totalCost > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            //: %1 is a total price like ~$12.40
                            tr(
                              '%1 spent across these projects',
                            ).arg(Format.estimated(library.totalCost)),
                            style: TextStyle(
                              color: mq.textTertiary,
                              fontSize: MqTheme.fontSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    text: tr('Open folder'),
                    onPressed: () =>
                        PlatformUtil.openPath(app.settings.projectsDir),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(text: tr('Refresh'), onPressed: library.refresh),
                ],
              ),
              const SizedBox(height: MqTheme.gapLarge),
              Expanded(
                child: library.count == 0
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 34,
                              color: mq.textTertiary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('No projects yet'),
                              style: TextStyle(
                                color: mq.textSecondary,
                                fontSize: MqTheme.fontBody,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 236,
                              mainAxisExtent: 268,
                              crossAxisSpacing: MqTheme.gap,
                              mainAxisSpacing: MqTheme.gap,
                            ),
                        itemCount: library.count,
                        itemBuilder: (context, index) =>
                            _ProjectCard(project: library.projects[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final LibraryProject project;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: () => PlatformUtil.openPath(
        project.finalVideo.isNotEmpty ? project.finalVideo : project.dir,
      ),
      // Cards sit in a grid: hover snaps both ways, fill and border together.
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceTertiary
              : states.hovered
              ? mq.surfaceSecondary
              : mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 138,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: mq.background,
                      borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: project.thumbnail.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.grid_view_rounded,
                              size: 26,
                              color: mq.textTertiary,
                            ),
                          )
                        : LocalImage(project.thumbnail),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    // Shrink-wrapped rather than centred in a fixed box: the
                    // word inside is translated, and "terminé" is wider than
                    // "done".
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: project.success
                            ? mq.successSubtle
                            : mq.errorSubtle,
                        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          project.success ? tr('done') : tr('failed'),
                          style: TextStyle(
                            color: project.success
                                ? mq.successText
                                : mq.errorText,
                            fontSize: MqTheme.fontMicro,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              project.productName.isNotEmpty
                  ? project.productName
                  : project.folderName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontBody,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                project.hook,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            // Two rows, not one: a 236px card cannot hold the date, the cost
            // and a translated "Show file" side by side -- in French the link
            // alone is half the width, and squeezing them together elided the
            // date down to "8 …".
            Row(
              children: [
                Flexible(
                  child: Text(
                    project.createdAt,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ),
                if (project.hasCost)
                  Text(
                    '  ·  ${Format.estimated(project.cost)}',
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              // Its own tap target, sitting above the card's: the gesture
              // arena gives the press to the innermost detector, so one click
              // never both reveals the file and opens the video.
              child: MqLink(
                text: tr('Show file'),
                onPressed: () => PlatformUtil.revealPath(
                  project.finalVideo.isNotEmpty
                      ? project.finalVideo
                      : project.dir,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
