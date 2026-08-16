import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'brand.dart';
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/key_field.dart';

/// Where the accounts live: two shelves, and neither of them is a shortlist.
///
/// **Keys.** One field per account, laid out two across, each saying what the
/// key buys and whether it works. It is the only page in the app that has to
/// be visited before anything can be generated at all.
///
/// **Information.** What each account charges and which of its models the app
/// uses. It replaced five pages of tick-boxes: those let anyone switch a model
/// off, which sounds like control and mostly meant a shelf could be emptied by
/// accident. Which models are worth offering is a judgement that wants the
/// benchmarks and the prices of a hundred endpoints in front of you; which of
/// the offered ones a given generation runs on is a choice made next to the
/// prompt, on the studio bar, where it belongs.
///
/// **One card per account, not per catalogue entry.** The registry splits
/// providers by what the pipeline asks for, so Bria is two entries -- pictures
/// and enlarging -- and Ideogram is another two. Drawn straight that is one
/// account listed twice with a key field under each, which is one account and
/// therefore one key. Cards are grouped by credential and the entries inside
/// become labelled rows.
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.app});

  final AppState app;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

/// The shelf that takes keys rather than model choices.
const String _keysPanel = 'keys';

class _ModelsPageState extends State<ModelsPage> {
  String _panelId = Registry.panels.first.id;

  PanelEntry get _panel => Registry.panels.firstWhere(
        (panel) => panel.id == _panelId,
        orElse: () => Registry.panels.first,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Providers come and go with the keys that unlock them, and every tick
      // rewrites the stored set.
      listenable: Listenable.merge([widget.app.settings, widget.app.registry]),
      builder: (context, _) {
        final panel = _panel;
        final cards = _cardsFor(panel);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The header and the tabs do not scroll. Losing the row of tabs off
            // the top of a long shelf is what makes a tabbed page feel like the
            // stack of sections it replaced.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MqTheme.pagePadding,
                MqTheme.pagePadding,
                MqTheme.pagePadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Models'),
                    style: TextStyle(
                      color: context.mq.textPrimary,
                      fontSize: MqTheme.fontHeading,
                      fontWeight: FontWeight.w600,
                      letterSpacing: MqTheme.trackHeading,
                      height: MqTheme.lineTight,
                    ),
                  ),
                  const SizedBox(height: MqTheme.gap + 2),
                  _Tabs(
                    app: widget.app,
                    current: _panelId,
                    onPicked: (id) => setState(() => _panelId = id),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  MqTheme.pagePadding,
                  MqTheme.gapLarge,
                  MqTheme.pagePadding,
                  MqTheme.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(panel.subtitle),
                      style: TextStyle(
                        color: context.mq.textSecondary,
                        fontSize: MqTheme.fontBody,
                      ),
                    ),
                    const SizedBox(height: MqTheme.gapLarge),
                    if (panel.id == _keysPanel)
                      _KeyGrid(app: widget.app, cards: cards)
                    else
                      _InfoList(app: widget.app, cards: cards),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// One card per account, in the order the registry lists their providers,
  /// each carrying every catalogue entry that account sells.
  ///
  /// Both shelves are about accounts rather than about one kind of generation,
  /// so both list all of them: the keys shelf so nothing is unreachable, the
  /// information shelf so an account's models are read in one place instead of
  /// hunted across five.
  List<_Card> _cardsFor(PanelEntry panel) {
    final registry = widget.app.registry;
    final byCredential = <String, List<ProviderEntry>>{};
    final order = <String>[];

    for (final provider in registry.entries) {
      final key = provider.credential;
      if (!byCredential.containsKey(key)) {
        byCredential[key] = [];
        order.add(key);
      }
      byCredential[key]!.add(provider);
    }

    final credentials = {
      for (final credential in registry.credentials()) credential.id: credential,
    };

    return [
      for (final id in order)
        _Card(credential: credentials[id], providers: byCredential[id]!),
    ];
  }
}

/// One account and everything it pays for on this shelf.
class _Card {
  const _Card({required this.credential, required this.providers});

  final CredentialEntry? credential;
  final List<ProviderEntry> providers;

  /// The account's own name where there is one. A provider with no credential
  /// -- there are none today -- falls back to its own label.
  String get label => credential?.label ?? providers.first.label;

  /// Every model on the card.
  List<String> get modelIds => [
        for (final provider in providers)
          for (final model in provider.models) model.id,
      ];
}

// ---------------------------------------------------------------------------
// The tab row
// ---------------------------------------------------------------------------

/// The five shelves, as one segmented row.
///
/// A tab carries a count of the accounts on it that have a key, which is the
/// one number that answers "what is left to set up" without opening anything.
/// It reads "3/4", and it is deliberately not a warning colour: a shelf you
/// have not funded is a choice, not a fault.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.app,
    required this.current,
    required this.onPicked,
  });

  final AppState app;
  final String current;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius + 4),
        border: Border.all(color: mq.border),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final panel in Registry.panels)
            _Tab(
              panel: panel,
              selected: panel.id == current,
              ready: _ready(panel),
              total: _total(panel),
              onTap: () => onPicked(panel.id),
            ),
        ],
      ),
    );
  }

  /// Both shelves are about the same set of accounts, so both carry the same
  /// count: how many of them are set up.
  int _total(PanelEntry panel) => app.registry.credentials().length;

  int _ready(PanelEntry panel) => app.registry
      .credentials()
      .where((credential) => app.settings.hasApiKey(credential.id))
      .length;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.panel,
    required this.selected,
    required this.ready,
    required this.total,
    required this.onTap,
  });

  final PanelEntry panel;
  final bool selected;
  final int ready;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // The tabs touch, so hover snaps both ways and only one is ever lit.
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) {
        // Filled with ink when it is the one you are on. It is the strongest
        // contrast a greyscale interface has, and a tab row is exactly where
        // "you are here" has to be unmistakable.
        final fill = selected
            ? mq.primary
            : states.pressed
                ? mq.surfaceActive
                : states.hovered
                    ? mq.surfaceHover
                    : Colors.transparent;
        final ink = selected
            ? mq.onPrimary
            : states.active
                ? mq.textPrimary
                : mq.textSecondary;

        return AnimatedContainer(
          duration: states.duration,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MqIcon(panel.icon, size: 16, color: ink),
              const SizedBox(width: 8),
              Text(
                tr(panel.title),
                style: TextStyle(
                  color: ink,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: MqTheme.trackSmall,
                ),
              ),
              if (total > 0) ...[
                const SizedBox(width: 8),
                Text(
                  //: %1 is how many providers on this tab have a key, %2 how
                  //: many there are
                  tr('%1/%2').arg(ready).arg(total),
                  style: TextStyle(
                    color: selected
                        ? mq.onPrimary.withValues(alpha: 0.65)
                        : mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The keys shelf
// ---------------------------------------------------------------------------

/// The accounts, two across.
///
/// A key is a 40-pixel box, and a 40-pixel box stretched over a 1180-pixel
/// column is mostly empty rule. Two per row puts the field at about the width
/// of the thing it holds and halves the scrolling, and the cards line up in a
/// grid you can scan for the empty ones rather than a ladder you read.
class _KeyGrid extends StatelessWidget {
  const _KeyGrid({required this.app, required this.cards});

  final AppState app;
  final List<_Card> cards;

  /// Below this, one across: two columns of a narrow window would leave the
  /// field too short to show a key.
  static const double _twoColumnsAbove = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= _twoColumnsAbove ? 2 : 1;
        final width =
            (constraints.maxWidth - MqTheme.gap * (columns - 1)) / columns;

        return Wrap(
          spacing: MqTheme.gap,
          runSpacing: MqTheme.gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _KeyCard(app: app, card: card),
              ),
          ],
        );
      },
    );
  }
}

/// One account: its mark, its name, its key, and what the key buys.
class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.app, required this.card});

  final AppState app;
  final _Card card;

  /// "Writing · Images · Video", the shelves this account sells on.
  String get _sells {
    final seen = <String>[];
    for (final provider in card.providers) {
      final label = _InfoGroup.categoryLabel(provider.category);
      if (!seen.contains(label)) seen.add(label);
    }
    return seen.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final credential = card.credential;
    if (credential == null) return const SizedBox.shrink();

    final hasKey = app.settings.hasApiKey(credential.id);

    return Container(
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
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProviderMark(credential: credential.id, size: 26),
                    // The one thing worth seeing from across the grid: which
                    // accounts are set up.
                    PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: hasKey ? mq.success : mq.borderStrong,
                          shape: BoxShape.circle,
                          border: Border.all(color: mq.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textPrimary,
                        fontSize: MqTheme.fontLabel,
                        fontWeight: FontWeight.w600,
                        letterSpacing: MqTheme.trackTitle,
                        height: MqTheme.lineTight,
                      ),
                    ),
                    Text(
                      _sells,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontMicro,
                        height: MqTheme.lineTight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MqTheme.gap),
          KeyField(app: app, credential: credential),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The information shelf
// ---------------------------------------------------------------------------

/// What each account is, what it charges, and which of its models the app
/// uses.
///
/// This shelf replaced five pages of tick-boxes. The tick-boxes let anyone
/// switch a model off, which sounds like control and was mostly a way to
/// break the app quietly: hide the wrong four and a shelf has nothing left on
/// it. What people actually wanted from that page was the thing underneath --
/// which models are here, what do they cost, whose bill is it -- and that is
/// a page you read rather than one you operate.
class _InfoList extends StatelessWidget {
  const _InfoList({required this.app, required this.cards});

  final AppState app;
  final List<_Card> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final card in cards) ...[
          _InfoCard(app: app, card: card),
          const SizedBox(height: MqTheme.gap),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.app, required this.card});

  final AppState app;
  final _Card card;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final credential = card.credential;
    final hasKey = credential != null && app.settings.hasApiKey(credential.id);

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ProviderMark(credential: credential?.id ?? ''),
                      PositionedDirectional(
                        end: -2,
                        bottom: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: hasKey ? mq.success : mq.borderStrong,
                            shape: BoxShape.circle,
                            border: Border.all(color: mq.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontTitle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: MqTheme.trackTitle,
                          height: MqTheme.lineTight,
                        ),
                      ),
                      if (credential != null && credential.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          credential.note,
                          style: TextStyle(
                            color: mq.textSecondary,
                            fontSize: MqTheme.fontSmall,
                            height: MqTheme.lineBody,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Text(
                        hasKey ? tr('Key added') : tr('No key yet'),
                        style: TextStyle(
                          color: hasKey ? mq.successText : mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                      if (credential != null) ...[
                        const SizedBox(width: 12),
                        MqLink(
                          text: tr('Pricing'),
                          onPressed: () =>
                              PlatformUtil.openExternal(credential.signupUrl),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < card.providers.length; ++i) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _InfoGroup(app: app, provider: card.providers[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One shelf of one account: what it does, its note, and its models with what
/// each of them costs.
class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.app, required this.provider});

  final AppState app;
  final ProviderEntry provider;

  static String categoryLabel(String category) => switch (category) {
    'text' => tr('Writing'),
    'avatar' => tr('Talking actors'),
    'image' => tr('Images'),
    'upscale' => tr('Enlarging'),
    'video' => tr('Video'),
    'voice' => tr('Voice-over'),
    'captions' => tr('Subtitles'),
    _ => category,
  };

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              categoryLabel(provider.category).toUpperCase(),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontMicro,
                fontWeight: FontWeight.w600,
                letterSpacing: MqTheme.trackOverline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: mq.borderSubtle)),
          ],
        ),
        if (provider.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            provider.note,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final model in provider.models)
              _ModelFact(
                label: model.label,
                price: Format.unitPriceLabel(app.pricing.unitPrice(model.id)),
                isDefault: model.id == provider.defaultModel,
              ),
          ],
        ),
      ],
    );
  }
}

/// One model, as a fact rather than a control.
///
/// Name, price, and whether it is the one a fresh install starts on. Nothing
/// here is pressable: the choice of which model a given generation runs on is
/// made on the studio bar, next to the prompt it applies to.
class _ModelFact extends StatelessWidget {
  const _ModelFact({
    required this.label,
    required this.price,
    required this.isDefault,
  });

  final String label;
  final String price;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: isDefault ? mq.borderStrong : mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: mq.textPrimary,
              fontSize: MqTheme.fontLabel,
              fontWeight: isDefault ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (price.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              price,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (isDefault) ...[
            const SizedBox(width: 8),
            Text(
              tr('default'),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontMicro,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
