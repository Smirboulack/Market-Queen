import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/version.dart';
import '../i18n/translator.dart';
import 'brand.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';

/// One item in the release notes.
class NewsItem {
  const NewsItem({
    required this.version,
    required this.date,
    required this.title,
    required this.body,
  });

  /// The release it landed in. Shown as a tag, so somebody who has not updated
  /// can tell what they are and are not looking at.
  final String version;

  /// "yyyy-MM-dd", written out rather than parsed: these are fixed points in
  /// the past and formatting them per locale is not worth a date library.
  final String date;

  final String title;
  final String body;
}

/// Where the app opens.
///
/// It used to open straight into the studio, which meant the first thing a new
/// install showed was an empty canvas with a prompt bar under it and no
/// indication that any of it needed an API key first. A home screen is not
/// decoration here: this app does nothing at all until three decisions have
/// been made -- what to make, and which accounts pay for it -- and this is the
/// one page that can say so.
///
/// Two things and no more. What changed, because a tool people leave and come
/// back to has to be able to say what moved while they were gone. And the three
/// ways in, as cards big enough to be the obvious next click.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.app,
    required this.onCreateUgc,
    required this.onStoryboard,
    required this.onModels,
  });

  final AppState app;

  final VoidCallback onCreateUgc;
  final VoidCallback onStoryboard;
  final VoidCallback onModels;

  /// The release notes, newest first.
  ///
  /// Written here rather than fetched. The app talks to nobody but the model
  /// providers the user pays for, and phoning a server of ours on every launch
  /// to deliver three paragraphs would be the first exception to that -- along
  /// with everything an exception brings: a privacy claim to qualify, a
  /// failure state to draw, an offline case to handle. A list in the build is
  /// none of those things and says the same words.
  /// A getter rather than a `const` list, so the words go through [tr] and a
  /// language switch reaches them like everything else on screen.
  static List<NewsItem> get news => [
    NewsItem(
      version: '0.1.0',
      date: '2026-08-16',
      title: tr('Every generation now shows what it cost'),
      body: tr(
        'Hover a result in the feed and it says which model made it, the '
        'frame that came back, how long the clip runs, and what your account '
        'was charged. Where the provider reports its own usage the figure is '
        'exact rather than an estimate.',
      ),
    ),
    NewsItem(
      version: '0.1.0',
      date: '2026-08-16',
      title: tr('BytePlus pricing is now per resolution'),
      body: tr(
        'Seedance is billed by output token, so the same five seconds costs '
        'four times as much at 1080p as at 480p. The estimate now follows the '
        'resolution and the soundtrack switch instead of quoting one figure '
        'for all of them.',
      ),
    ),
    NewsItem(
      version: '0.1.0',
      date: '2026-08-16',
      title: tr('Ads without projects'),
      body: tr(
        'There is no folder to make first any more. Create UGC opens onto '
        'your ads the way a chat app opens onto conversations, and a new one '
        'is a single click.',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(MqTheme.pagePadding),
      child: Center(
        child: ConstrainedBox(
          // The same column the rest of the app is capped to, so Home and the
          // studio are one page width rather than two.
          constraints: const BoxConstraints(maxWidth: MqTheme.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Welcome(),
              const SizedBox(height: MqTheme.gapLarge + 8),
              _Ways(
                onCreateUgc: onCreateUgc,
                onStoryboard: onStoryboard,
                onModels: onModels,
              ),
              const SizedBox(height: MqTheme.gapLarge + 12),
              const _News(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark, the name, and one sentence about what the thing is for.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const BrandMark(size: 64),
        const SizedBox(width: MqTheme.gap + 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Welcome to Market Queen'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontHeading,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackHeading,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('UGC ads, made with your own API keys. Nothing is generated '
                    'until you ask for it, and every price you see is what your '
                    'own accounts will be billed.'),
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontBody,
                  height: MqTheme.lineBody,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The three ways in, as cards.
///
/// In the order the work happens: write and shoot an ad, plan one shot by
/// shot, or go and set up the accounts that pay for either. The third is last
/// and is not dressed as an afterthought -- on a fresh install it is the only
/// one that leads anywhere.
class _Ways extends StatelessWidget {
  const _Ways({
    required this.onCreateUgc,
    required this.onStoryboard,
    required this.onModels,
  });

  final VoidCallback onCreateUgc;
  final VoidCallback onStoryboard;
  final VoidCallback onModels;

  /// Below this the three sit one above the other rather than shrinking into
  /// three columns too narrow to hold a sentence.
  static const double _stackBelow = 760;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _WayCard(
        icon: 'clapperboard-line',
        title: tr('Create UGC'),
        body: tr('Write the script, cast an actor, and shoot the ad.'),
        action: tr('Start an ad'),
        onTap: onCreateUgc,
        primary: true,
      ),
      _WayCard(
        icon: 'layout-line',
        title: tr('Storyboard'),
        body: tr('Plan an ad shot by shot before you spend anything on it.'),
        action: tr('Open storyboards'),
        onTap: onStoryboard,
      ),
      _WayCard(
        icon: 'sound-module-line',
        title: tr('Models'),
        body: tr('Add your API keys and pick which models you want offered.'),
        action: tr('Set up the models'),
        onTap: onModels,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; ++i) ...[
                if (i > 0) const SizedBox(height: MqTheme.gap),
                cards[i],
              ],
            ],
          );
        }

        // IntrinsicHeight, not `CrossAxisAlignment.stretch`. Stretch on a Row
        // stretches the *cross* axis, which is the vertical one -- and this
        // sits in a scroll view, where vertical is unbounded, so it asks its
        // children to be infinitely tall and the layout throws. Measuring the
        // tallest card first is the way to get three equal ones here.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; ++i) ...[
                if (i > 0) const SizedBox(width: MqTheme.gap),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WayCard extends StatelessWidget {
  const _WayCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
    this.primary = false,
  });

  final String icon;
  final String title;
  final String body;

  /// The words on the link at the foot of the card. Different per card on
  /// purpose: three cards all saying "Open" is three cards you have to read the
  /// heading of twice.
  final String action;

  final VoidCallback onTap;

  /// The one the app is for. It carries a heavier outline -- not a filled
  /// button, because the other two are not lesser, only later.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.all(MqTheme.gapLarge),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: primary || states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // Min, so the card lays out the same whether its parent measured a
          // height for it -- the three-across row does -- or handed it an
          // unbounded one, which is what the stacked layout inside the scroll
          // view does. The frames still come out equal in the row; only the
          // ink inside them is top-aligned.
          mainAxisSize: MainAxisSize.min,
          children: [
            MqIcon(
              icon,
              size: 22,
              color: states.active ? mq.textPrimary : mq.textSecondary,
            ),
            const SizedBox(height: MqTheme.gap + 2),
            Text(
              title,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontTitle,
                fontWeight: FontWeight.w600,
                letterSpacing: MqTheme.trackTitle,
                height: MqTheme.lineTight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                height: MqTheme.lineBody,
              ),
            ),
            const SizedBox(height: MqTheme.gap + 2),
            Row(
              children: [
                Text(
                  action,
                  style: TextStyle(
                    color: mq.primaryText,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w500,
                    decoration: states.active
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: mq.primaryText,
                  ),
                ),
                const SizedBox(width: 4),
                MqIcon(
                  'arrow-right-s-line',
                  size: 16,
                  color: mq.primaryText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What changed, newest first.
class _News extends StatelessWidget {
  const _News();

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('What\'s new'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontTitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackTitle,
                ),
              ),
            ),
            Text(
              //: %1 is a version number such as "0.1.0"
              tr('You are on v%1').arg(appVersion),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: MqTheme.gap),
        Container(
          decoration: BoxDecoration(
            color: mq.surface,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(color: mq.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < HomePage.news.length; ++i) ...[
                // Hairlines between entries rather than around each: the block
                // is one list, not a stack of cards.
                if (i > 0) Container(height: 1, color: mq.borderSubtle),
                _NewsRow(item: HomePage.news[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: const EdgeInsets.all(MqTheme.gapLarge - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    fontWeight: FontWeight.w600,
                    height: MqTheme.lineTight,
                  ),
                ),
              ),
              const SizedBox(width: MqTheme.gap),
              // The version and the date, quiet and monospaced-in-figures so a
              // column of them lines up.
              Text(
                'v${item.version}  ·  ${item.date}',
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            item.body,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
        ],
      ),
    );
  }
}
