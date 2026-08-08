pragma Singleton

import QtQuick
import MarketQueen

// Turns the numbers Pricing hands back into text.
//
// It lives in QML rather than C++ so every label goes through qsTr() and picks
// up a language switch like the rest of the interface.
QtObject {
    id: root

    // QML only re-runs a binding on a language switch when qsTr() appears in
    // the binding itself, not when it hides inside a function the binding
    // calls. Reading this property from each function below puts the caller's
    // binding back on the hook.
    readonly property string language: App.translator.currentLabel

    // Prices span three orders of magnitude, from a third of a cent for a
    // Whisper pass to a few dollars for a long clip. Fixed two decimals would
    // print the cheap steps as "$0.00", which reads as free.
    function money(amount) {
        if (amount === undefined || amount === null || isNaN(amount))
            return "";
        if (amount === 0)
            return "$0";
        if (amount < 0.01)
            return "$" + amount.toFixed(3);
        return "$" + amount.toFixed(2);
    }

    // The same, marked as the estimate it is.
    function estimated(amount) {
        void root.language;
        const text = money(amount);
        //: Prefix meaning "approximately". %1 is a price like $1.10
        return text === "" ? "" : qsTr("~%1").arg(text);
    }

    // Pipeline steps, in the order they run. Matches Pipeline::stepLabel.
    function stepLabel(step) {
        void root.language;
        switch (step) {
        case "script":   return qsTr("Script");
        case "voice":    return qsTr("Voice-over");
        case "frames":   return qsTr("Frames");
        case "video":    return qsTr("Shots");
        case "captions": return qsTr("Subtitles");
        default:         return step;
        }
    }

    // Extra context worth the horizontal space. How many shots the ad is cut
    // into, and how many seconds of video that buys, are what move the total;
    // a few hundred characters of speech does not.
    function unitsLabel(units, unit) {
        void root.language;
        switch (unit) {
        //: %1 is a number of seconds
        case "second": return qsTr("%1 s").arg(Math.round(units));
        //: %1 is a number of images
        case "image":  return qsTr("%1 x").arg(Math.round(units));
        default:       return "";
        }
    }

    // What one unit of a model costs, for the model picker.
    function unitPriceLabel(price) {
        void root.language;
        if (!price || price.amount === undefined)
            return "";
        const value = money(price.amount);
        switch (price.unit) {
        //: Price per second of generated video
        case "second": return qsTr("%1/s").arg(value);
        //: Price per generated image
        case "image":  return qsTr("%1/image").arg(value);
        //: Price per 1000 characters of speech
        case "kchars": return qsTr("%1/1k chars").arg(value);
        //: Price per minute of audio
        case "minute": return qsTr("%1/min").arg(value);
        //: Price per million output tokens
        case "tokens": return qsTr("%1/1M out").arg(value);
        default:       return "";
        }
    }
}
