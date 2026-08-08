#pragma once

#include <QString>

namespace paths {

// %APPDATA%/MarketQueen, ~/.local/share/MarketQueen, ~/Library/Application Support/...
QString configDir();

// Where generated projects live. User-overridable from the settings page.
QString defaultProjectsDir();

// Creates the directory if needed, returns the absolute path (empty on failure).
QString ensureDir(const QString &path);

// A filesystem-safe slug for project folder names.
QString slugify(const QString &text, int maxLength = 40);

} // namespace paths
