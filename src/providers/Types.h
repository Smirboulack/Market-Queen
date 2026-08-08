#pragma once

#include <QString>
#include <QStringList>

// Requests handed to providers. Everything a provider needs is in the struct:
// providers never read settings or touch the filesystem themselves.
namespace prov {

struct ScriptRequest {
    // Two jobs, one transport. Writing a script and directing one the user
    // already wrote differ only in the prompt and are otherwise the same call
    // to the same three providers, returning the same `shots` shape.
    enum class Mode {
        WriteScript,   // the model writes the words and the visuals
        DirectVisuals, // the words are the user's; the model only frames them
    };

    QString apiKey;
    QString model;
    QString baseUrl;              // optional override (OpenAI-compatible gateways)
    Mode mode = Mode::WriteScript;

    // DirectVisuals only: one entry per scene, in order.
    QStringList lines;
    QStringList kinds;            // "talking" or "broll"
    QString actorBrief;
    QString actorDecor;
    QString directionRules;       // the house style, from casting.json
    QString productName;
    QString productDescription;
    QString audience;
    QString tone;
    QString language;
    QString avatarBrief;          // who is speaking on camera
    QString extraInstructions;
    QString referenceImageDataUri; // product photo, passed to vision-capable models
    int durationSeconds = 20;
    int shotCount = 4;            // how many camera setups to write the ad across
};

struct ImageRequest {
    QString apiKey;
    QString model;
    QString prompt;
    QString aspectRatio;          // "9:16", "1:1", "16:9"
    QString referenceImageDataUri;
};

struct VideoRequest {
    QString apiKey;
    QString model;
    QString prompt;
    QString imageDataUri;         // first frame
    QString aspectRatio;
    int durationSeconds = 5;
};

struct VoiceRequest {
    QString apiKey;
    QString model;
    QString voiceId;
    QString text;
    double speed = 1.0;
    // ElevenLabs voice_settings. The defaults are the values that used to be
    // hardcoded in the provider, so a request that leaves them alone behaves
    // exactly as it did before the booth exposed them.
    double stability = 0.45;
    double similarity = 0.8;
    double style = 0.35;
};

// Instant voice cloning from the user's own recordings. This creates a
// permanent voice on their provider account, so it is never implicit.
struct VoiceCloneRequest {
    QString apiKey;
    QString name;
    QString description;
    QStringList samplePaths;
};

struct TranscribeRequest {
    QString apiKey;
    QString model;
    QString audioPath;
    QString language;
};

} // namespace prov
