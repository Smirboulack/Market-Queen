import '../core/pricing.dart';
import '../i18n/translator.dart';

/// Turns the numbers [Pricing] hands back into text.
///
/// It lives in the UI layer rather than the engine so every label goes through
/// [tr] and picks up a language switch like the rest of the interface.
class Format {
  Format._();

  /// Prices span three orders of magnitude, from a third of a cent for a
  /// Whisper pass to a few dollars for a long clip. Fixed two decimals would
  /// print the cheap steps as "$0.00", which reads as free.
  static String money(double? amount) {
    if (amount == null || amount.isNaN) return '';
    if (amount == 0) return r'$0';
    if (amount < 0.01) return '\$${amount.toStringAsFixed(3)}';
    return '\$${amount.toStringAsFixed(2)}';
  }

  /// The same, marked as the estimate it is.
  static String estimated(double? amount) {
    final text = money(amount);
    //: Prefix meaning "approximately". %1 is a price like $1.10
    return text.isEmpty ? '' : tr('~%1').arg(text);
  }

  /// Pipeline steps, in the order they run. Matches [Pipeline.stepLabel].
  static String stepLabel(String step) => switch (step) {
        'script' => tr('Script'),
        'voice' => tr('Voice-over'),
        'frames' => tr('Frames'),
        'video' => tr('Shots'),
        'captions' => tr('Subtitles'),
        _ => step,
      };

  /// Extra context worth the horizontal space. How many shots the ad is cut
  /// into, and how many seconds of video that buys, are what move the total; a
  /// few hundred characters of speech does not.
  static String unitsLabel(double units, String unit) => switch (unit) {
        //: %1 is a number of seconds
        'second' => tr('%1 s').arg(units.round()),
        //: %1 is a number of images
        'image' => tr('%1 x').arg(units.round()),
        _ => '',
      };

  /// What one unit of a model costs, for the model picker.
  static String unitPriceLabel(UnitPrice? price) {
    if (price == null) return '';
    final value = money(price.amount);
    return switch (price.unit) {
      //: Price per second of generated video
      'second' => tr('%1/s').arg(value),
      //: Price per generated image
      'image' => tr('%1/image').arg(value),
      //: Price per 1000 characters of speech
      'kchars' => tr('%1/1k chars').arg(value),
      //: Price per minute of audio
      'minute' => tr('%1/min').arg(value),
      //: Price per million output tokens
      'tokens' => tr('%1/1M out').arg(value),
      _ => '',
    };
  }
}
