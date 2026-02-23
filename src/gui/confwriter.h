// confwriter.h
// MusicLib Qt GUI — Shell config file reader/writer
//
// Reads and writes musiclib.conf as a shell-sourceable KEY="value" file.
// Preserves comments, blank lines, and section headers when rewriting.
//
// This class bridges KConfig (GUI fast-cache) and musiclib.conf (backend
// authority).  The shell scripts never touch KConfig; they source the
// .conf file directly.  So every GUI settings change must be flushed
// to disk through this writer.
//
// Copyright (c) 2026 MusicLib Project

#ifndef CONFWRITER_H
#define CONFWRITER_H

#include <QString>
#include <QMap>
#include <QUrl>

/**
 * @brief Reads and writes musiclib.conf while preserving its structure.
 *
 * The file format is simple shell assignment:
 *   KEY="value"        (string)
 *   KEY=42             (integer, no quotes)
 *   KEY=true           (boolean, no quotes)
 *   # comment lines    (preserved verbatim)
 *   blank lines        (preserved verbatim)
 *
 * Lines containing shell variable expansions like ${MUSICLIB_DATA_DIR}
 * are read literally (the expansion is not evaluated).  When the GUI
 * rewrites a value, it writes the resolved absolute path — no shell
 * variables.  This is intentional: the GUI always knows the concrete
 * paths, and writing them explicitly avoids subtle expansion bugs.
 */
class ConfWriter
{
public:
    ConfWriter();

    /// Load config from the standard location (XDG or legacy fallback).
    /// Returns true if a config file was found and parsed.
    bool loadFromDefaultLocation();

    /// Load config from an explicit file path.
    /// Returns true if the file was found and parsed.
    bool loadFromFile(const QString &filePath);

    /// Write all current values back to the file that was loaded.
    /// Preserves comments and section headers.
    /// Returns true on success.
    bool save();

    /// Write current values to an explicit file path.
    bool saveToFile(const QString &filePath);

    /// Path of the currently loaded config file (empty if none loaded).
    QString filePath() const;

    // ── Value access ──

    /// Get a string value.  Returns defaultValue if key not found.
    QString value(const QString &key, const QString &defaultValue = QString()) const;

    /// Get an integer value.  Returns defaultValue if key not found or not numeric.
    int intValue(const QString &key, int defaultValue = 0) const;

    /// Get a boolean value (true/false).
    bool boolValue(const QString &key, bool defaultValue = false) const;

    /// Get a URL value (converts string path to QUrl).
    QUrl urlValue(const QString &key, const QUrl &defaultValue = QUrl()) const;

    /// Set a string value.
    void setValue(const QString &key, const QString &value);

    /// Set an integer value.
    void setIntValue(const QString &key, int value);

    /// Set a boolean value.
    void setBoolValue(const QString &key, bool value);

    /// Set a URL value (stores as local file path string).
    void setUrlValue(const QString &key, const QUrl &value);

    /// Returns all known key=value pairs (keys are case-sensitive).
    QMap<QString, QString> allValues() const;

private:
    /// Locate the config file using XDG then legacy fallback.
    /// Returns empty string if not found anywhere.
    QString locateConfigFile() const;

    /// Parse a single line, extracting key and value if it's an assignment.
    /// Returns true if the line was a valid KEY=value assignment.
    bool parseLine(const QString &line, QString &key, QString &value) const;

    /// Strip surrounding quotes from a value string.
    QString unquote(const QString &s) const;

    /// The full file path currently loaded.
    QString m_filePath;

    /// Ordered list of raw lines from the file (comments, blanks, assignments).
    /// Used to preserve file structure when rewriting.
    QStringList m_rawLines;

    /// Parsed key→value map (keys are the shell variable names).
    QMap<QString, QString> m_values;
};

#endif // CONFWRITER_H
