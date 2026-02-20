#pragma once

#include <QAbstractTableModel>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QVector>
#include <QStringList>

// Represents one row from musiclib.dsv
struct TrackRecord {
    QString id;
    QString artist;
    QString idAlbum;
    QString album;
    QString albumArtist;
    QString songTitle;
    QString songPath;
    QString genre;
    QString songLength;
    QString rating;      // Raw POPM value (not used for display)
    QString custom2;
    QString groupDesc;   // Star rating 0-5 (used for display)
    QString lastTimePlayed;
};

// Column indices - match DSV order
enum class TrackColumn : int {
    ID           = 0,
    Artist       = 1,
    IDAlbum      = 2,
    Album        = 3,
    AlbumArtist  = 4,
    SongTitle    = 5,
    SongPath     = 6,
    Genre        = 7,
    SongLength   = 8,
    Rating       = 9,
    Custom2      = 10,
    GroupDesc    = 11,
    LastTimePlayed = 12,
    COUNT        = 13
};

class LibraryModel : public QAbstractTableModel
{
    Q_OBJECT

public:
    explicit LibraryModel(QObject *parent = nullptr);
    ~LibraryModel() override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;

    // Load DSV from path; returns true on success
    bool loadFromFile(const QString &path);

    // QAbstractTableModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role = Qt::DisplayRole) const override;

    // Return the full TrackRecord for a given row
    TrackRecord trackAt(int row) const;

    QString dsvPath() const { return m_dsvPath; }

signals:
    void loadError(const QString &message);

private slots:
    void onFileChanged(const QString &path);
    void reloadDebounced();

private:
    void parseFile(const QString &path);
    QString formatDuration(const QString &ms) const;
    QString formatLastPlayed(const QString &serialTime) const;

    QVector<TrackRecord>  m_tracks;
    QStringList           m_headers;
    QString               m_dsvPath;
    QFileSystemWatcher   *m_watcher;
    QTimer               *m_debounceTimer;
};
