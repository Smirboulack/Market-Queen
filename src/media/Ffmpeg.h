#pragma once

#include "providers/ProviderTask.h"

#include <QProcess>
#include <QStringList>

namespace ffmpeg {

// Looks for ffmpeg: the configured path first, then PATH, then the usual
// install locations. Returns an empty string when it is nowhere to be found.
QString resolve(const QString &configuredPath);

// Seconds parsed out of an ffmpeg "Duration: 00:00:12.34" banner, or -1.
double parseDuration(const QString &log);

// Escapes a filename for use inside a filtergraph argument.
QString escapeFilterPath(const QString &fileName);

} // namespace ffmpeg

// Runs one ffmpeg command. Result: { stderr: QString, exitCode: int }.
class FfmpegTask : public ProviderTask
{
    Q_OBJECT

public:
    FfmpegTask(const QString &executable, const QStringList &arguments,
               const QString &workingDirectory, QObject *parent = nullptr);

    // ffmpeg -i <file> exits non-zero when there is no output file; probing
    // uses that on purpose.
    void setIgnoreExitCode(bool ignore) { m_ignoreExitCode = ignore; }

    void cancel() override;

protected:
    void start() override;

    // What succeed() reports once the process exits. Subclasses extend it.
    virtual QVariantMap buildResult(int exitCode) const;

    QString m_executable;
    QStringList m_arguments;
    QString m_workingDirectory;
    bool m_ignoreExitCode = false;
    QProcess *m_process = nullptr;
    QString m_log;
};

// Reads the duration of a media file. Result adds { duration: double }.
class FfmpegProbeTask : public FfmpegTask
{
    Q_OBJECT

public:
    FfmpegProbeTask(const QString &executable, const QString &mediaPath, QObject *parent = nullptr);

protected:
    QVariantMap buildResult(int exitCode) const override;
};
