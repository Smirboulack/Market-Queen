import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import '../models/library_model.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
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
                        Text(
                          tr('Library'),
                          style: TextStyle(
                            color: mq.text,
                            fontSize: MqTheme.fontHeading,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          library.count == 0
                              ? tr('Everything you generate lands here.')
                              : tr('%1 project(s) in %2')
                                  .arg(library.count)
                                  .arg(app.settings.projectsDir),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: mq.textDim, fontSize: MqTheme.fontBody),
                        ),
                        if (library.totalCost > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            //: %1 is a total price like ~$12.40
                            tr('%1 spent across these projects')
                                .arg(Format.estimated(library.totalCost)),
                            style: TextStyle(
                                color: mq.textFaint,
                                fontSize: MqTheme.fontSmall),
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
                            Icon(Icons.grid_view_rounded,
                                size: 34, color: mq.textFaint),
                            const SizedBox(height: 8),
                            Text(
                              tr('No projects yet'),
                              style: TextStyle(
                                  color: mq.textDim,
                                  fontSize: MqTheme.fontBody),
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

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({required this.project});

  final LibraryProject project;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final project = widget.project;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => PlatformUtil.openPath(
            project.finalVideo.isNotEmpty ? project.finalVideo : project.dir),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            // Cards sit in a grid: hover snaps both ways, fill and border
            // together.
            color: _hovered ? mq.surfaceAlt : mq.surface,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(color: _hovered ? mq.borderStrong : mq.border),
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
                        borderRadius:
                            BorderRadius.circular(MqTheme.radiusSmall),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: project.thumbnail.isEmpty
                          ? Center(
                              child: Icon(Icons.grid_view_rounded,
                                  size: 26, color: mq.textFaint),
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
                          color: mq.tint(
                              project.success ? mq.success : mq.danger),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          child: Text(
                            project.success ? tr('done') : tr('failed'),
                            style: TextStyle(
                              color: project.success ? mq.success : mq.danger,
                              fontSize: MqTheme.fontSmall - 1,
                              fontWeight: FontWeight.w600,
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
                  color: mq.text,
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
                  style:
                      TextStyle(color: mq.textDim, fontSize: MqTheme.fontSmall),
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
                          color: mq.textFaint, fontSize: MqTheme.fontSmall),
                    ),
                  ),
                  if (project.hasCost)
                    Text(
                      '  ·  ${Format.estimated(project.cost)}',
                      style: TextStyle(
                          color: mq.textFaint, fontSize: MqTheme.fontSmall),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Align(
                alignment: AlignmentDirectional.centerStart,
                // Its own tap target, sitting above the card's: the gesture
                // arena gives the press to the innermost detector, so one click
                // never both reveals the file and opens the video.
                child: Pressable(
                  onTap: () => PlatformUtil.revealPath(
                      project.finalVideo.isNotEmpty
                          ? project.finalVideo
                          : project.dir),
                  builder: (context, hovered, pressed) => Text(
                    tr('Show file'),
                    style: TextStyle(
                      color: hovered ? mq.accentHover : mq.accent,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
