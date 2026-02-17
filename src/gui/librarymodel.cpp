#include "librarymodel.h"

#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QColor>
#include <QTimeZone>

static const char DSV_DELIMITER = '^';

LibraryModel::LibraryModel(QObject *parent)
    : QAbstractTableModel(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_debounceTimer(new QTimer(this))
{
    m_headers = {
        "ID", "Artist", "IDAlbum", "Album", "Album Artist",
        "Title", "Path", "Genre", "Length", "Rating",
        "Custom2", "Stars", "Last Played"
    };

    // Debounce DSV changes - wait 500ms after last change before reloading
    m_debounceTimer->setSingleShot(true);
    m_debounceTimer->setInterval(500);

    connect(m_watcher, &QFileSystemWatcher::fileChanged,
            this, &LibraryModel::onFileChanged);
    connect(m_debounceTimer, &QTimer::timeout,
            this, &LibraryModel::reloadDebounced);
}

bool LibraryModel::loadFromFile(const QString &path)
{
    m_dsvPath = path;

    // Start watching the file for changes
    if (!m_watcher->files().isEmpty())
        m_watcher->removePaths(m_watcher->files());
    m_watcher->addPath(path);

    parseFile(path);
    return !m_tracks.isEmpty();
}

void LibraryModel::parseFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit loadError(tr("Cannot open database file: %1").arg(path));
        return;
    }

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);

    QVector<TrackRecord> newTracks;
    bool firstLine = true;

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;

        // Skip header row
        if (firstLine) {
            firstLine = false;
            continue;
        }

        QStringList fields = line.split(DSV_DELIMITER);

        // Pad short rows to avoid out-of-bounds
        while (fields.size() < static_cast<int>(TrackColumn::COUNT))
            fields.append(QString());

        TrackRecord track;
        track.id            = fields[static_cast<int>(TrackColumn::ID)];
        track.artist        = fields[static_cast<int>(TrackColumn::Artist)];
        track.idAlbum       = fields[static_cast<int>(TrackColumn::IDAlbum)];
        track.album         = fields[static_cast<int>(TrackColumn::Album)];
        track.albumArtist   = fields[static_cast<int>(TrackColumn::AlbumArtist)];
        track.songTitle     = fields[static_cast<int>(TrackColumn::SongTitle)];
        track.songPath      = fields[static_cast<int>(TrackColumn::SongPath)];
        track.genre         = fields[static_cast<int>(TrackColumn::Genre)];
        track.songLength    = fields[static_cast<int>(TrackColumn::SongLength)];
        track.rating        = fields[static_cast<int>(TrackColumn::Rating)];
        track.custom2       = fields[static_cast<int>(TrackColumn::Custom2)];
        track.groupDesc     = fields[static_cast<int>(TrackColumn::GroupDesc)];
        track.lastTimePlayed = fields[static_cast<int>(TrackColumn::LastTimePlayed)];

        newTracks.append(track);
    }

    beginResetModel();
    m_tracks = newTracks;
    endResetModel();
}

void LibraryModel::onFileChanged(const QString &path)
{
    Q_UNUSED(path)
    // Re-add path in case the file was replaced (shell scripts use tmp+mv)
    if (!m_watcher->files().contains(m_dsvPath))
        m_watcher->addPath(m_dsvPath);
    m_debounceTimer->start();
}

void LibraryModel::reloadDebounced()
{
    parseFile(m_dsvPath);
}

int LibraryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_tracks.size();
}

int LibraryModel::columnCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return static_cast<int>(TrackColumn::COUNT);
}

QVariant LibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_tracks.size())
        return QVariant();

    const TrackRecord &track = m_tracks.at(index.row());
    const int col = index.column();

    if (role == Qt::DisplayRole) {
        switch (static_cast<TrackColumn>(col)) {
        case TrackColumn::ID:            return track.id;
        case TrackColumn::Artist:        return track.artist;
        case TrackColumn::IDAlbum:       return track.idAlbum;
        case TrackColumn::Album:         return track.album;
        case TrackColumn::AlbumArtist:   return track.albumArtist;
        case TrackColumn::SongTitle:     return track.songTitle;
        case TrackColumn::SongPath:      return track.songPath;
        case TrackColumn::Genre:         return track.genre;
        case TrackColumn::SongLength:    return formatDuration(track.songLength);
        case TrackColumn::Rating:        return track.rating;
        case TrackColumn::Custom2:       return track.custom2;
        case TrackColumn::GroupDesc:     return track.groupDesc;
        case TrackColumn::LastTimePlayed: return formatLastPlayed(track.lastTimePlayed);
        default:                         return QVariant();
        }
    }

    // Highlight unrated tracks with a subtle background
    if (role == Qt::BackgroundRole) {
        if (track.groupDesc.trimmed() == "0" || track.groupDesc.trimmed().isEmpty())
            return QColor(255, 255, 220); // pale yellow
    }

// Provide raw numeric values for correct sorting
    if (role == Qt::UserRole) {
        if (static_cast<TrackColumn>(col) == TrackColumn::GroupDesc)
            return track.groupDesc.toInt();
        if (static_cast<TrackColumn>(col) == TrackColumn::LastTimePlayed)
            return track.lastTimePlayed.toDouble();
    }

    return QVariant();
}

QVariant LibraryModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (role != Qt::DisplayRole) return QVariant();
    if (orientation == Qt::Horizontal && section < m_headers.size())
        return m_headers.at(section);
    if (orientation == Qt::Vertical)
        return section + 1;
    return QVariant();
}

TrackRecord LibraryModel::trackAt(int row) const
{
    if (row < 0 || row >= m_tracks.size())
        return TrackRecord{};
    return m_tracks.at(row);
}

// Convert milliseconds string to m:ss display
QString LibraryModel::formatDuration(const QString &ms) const
{
    bool ok = false;
    int total = ms.toInt(&ok);
    if (!ok || total <= 0) return ms;
    int secs = total / 1000;
    return QString("%1:%2").arg(secs / 60).arg(secs % 60, 2, 10, QChar('0'));
}

// Convert Excel serial time (float) to readable date string
QString LibraryModel::formatLastPlayed(const QString &serialTime) const
{
    bool ok = false;
    double serial = serialTime.toDouble(&ok);
    if (!ok || serial <= 0.0) return QString();

    // Excel serial: days since 1899-12-30
    qint64 unixSecs = static_cast<qint64>((serial - 25569.0) * 86400.0);
    QDateTime dt = QDateTime::fromSecsSinceEpoch(unixSecs, QTimeZone::utc());
    if (!dt.isValid()) return QString();
    return dt.toLocalTime().toString("MM/dd/yy");
}
