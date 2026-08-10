import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../theme.dart';
import '../widgets/mq_dialog.dart';
import 'studio_card.dart';

/// The studio's front page: your projects, and nothing else.
///
/// A project is a folder of ads for one product or one campaign. It carries no
/// settings of its own on purpose -- everything that shapes an ad belongs to
/// the ad, and a project that could quietly override it would be one more place
/// to look when a render comes out wrong.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.app, required this.onOpen});

  final AppState app;
  final ValueChanged<String> onOpen;

  Future<void> _create(BuildContext context) async {
    final name = await askForName(
      context,
      title: tr('New project'),
      subtitle: tr('A folder for the ads of one product or one campaign.'),
      label: tr('Project name'),
      placeholder: tr('e.g. Lumen glow serum'),
      confirmLabel: tr('Create'),
      initial: app.workspace.suggestedProjectName(),
    );
    if (name == null) return;

    final project = app.workspace.createProject(name);
    onOpen(project.id);
  }

  Future<void> _rename(BuildContext context, String id, String current) async {
    final name = await askForName(
      context,
      title: tr('Rename the project'),
      label: tr('Project name'),
      placeholder: current,
      confirmLabel: tr('Rename'),
      initial: current,
    );
    if (name != null) app.workspace.renameProject(id, name);
  }

  Future<void> _delete(BuildContext context, String id, String name) async {
    final confirmed = await askToConfirm(
      context,
      //: %1 is a project name
      title: tr('Delete "%1"?').arg(name),
      message: tr(
        'Every ad in it goes with it. Videos already generated stay in your '
        'projects folder.',
      ),
      confirmLabel: tr('Delete the project'),
    );
    if (confirmed) app.workspace.removeProject(id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.workspace,
      builder: (context, _) {
        final projects = app.workspace.byRecency;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.pagePadding,
            MqTheme.gapLarge,
            MqTheme.pagePadding,
            MqTheme.gapLarge * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudioNewButton(
                label: tr('+ New project'),
                onPressed: () => _create(context),
              ),
              const SizedBox(height: MqTheme.gapLarge),
              if (projects.isEmpty)
                StudioEmptyNote(
                  text: tr(
                    'No project yet. A project is a folder for the ads of one '
                    'product or one campaign.',
                  ),
                ),
              Wrap(
                spacing: MqTheme.gap,
                runSpacing: MqTheme.gap,
                children: [
                  for (final project in projects)
                    StudioCard(
                      name: project.name,
                      updatedAt: project.updatedAt,
                      detail: project.ads.isEmpty
                          ? tr('No ad yet')
                          //: %1 is a number of ads
                          : tr('%1 ad(s)').arg(project.ads.length),
                      onOpen: () => onOpen(project.id),
                      onRename: () =>
                          _rename(context, project.id, project.name),
                      onDelete: () =>
                          _delete(context, project.id, project.name),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
