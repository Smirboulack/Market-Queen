import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/mq_dialog.dart';

/// One worked example: a product, and an ad for it written the way one should
/// be written.
class AdExample {
  const AdExample({
    required this.title,
    required this.niche,
    required this.productName,
    required this.productDescription,
    required this.audience,
    required this.script,
  });

  final String title;
  final String niche;
  final String productName;
  final String productDescription;
  final String audience;
  final String script;

  /// Written as one continuous take, every one of them, because that is the
  /// entire lesson. None of them announces a hook or steps into a "solution
  /// section" -- they are somebody talking, and the shape is underneath.
  static List<AdExample> get all => [
    AdExample(
      title: tr('The two-week check-in'),
      niche: tr('Skincare'),
      productName: tr('Vitamin C serum'),
      productDescription: tr('A serum for dull, uneven skin.'),
      audience: tr('People who have already tried three that did nothing.'),
      script: tr(
        'Okay, I genuinely did not think this would work. Three weeks ago my '
        'skin was so flat I was putting makeup on to answer the door. I had '
        'tried the expensive one, the one everybody swears by, nothing. This '
        'is the vitamin C one my sister sent me. Every morning since, that is '
        'the whole routine. Same light, same phone, look at the difference. If '
        'your skin has gone dull and you do not know why, give it two weeks.',
      ),
    ),
    AdExample(
      title: tr('The drawer test'),
      niche: tr('Kitchen'),
      productName: tr('Folding chopping board'),
      productDescription: tr('A board that folds into a chute for the pan.'),
      audience: tr('Small flats, no counter space.'),
      script: tr(
        'My kitchen counter is the size of a laptop, so every board I own '
        'lives on the floor. This one folds. I chop, I pinch the sides, '
        'everything goes straight in the pan and nothing ends up on the hob. '
        'Then it goes in the drawer, which no board of mine has ever done. It '
        'was twelve pounds. That is the entire video.',
      ),
    ),
    AdExample(
      title: tr('The Sunday night problem'),
      niche: tr('Software'),
      productName: tr('Invoicing app for freelancers'),
      productDescription: tr('Invoices, reminders and VAT in one place.'),
      audience: tr('Freelancers doing their books at the weekend.'),
      script: tr(
        'Every Sunday night I used to lose two hours to invoices. Copying last '
        'month, changing the date, getting the VAT wrong, chasing the client '
        'who never pays until you ask twice. I moved all of it into this. It '
        'sends the reminders itself now. Last Sunday I did the whole month in '
        'about four minutes and then went out. That is the only thing I have '
        'to say about it.',
      ),
    ),
    AdExample(
      title: tr('The honest sceptic'),
      niche: tr('Supplements'),
      productName: tr('Magnesium before bed'),
      productDescription: tr('One capsule an hour before sleep.'),
      audience: tr('People who wake at three in the morning.'),
      script: tr(
        'I do not believe in supplements, so take this how you like. I was '
        'waking up at three every night, wide awake, for about a year. A '
        'friend told me to try magnesium before bed. I took one for eight '
        'nights to prove her wrong. I slept through six of them. I am still '
        'sceptical, I just also keep buying it.',
      ),
    ),
    AdExample(
      title: tr('Five minutes'),
      niche: tr('Fitness'),
      productName: tr('Five-minute workout app'),
      productDescription: tr('Short sessions you can do in a hallway.'),
      audience: tr('People who have cancelled two gym memberships.'),
      script: tr(
        'I have cancelled two gym memberships in three years, so the problem '
        'was never the gym. It was the forty minutes of getting there. This '
        'does five. In my hallway, in whatever I am already wearing. I have '
        'done it every day for six weeks, which is longer than either '
        'membership lasted. Five minutes is not impressive. Doing it in '
        'January is.',
      ),
    ),
    AdExample(
      title: tr('The chewer'),
      niche: tr('Pets'),
      productName: tr('Rubber chew toy'),
      productDescription: tr('A chew toy for dogs that destroy everything.'),
      audience: tr('Owners on their fourth toy this month.'),
      script: tr(
        'This is the fourth toy this month. The rope lasted a day, the duck '
        'lasted an afternoon, the tennis ball I do not want to talk about. He '
        'has had this one since the ninth. Here it is. There is one tooth mark '
        'on the end. He still takes it to bed. If your dog does this to '
        'everything, that is all the review you need.',
      ),
    ),
  ];
}

/// Examples worth stealing from.
///
/// Not templates: there is nothing to fill in and no blanks to complete. They
/// are six finished ads, so that "write it the way you would say it" stops
/// being advice and becomes something you can read.
class ExamplesPage extends StatelessWidget {
  const ExamplesPage({super.key, required this.app, required this.onOpenAd});

  final AppState app;

  /// Jumps the studio to the ad an example just created.
  final void Function(String projectId, String adId) onOpenAd;

  Future<void> _use(BuildContext context, AdExample example) async {
    final projectId = await _pickProject(context);
    if (projectId == null || !context.mounted) return;

    final ad = app.workspace.createAd(projectId, example.title);
    app.workspace.openAd(projectId, ad.id);
    app.project
      ..setProductField('name', example.productName)
      ..setProductField('description', example.productDescription)
      ..setProductField('audience', example.audience)
      ..setScript(example.script);

    onOpenAd(projectId, ad.id);
  }

  /// Where the new ad should go. One extra click, and the alternative is an
  /// example that lands in a project the user did not choose.
  Future<String?> _pickProject(BuildContext context) async {
    final projects = app.workspace.byRecency;

    if (projects.isEmpty) {
      final name = await askForName(
        context,
        title: tr('New project'),
        subtitle: tr('The example needs somewhere to live.'),
        label: tr('Project name'),
        placeholder: tr('e.g. Lumen glow serum'),
        confirmLabel: tr('Create'),
        initial: app.workspace.suggestedProjectName(),
      );
      if (name == null) return null;
      return app.workspace.createProject(name).id;
    }

    return showMqModal<String>(
      context: context,
      child: Builder(
        builder: (context) => MqModalCard(
          width: 460,
          title: tr('Which project?'),
          subtitle: tr('The example is copied in as a new ad.'),
          actions: [
            GhostButton(
              text: tr('New project…'),
              onPressed: () async {
                final name = await askForName(
                  context,
                  title: tr('New project'),
                  label: tr('Project name'),
                  placeholder: tr('e.g. Lumen glow serum'),
                  confirmLabel: tr('Create'),
                  initial: app.workspace.suggestedProjectName(),
                );
                if (name == null || !context.mounted) return;
                final project = app.workspace.createProject(name);
                if (context.mounted) Navigator.of(context).pop(project.id);
              },
            ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final project in projects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _ProjectRow(
                        name: project.name,
                        //: %1 is a number of ads
                        detail: tr('%1 ad(s)').arg(project.ads.length),
                        onTap: () => Navigator.of(context).pop(project.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(MqTheme.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: tr('Examples'),
            subtitle: tr(
              'Six ads written the way a person actually talks. Read one, then '
              'write yours the same way.',
            ),
          ),
          const SizedBox(height: MqTheme.gapLarge),
          Wrap(
            spacing: MqTheme.gap,
            runSpacing: MqTheme.gap,
            children: [
              for (final example in AdExample.all)
                _ExampleCard(
                  example: example,
                  onUse: () => _use(context, example),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example, required this.onUse});

  final AdExample example;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: 420,
      padding: const EdgeInsets.all(MqTheme.gap + 2),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  example.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                example.niche.toUpperCase(),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackOverline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            //: %1 is a product name, %2 who it is for
            tr('%1 · %2').arg(example.productName).arg(example.audience),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mq.surfaceSecondary,
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
              border: Border.all(color: mq.borderSubtle),
            ),
            child: Text(
              example.script,
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                height: MqTheme.lineBody,
              ),
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          Row(
            children: [
              GhostButton(text: tr('Use this example'), onPressed: onUse),
              const SizedBox(width: 8),
              GhostButton(
                text: tr('Copy the text'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: example.script)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.name,
    required this.detail,
    required this.onTap,
  });

  final String name;
  final String detail;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          children: [
            MqIcon('folder-line', size: 17, color: mq.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              detail,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
