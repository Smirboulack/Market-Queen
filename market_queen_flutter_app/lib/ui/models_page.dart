import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'brand.dart';
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/key_field.dart';

/// Where the app is configured: five tabs, one per kind of generation.
///
/// The shape is doing three jobs that used to be spread across two screens and
/// a scroll of about four thousand pixels.
///
/// **Tabs, not sections.** Seventeen providers stacked on one page is not a
/// page anybody reads; it is a page people give up on. Only one shelf is on
/// screen at a time, and the row of tabs is both the map and the way around.
///
/// **One card per account, not per catalogue entry.** The registry splits
/// providers by what the pipeline asks for, so Bria is two entries -- pictures
/// and enlarging -- and Ideogram is another two. Drawn straight, the Images tab
/// listed "Bria" twice with a key field under each, which is one account and
/// therefore one key. Cards are grouped by credential and the entries inside
/// become labelled rows.
///
/// **The key sits with what it unlocks.** Nothing on a page of key fields ever
/// said which models a key switched on, and it is not guessable: one OpenAI key
/// covers the writer, the stills, Sora and the voice-over, while LTX's covers a
/// single row of one tab. Here the key is a line inside the card whose models
/// it pays for, and once it is filled in it collapses to that one line.
///
/// Everything is on by default, and a model added in a future release arrives
/// switched on, because the stored setting is the *hidden* set.
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.app});

  final AppState app;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

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
                    for (final card in cards) ...[
                      _AccountCard(app: widget.app, card: card),
                      const SizedBox(height: MqTheme.gap),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// One card per account on this shelf, in the order the registry lists their
  /// providers, each carrying every catalogue entry that account pays for here.
  List<_Card> _cardsFor(PanelEntry panel) {
    final registry = widget.app.registry;
    final byCredential = <String, List<ProviderEntry>>{};
    final order = <String>[];

    for (final provider in registry.providersForPanel(panel.id)) {
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

  Iterable<CredentialEntry> _credentials(PanelEntry panel) =>
      app.registry.credentialsForPanel(panel.id);

  int _total(PanelEntry panel) => _credentials(panel).length;

  int _ready(PanelEntry panel) => _credentials(panel)
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
// One account
// ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.app, required this.card});

  final AppState app;
  final _Card card;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final credential = card.credential;

    final ids = card.modelIds;
    final hasKey =
        credential != null && app.settings.hasApiKey(credential.id);

    // Nothing on this card can be chosen until the account is set up, so
    // nothing on it is switchable either. Ticking a model on an account with
    // no key put an entry in the composer's menu that could only ever fail at
    // send -- a paid-looking choice that was never available. An account with
    // no credential at all is a case the catalogue does not have today; it
    // stays unlocked rather than being locked forever by a null.
    final unlocked = credential == null || hasKey;

    // Counted against the same rule the chips are drawn by, so a locked card
    // does not claim five models are on above five that are visibly not. The
    // stored set is left alone: a key removed and put back finds the same
    // shortlist it had.
    final shown = unlocked
        ? ids.where((id) => app.settings.modelShown(_ownerOf(id), id)).length
        : 0;

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
            child: _header(context, hasKey, unlocked, shown, ids),
          ),
          if (credential != null) ...[
            const SizedBox(height: 12),
            // The key gets its own band, a step down from the card, so it reads
            // as the thing the models below it depend on rather than as another
            // row of them.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: mq.surfaceSecondary,
                border: Border.symmetric(
                  horizontal: BorderSide(color: mq.borderSubtle),
                ),
              ),
              child: KeyField(app: app, credential: credential),
            ),
          ] else
            const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < card.providers.length; ++i) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _Group(
                    app: app,
                    provider: card.providers[i],
                    unlocked: unlocked,
                    // The heading only earns its line when the card holds more
                    // than one thing: "Images" over the only row on the card
                    // says nothing the tab has not already said.
                    named: card.providers.length > 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Which catalogue entry a model id belongs to. Ids are unique inside a card,
  /// so the first match is the right one.
  String _ownerOf(String modelId) {
    for (final provider in card.providers) {
      for (final model in provider.models) {
        if (model.id == modelId) return provider.id;
      }
    }
    return card.providers.first.id;
  }

  Widget _header(
    BuildContext context,
    bool hasKey,
    bool unlocked,
    int shown,
    List<String> ids,
  ) {
    final mq = context.mq;
    final credential = card.credential;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The account's mark, with the "there is a key in this one" dot pinned
        // to its corner. The dot used to stand on its own at the head of the
        // row, which made seventeen cards seventeen identical grey headings
        // with a full stop in front of them -- nothing to aim at while looking
        // for the one you came here to set up.
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
                    // Ringed in the card's own surface so it reads as a badge
                    // on the mark rather than as a smudge in the corner of it.
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
              Row(
                children: [
                  Flexible(
                    child: Text(
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
                  ),
                  if (credential != null && credential.free) ...[
                    const SizedBox(width: 8),
                    _Badge(text: tr('Free tier')),
                  ],
                ],
              ),
              // What the key is for is said by the key field, and only while it
              // is open -- which is exactly when you are deciding whether to go
              // and get one. Repeating it over a card you have already set up
              // is a second grey line saying what the models under it already
              // say better.
            ],
          ),
        ),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Text(
                //: %1 is how many models are enabled, %2 how many there are
                tr('%1 of %2').arg(shown).arg(ids.length),
                style: TextStyle(
                  color: unlocked ? mq.textTertiary : mq.textDisabled,
                  fontSize: MqTheme.fontSmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              MqLink(
                text: shown == ids.length ? tr('None') : tr('All'),
                onPressed: !unlocked
                    ? null
                    : () {
                        final hide = shown == ids.length;
                        for (final provider in card.providers) {
                          app.settings.setProviderModelsHidden(
                            provider.id,
                            [for (final model in provider.models) model.id],
                            hide,
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet, bordered tag. Used for the one claim on this page that can cost
/// somebody money if it is wrong, so it is drawn to be read rather than to
/// decorate.
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: mq.successSubtle,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mq.successText,
          fontSize: MqTheme.fontMicro,
          fontWeight: FontWeight.w600,
          letterSpacing: MqTheme.trackSmall,
        ),
      ),
    );
  }
}

/// One catalogue entry inside an account card: its note, and its models.
class _Group extends StatelessWidget {
  const _Group({
    required this.app,
    required this.provider,
    required this.named,
    required this.unlocked,
  });

  final AppState app;
  final ProviderEntry provider;

  /// Whether to caption the row with what it is for.
  final bool named;

  /// False until the account above has a key. The models are still listed --
  /// what an account offers is exactly what you are deciding about while you
  /// go and get one -- but none of them can be ticked.
  final bool unlocked;

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
        if (named) ...[
          Text(
            categoryLabel(provider.category).toUpperCase(),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontMicro,
              fontWeight: FontWeight.w600,
              letterSpacing: MqTheme.trackOverline,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (provider.note.isNotEmpty) ...[
          Text(
            provider.note,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final model in provider.models)
              _ModelChip(
                app: app,
                providerId: provider.id,
                model: model,
                unlocked: unlocked,
              ),
          ],
        ),
      ],
    );
  }
}

/// One model: its name, its unit price, and whether the composer may offer it.
class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.app,
    required this.providerId,
    required this.model,
    this.unlocked = true,
  });

  final AppState app;
  final String providerId;
  final ModelEntry model;

  /// Whether the account this model is bought from has a key yet. Without one
  /// the chip is inert: it still says what the model is and what it costs --
  /// which is what you are weighing while deciding whether to go and sign up
  /// -- but it cannot be ticked, because a ticked model with no key behind it
  /// is an entry in the composer's menu that can only fail at send.
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final on = unlocked && app.settings.modelShown(providerId, model.id);
    final price = Format.unitPriceLabel(app.pricing.unitPrice(model.id));

    return Pressable(
      onTap: unlocked
          ? () => app.settings.setModelHidden(providerId, model.id, on)
          : null,
      tooltip: unlocked ? '' : tr('Add this account\'s key to switch it on.'),
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.fromLTRB(8, 6, 11, 6),
        decoration: BoxDecoration(
          // A chip that is switched off is still a chip you can switch on, so
          // it keeps its outline. Only the fill and the ink recede.
          color: on
              ? (states.active ? mq.surfaceActive : mq.surfaceSecondary)
              : (states.active ? mq.surfaceHover : Colors.transparent),
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: !unlocked
                ? mq.borderSubtle
                : on
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A filled square with a tick, or an empty outline. The state is
            // the point of the row, so it leads. Locked, it is a padlock
            // instead: an empty box invites a click that does nothing.
            SizedBox(
              width: 15,
              height: 15,
              child: unlocked
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? mq.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: on ? mq.primary : mq.borderStrong,
                        ),
                      ),
                      child: on
                          ? MqIcon('check-line', size: 11, color: mq.onPrimary)
                          : null,
                    )
                  : MqIcon('lock-line', size: 13, color: mq.textDisabled),
            ),
            const SizedBox(width: 8),
            Text(
              model.label,
              style: TextStyle(
                color: !unlocked
                    ? mq.textDisabled
                    : on
                    ? mq.textPrimary
                    : mq.textTertiary,
                fontSize: MqTheme.fontLabel,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            // The price is what the model costs once any free quota is gone, so
            // the two belong side by side rather than one instead of the other:
            // "Free tier" alone would read as "this is never billed".
            if (model.isFree) ...[
              const SizedBox(width: 8),
              Text(
                tr('Free tier'),
                style: TextStyle(
                  color: on ? mq.successText : mq.textDisabled,
                  fontSize: MqTheme.fontMicro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (price.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                price,
                style: TextStyle(
                  color: on ? mq.textTertiary : mq.textDisabled,
                  fontSize: MqTheme.fontSmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
