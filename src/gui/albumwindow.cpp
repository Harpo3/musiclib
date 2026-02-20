// albumwindow.cpp
// MusicLib Qt GUI - Album Detail Child Window Implementation
// Copyright (c) 2026 MusicLib Project

#include "albumwindow.h"
#include "librarymodel.h"

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QPixmap>
#include <QFileInfo>
#include <QDateTime>
#include <QFont>
#include <QTimeZone>

#include <cmath>

// ─────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────

AlbumWindow::AlbumWindow(QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle(tr("Album Details"));
    setMinimumSize(550, 450);
    resize(600, 500);

    // Don't block the main window
    setModal(false);
    setAttribute(Qt::WA_DeleteOnClose, false);  // reuse the window

    // ── Header ──
    m_headerLabel = new QLabel(this);
    QFont headerFont = m_headerLabel->font();
    headerFont.setPointSize(headerFont.pointSize() + 4);
    headerFont.setBold(true);
    m_headerLabel->setFont(headerFont);
    m_headerLabel->setWordWrap(true);

    // ── Artwork + Comment row ──
    m_artworkLabel = new QLabel(this);
    m_artworkLabel->setFixedSize(200, 200);
    m_artworkLabel->setScaledContents(true);
    m_artworkLabel->setFrameStyle(QFrame::StyledPanel);

    m_commentLabel = new QLabel(this);
    m_commentLabel->setWordWrap(true);
    m_commentLabel->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    m_commentLabel->setStyleSheet(
        QStringLiteral("QLabel { padding: 8px; background-color: palette(base); "
                       "border: 1px solid palette(mid); border-radius: 4px; }"));

    auto *artCommentLayout = new QHBoxLayout;
    artCommentLayout->addWidget(m_artworkLabel);
    artCommentLayout->addWidget(m_commentLabel, 1);

    // ── Track list ──
    m_trackList = new QTreeWidget(this);
    m_trackList->setRootIsDecorated(false);
    m_trackList->setAlternatingRowColors(true);
    m_trackList->setHeaderLabels({tr("Track"), tr("Rating"), tr("Last Played")});
    m_trackList->header()->setStretchLastSection(true);
    m_trackList->header()->setSectionResizeMode(0, QHeaderView::Stretch);
    m_trackList->header()->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    m_trackList->header()->setSectionResizeMode(2, QHeaderView::ResizeToContents);
    m_trackList->setSelectionMode(QAbstractItemView::NoSelection);
    m_trackList->setFocusPolicy(Qt::NoFocus);

    // ── Main layout ──
    auto *mainLayout = new QVBoxLayout(this);
    mainLayout->addWidget(m_headerLabel);
    mainLayout->addLayout(artCommentLayout);
    mainLayout->addWidget(m_trackList, 1);  // track list gets the stretch
}

AlbumWindow::~AlbumWindow() = default;

// ─────────────────────────────────────────────────────────────
// Populate with album data
// ─────────────────────────────────────────────────────────────

void AlbumWindow::populate(LibraryModel *model,
                           int albumId,
                           const QString &artist,
                           const QString &album,
                           const QString &year,
                           const QString &artworkPath,
                           const QString &comment)
{
    // ── Header ──
    QString header = artist + QStringLiteral(" - ") + album;
    if (!year.isEmpty()) {
        header += QStringLiteral(" (") + year + QStringLiteral(")");
    }
    m_headerLabel->setText(header);
    setWindowTitle(header);

    // ── Artwork ──
    QPixmap artwork(artworkPath);
    if (!artwork.isNull()) {
        m_artworkLabel->setPixmap(
            artwork.scaled(200, 200, Qt::KeepAspectRatio, Qt::SmoothTransformation));
        m_artworkLabel->show();
    } else {
        m_artworkLabel->setText(tr("No artwork"));
        m_artworkLabel->setAlignment(Qt::AlignCenter);
    }

    // ── Comment ──
    if (!comment.isEmpty()) {
        m_commentLabel->setText(comment);
        m_commentLabel->show();
    } else {
        m_commentLabel->setText(tr("No description available."));
    }

    // ── Track list from DSV ──
    m_trackList->clear();

    if (!model) {
        return;
    }

    // Collect all tracks matching this IDAlbum using trackAt() for raw data access
    struct TrackInfo {
        QString trackNumber;   // first 2 chars of filename
        QString title;
        int     groupDesc;
        double  lastPlayed;
    };
    QList<TrackInfo> tracks;

    const int rowCount = model->rowCount();
    for (int row = 0; row < rowCount; ++row) {
        TrackRecord record = model->trackAt(row);

        // Match by IDAlbum
        bool ok = false;
        int rowAlbumId = record.idAlbum.toInt(&ok);
        if (!ok || rowAlbumId != albumId) {
            continue;
        }

        TrackInfo info;
        info.title      = record.songTitle;
        info.groupDesc  = record.groupDesc.toInt();
        info.lastPlayed = record.lastTimePlayed.toDouble();

        // Extract track number from SongPath
        info.trackNumber = extractTrackNumber(record.songPath);

        tracks.append(info);
    }

    // Sort by track number
    std::sort(tracks.begin(), tracks.end(),
              [](const TrackInfo &a, const TrackInfo &b) {
                  return a.trackNumber < b.trackNumber;
              });

    // Populate tree widget
    for (const TrackInfo &track : tracks) {
        auto *item = new QTreeWidgetItem(m_trackList);
        item->setText(0, track.trackNumber + QStringLiteral(" ") + track.title);
        item->setText(1, starsToDisplay(track.groupDesc));
        item->setText(2, sqlTimeToDate(track.lastPlayed));
    }
}

// ─────────────────────────────────────────────────────────────
// Static helpers
// ─────────────────────────────────────────────────────────────

QString AlbumWindow::starsToDisplay(int groupDesc)
{
    if (groupDesc <= 0 || groupDesc > 5) {
        return QStringLiteral("—");  // unrated
    }

    // Build star string: filled stars + empty stars
    QString stars;
    for (int i = 0; i < groupDesc; ++i) {
        stars += QChar(0x2605);  // ★ BLACK STAR
    }
    for (int i = groupDesc; i < 5; ++i) {
        stars += QChar(0x2606);  // ☆ WHITE STAR
    }
    return stars;
}

QString AlbumWindow::sqlTimeToDate(double sqlTime)
{
    if (sqlTime <= 0.0) {
        return QStringLiteral("Never");
    }

    // SQL serial time: days since 1899-12-30
    // Convert to Unix epoch: (sqlTime - 25569) * 86400
    qint64 unixEpoch = static_cast<qint64>((sqlTime - 25569.0) * 86400.0);
    QDateTime dt = QDateTime::fromSecsSinceEpoch(unixEpoch, QTimeZone::systemTimeZone());

    if (!dt.isValid()) {
        return QStringLiteral("Invalid");
    }

    return dt.toString(QStringLiteral("MM/dd/yyyy"));
}

QString AlbumWindow::extractTrackNumber(const QString &songPath)
{
    // Track number is always the first two characters of the filename
    QFileInfo fi(songPath);
    QString basename = fi.fileName();

    if (basename.length() >= 2) {
        return basename.left(2);
    }
    return QStringLiteral("??");
}
