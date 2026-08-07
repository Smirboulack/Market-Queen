#pragma once

#include <QByteArray>

// Local-only secret storage.
//
// The API keys never leave the machine, but they should not sit in a plain text
// file either: anything that reads the config directory (a backup tool, a sync
// client, a shared screen) would leak them. We encrypt with ChaCha20 and
// authenticate with HMAC-SHA256, using a key derived from the machine identity.
//
// This protects against casual disclosure, not against someone who already runs
// code as the user -- such an attacker can derive the same key. A real OS
// keychain integration is the follow-up (see README).
namespace crypto {

// 32-byte key derived from the machine + user identity.
QByteArray deviceKey();

// nonce(12) || ciphertext || tag(32), prefixed with a 4-byte magic.
QByteArray seal(const QByteArray &plain, const QByteArray &key);

// Returns an empty array and sets *ok to false when the blob is corrupt or was
// produced on another machine.
QByteArray unseal(const QByteArray &blob, const QByteArray &key, bool *ok = nullptr);

} // namespace crypto
