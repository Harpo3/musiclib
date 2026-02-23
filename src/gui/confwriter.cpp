// confwriter.cpp
// MusicLib Qt GUI — Shell config file reader/writer implementation
// Copyright (c) 2026 MusicLib Project

#include "confwriter.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

// ═════════════════════════════════════════════════════════════
// Construction
// ═════════════════════════════════════════════════════════════

ConfWriter::ConfWriter()
{
}

// ═════════════════════════════════════════════════════════════
// File location
// ═════════════════════════════════════════════════════════════

QString ConfWriter::locateConfigFile() const
{
    // Priority order (matches musiclib_utils.sh::load_config):
    //   1. $MUSICLIB_CONFIG_DIR/musiclib.conf  (env override)
    //   2. $XDG_CONFIG_HOME/musiclib/musiclib.conf
    //   3. ~/musiclib/config/musiclib.conf     (legacy)

    // Check environment override
    QString envDir = QString::fromLocal8Bit(qgetenv("MUSICLIB_CONFIG_DIR"));
    if (!envDir.isEmpty()) {
        QString path = envDir + QStringLiteral("/musiclib.conf");
        if (QFile::exists(path)) {
            return path;
        }
    }

    // XDG path
    QString xdgConfig = QStandardPaths::writableLocation(
        QStandardPaths::GenericConfigLocation);
    QString xdgPath = xdgConfig + QStringLiteral("/musiclib/musiclib.conf");
    if (QFile::exists(xdgPath)) {
        return xdgPath;
    }

    // Legacy path
    QString legacyPath = QDir::homePath()
        + QStringLiteral("/musiclib/config/musiclib.conf");
    if (QFile::exists(legacyPath)) {
        return legacyPath;
    }

    // Not found — return the XDG path as the "would-be" location
    // so save() can create it there.
    return xdgPath;
}

QString ConfWriter::filePath() const
{
    return m_filePath;
}

// ═════════════════════════════════════════════════════════════
// Loading
// ═════════════════════════════════════════════════════════════

bool ConfWriter::loadFromDefaultLocation()
{
    return loadFromFile(locateConfigFile());
}

bool ConfWriter::loadFromFile(const QString &filePath)
{
    m_filePath = filePath;
    m_rawLines.clear();
    m_values.clear();

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream stream(&file);
    while (!stream.atEnd()) {
        QString line = stream.readLine();
        m_rawLines.append(line);

        QString key, val;
        if (parseLine(line, key, val)) {
            m_values[key] = val;
        }
    }

    file.close();
    return true;
}

// ═════════════════════════════════════════════════════════════
// Saving — preserves comments and structure
// ═════════════════════════════════════════════════════════════

bool ConfWriter::save()
{
    return saveToFile(m_filePath);
}

bool ConfWriter::saveToFile(const QString &filePath)
{
    if (filePath.isEmpty()) {
        return false;
    }

    // Ensure the parent directory exists
    QFileInfo fi(filePath);
    QDir().mkpath(fi.absolutePath());

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream stream(&file);

    // Track which keys we've written (to detect new keys that need appending)
    QSet<QString> writtenKeys;

    // Rewrite existing lines, updating values in-place
    for (const QString &rawLine : m_rawLines) {
        QString key, oldVal;
        if (parseLine(rawLine, key, oldVal) && m_values.contains(key)) {
            // This line is a KEY=value assignment — write the current value.
            const QString &newVal = m_values[key];

            // Decide quoting: strings get quotes, numbers and booleans don't.
            bool isNumeric = false;
            newVal.toInt(&isNumeric);
            bool isBool = (newVal == QStringLiteral("true")
                        || newVal == QStringLiteral("false"));

            if (isNumeric || isBool) {
                stream << key << QStringLiteral("=") << newVal;
            } else {
                stream << key << QStringLiteral("=\"") << newVal
                       << QStringLiteral("\"");
            }

            // Preserve inline comment if present in the original line
            // Look for # preceded by whitespace after the value
            static QRegularExpression inlineComment(
                QStringLiteral("\\s+#\\s+.*$"));
            QRegularExpressionMatch match = inlineComment.match(rawLine);
            if (match.hasMatch()) {
                stream << match.captured(0);
            }

            stream << QStringLiteral("\n");
            writtenKeys.insert(key);
        } else {
            // Comment, blank line, or unknown — preserve verbatim
            stream << rawLine << QStringLiteral("\n");
        }
    }

    // Append any new keys that weren't in the original file
    for (auto it = m_values.constBegin(); it != m_values.constEnd(); ++it) {
        if (!writtenKeys.contains(it.key())) {
            const QString &val = it.value();
            bool isNumeric = false;
            val.toInt(&isNumeric);
            bool isBool = (val == QStringLiteral("true")
                        || val == QStringLiteral("false"));

            if (isNumeric || isBool) {
                stream << it.key() << QStringLiteral("=") << val
                       << QStringLiteral("\n");
            } else {
                stream << it.key() << QStringLiteral("=\"") << val
                       << QStringLiteral("\"\n");
            }
        }
    }

    file.close();
    return true;
}

// ═════════════════════════════════════════════════════════════
// Line parsing
// ═════════════════════════════════════════════════════════════

bool ConfWriter::parseLine(const QString &line, QString &key, QString &value) const
{
    // Skip blank lines and comments
    QString trimmed = line.trimmed();
    if (trimmed.isEmpty() || trimmed.startsWith(QLatin1Char('#'))) {
        return false;
    }

    // Match: KEY=value  or  KEY="value"  or  KEY='value'
    // KEY must be a valid shell variable name: [A-Za-z_][A-Za-z0-9_]*
    static QRegularExpression assignmentRe(
        QStringLiteral("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$"));

    QRegularExpressionMatch match = assignmentRe.match(trimmed);
    if (!match.hasMatch()) {
        return false;
    }

    key = match.captured(1);

    // Extract value, stripping quotes and inline comments
    QString rawValue = match.captured(2);

    // Strip inline comment (# preceded by space, outside quotes)
    // Simple heuristic: if the value starts with a quote, find the
    // closing quote first, then look for # after it.
    if (rawValue.startsWith(QLatin1Char('"'))) {
        int closeQuote = rawValue.indexOf(QLatin1Char('"'), 1);
        if (closeQuote > 0) {
            rawValue = rawValue.mid(1, closeQuote - 1);
        } else {
            rawValue = rawValue.mid(1);  // unclosed quote — take as-is
        }
    } else if (rawValue.startsWith(QLatin1Char('\''))) {
        int closeQuote = rawValue.indexOf(QLatin1Char('\''), 1);
        if (closeQuote > 0) {
            rawValue = rawValue.mid(1, closeQuote - 1);
        } else {
            rawValue = rawValue.mid(1);
        }
    } else {
        // Unquoted value — strip inline comment
        int hashPos = rawValue.indexOf(QStringLiteral("  #"));
        if (hashPos >= 0) {
            rawValue = rawValue.left(hashPos);
        }
        rawValue = rawValue.trimmed();
    }

    value = rawValue;
    return true;
}

QString ConfWriter::unquote(const QString &s) const
{
    if (s.length() >= 2) {
        if ((s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"')))
            || (s.startsWith(QLatin1Char('\'')) && s.endsWith(QLatin1Char('\'')))) {
            return s.mid(1, s.length() - 2);
        }
    }
    return s;
}

// ═════════════════════════════════════════════════════════════
// Value access — strings
// ═════════════════════════════════════════════════════════════

QString ConfWriter::value(const QString &key, const QString &defaultValue) const
{
    return m_values.value(key, defaultValue);
}

void ConfWriter::setValue(const QString &key, const QString &value)
{
    m_values[key] = value;
}

// ═════════════════════════════════════════════════════════════
// Value access — integers
// ═════════════════════════════════════════════════════════════

int ConfWriter::intValue(const QString &key, int defaultValue) const
{
    QString val = m_values.value(key);
    if (val.isEmpty()) {
        return defaultValue;
    }
    bool ok = false;
    int result = val.toInt(&ok);
    return ok ? result : defaultValue;
}

void ConfWriter::setIntValue(const QString &key, int value)
{
    m_values[key] = QString::number(value);
}

// ═════════════════════════════════════════════════════════════
// Value access — booleans
// ═════════════════════════════════════════════════════════════

bool ConfWriter::boolValue(const QString &key, bool defaultValue) const
{
    QString val = m_values.value(key).toLower();
    if (val == QStringLiteral("true") || val == QStringLiteral("1")
        || val == QStringLiteral("yes")) {
        return true;
    }
    if (val == QStringLiteral("false") || val == QStringLiteral("0")
        || val == QStringLiteral("no")) {
        return false;
    }
    return defaultValue;
}

void ConfWriter::setBoolValue(const QString &key, bool value)
{
    m_values[key] = value ? QStringLiteral("true") : QStringLiteral("false");
}

// ═════════════════════════════════════════════════════════════
// Value access — URLs (file paths)
// ═════════════════════════════════════════════════════════════

QUrl ConfWriter::urlValue(const QString &key, const QUrl &defaultValue) const
{
    QString val = m_values.value(key);
    if (val.isEmpty()) {
        return defaultValue;
    }
    // Config stores local file paths, not URLs — convert.
    return QUrl::fromLocalFile(val);
}

void ConfWriter::setUrlValue(const QString &key, const QUrl &value)
{
    // Store as a plain local path (what the shell scripts expect).
    m_values[key] = value.toLocalFile();
}

// ═════════════════════════════════════════════════════════════
// Bulk access
// ═════════════════════════════════════════════════════════════

QMap<QString, QString> ConfWriter::allValues() const
{
    return m_values;
}
