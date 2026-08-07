#include "Ffmpeg.h"

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>

#include <cmath>

namespace ffmpeg {

QString resolve(const QString &configuredPath)
{
    if (!configuredPath.isEmpty() && QFileInfo(configuredPath).isExecutable())
        return configuredPath;

    const QString found = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (!found.isEmpty())
        return found;

    static const QStringList candidates = {
#ifdef Q_OS_WIN
        QStringLiteral("C:/ffmpeg/bin/ffmpeg.exe"),
        QStringLiteral("C:/Program Files/ffmpeg/bin/ffmpeg.exe"),
#else
        QStringLiteral("/usr/bin/ffmpeg"),
        QStringLiteral("/usr/local/bin/ffmpeg"),
        QStringLiteral("/opt/homebrew/bin/ffmpeg"),
        QStringLiteral("/snap/bin/ffmpeg"),
#endif
    };
    for (const QString &candidate : candidates) {
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }
    return {};
}

double parseDuration(const QString &log)
{
    static const QRegularExpression re(
        QStringLiteral("Duration:\\s*(\\d+):(\\d{2}):(\\d{2})\\.(\\d+)"));
    const QRegularExpressionMatch match = re.match(log);
    if (!match.hasMatch())
        return -1.0;

    const QString fraction = match.captured(4);
    return match.captured(1).toInt() * 3600.0 + match.captured(2).toInt() * 60.0
        + match.captured(3).toInt()
        + fraction.toDouble() / std::pow(10.0, fraction.size());
}

QString escapeFilterPath(const QString &fileName)
{
    // Inside a filtergraph, ':' separates options and '\' escapes; both appear
    // in Windows paths. Callers should pass a bare file name and set the
    // process working directory, but keep this safe either way.
    QString escaped = fileName;
    escaped.replace(QLatin1Char('\\'), QLatin1String("/"));
    escaped.replace(QLatin1Char(':'), QLatin1String("\\\\:"));
    escaped.replace(QLatin1Char('\''), QLatin1String("\\\\'"));
    return escaped;
}

} // namespace ffmpeg

FfmpegTask::FfmpegTask(const QString &executable, const QStringList &arguments,
                       const QString &workingDirectory, QObject *parent)
    : ProviderTask(parent)
    , m_executable(executable)
    , m_arguments(arguments)
    , m_workingDirectory(workingDirectory)
{
}

void FfmpegTask::start()
{
    if (m_executable.isEmpty()) {
        fail(tr("FFmpeg was not found. Install it, or set its path in Settings."));
        return;
    }

    m_process = new QProcess(this);
    m_process->setProgram(m_executable);
    m_process->setArguments(m_arguments);
    if (!m_workingDirectory.isEmpty())
        m_process->setWorkingDirectory(m_workingDirectory);
    m_process->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_process, &QProcess::readyRead, this, [this]() {
        m_log += QString::fromLocal8Bit(m_process->readAll());
        // Keep the tail only: a long encode prints thousands of progress lines.
        if (m_log.size() > 64'000)
            m_log = m_log.right(32'000);
    });

    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            fail(tr("Could not run FFmpeg (%1).").arg(m_executable));
    });

    connect(m_process, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus status) {
                m_log += QString::fromLocal8Bit(m_process->readAll());

                if (isCancelled() || isFinished())
                    return;

                if (status == QProcess::CrashExit) {
                    fail(tr("FFmpeg stopped unexpectedly."));
                    return;
                }
                if (exitCode != 0 && !m_ignoreExitCode) {
                    // The last lines carry the actual reason.
                    const QStringList lines = m_log.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                    const QString tail = lines.mid(qMax(0, int(lines.size()) - 4))
                                             .join(QLatin1Char(' '))
                                             .simplified();
                    fail(tr("FFmpeg failed (exit %1). %2").arg(exitCode).arg(tail));
                    return;
                }

                succeed(buildResult(exitCode));
            });

    m_process->start();
}

QVariantMap FfmpegTask::buildResult(int exitCode) const
{
    return {{QStringLiteral("stderr"), m_log}, {QStringLiteral("exitCode"), exitCode}};
}

void FfmpegTask::cancel()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(2000);
    }
    ProviderTask::cancel();
}

FfmpegProbeTask::FfmpegProbeTask(const QString &executable, const QString &mediaPath,
                                 QObject *parent)
    : FfmpegTask(executable, {QStringLiteral("-hide_banner"), QStringLiteral("-i"), mediaPath}, {},
                 parent)
{
    setIgnoreExitCode(true);
}

QVariantMap FfmpegProbeTask::buildResult(int exitCode) const
{
    QVariantMap result = FfmpegTask::buildResult(exitCode);
    result.insert(QStringLiteral("duration"), ffmpeg::parseDuration(m_log));
    return result;
}
