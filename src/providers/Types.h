#pragma once

#include <QString>

// Requests handed to providers. Everything a provider needs is in the struct:
// providers never read settings or touch the filesystem themselves.
namespace prov {

struct ScriptRequest {
    QString apiKey;
    QString model;
    QString baseUrl;              // optional override (OpenAI-compatible gateways)
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
};

struct TranscribeRequest {
    QString apiKey;
    QString model;
    QString audioPath;
    QString language;
};

} // namespace prov
