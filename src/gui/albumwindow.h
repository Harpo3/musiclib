// albumwindow.h
// MusicLib Qt GUI - Album Detail Child Window
// Phase 2: Toolbar action - shows full album tracklist with artwork and comment
//
// Opened from the "Album" toolbar button. Displays:
//   - Header: Artist - Album (Year)
//   - Album artwork from data/conky_output/folder.jpg
//   - Comment/description from data/conky_output/detail.txt
//   - Full tracklist from DSV (matched by IDAlbum), sorted by track number
//     (first 2 characters of filename), showing Title, Rating stars, Last Played
//
// Copyright (c) 2026 MusicLib Project

#ifndef ALBUMWINDOW_H
#define ALBUMWINDOW_H

#include <QDialog>
#include <QLabel>
#include <QTreeWidget>

class LibraryModel;

/**
 * @brief Modal-less child window showing album detail for the currently playing track.
 *
 * Layout:
 *   ┌──────────────────────────────────────────┐
 *   │ Aerosmith - Toys in the Attic (1975)     │
 *   ├──────────┬───────────────────────────────┤
 *   │          │ Comment / album description    │
 *   │ Artwork  │ from detail.txt               │
 *   │          │                               │
 *   ├──────────┴───────────────────────────────┤
 *   │ Track              Rating    Last Played  │
 *   │ 01 Toys in the..   ★★★★★    12/16/2025  │
 *   │ 02 Uncle Salty      ★★★★☆    01/03/2026  │
 *   │ ...                                       │
 *   └──────────────────────────────────────────┘
 */
class AlbumWindow : public QDialog
{
    Q_OBJECT

public:
    explicit AlbumWindow(QWidget *parent = nullptr);
    ~AlbumWindow() override;

    /**
     * @brief Populate the window with album data.
     *
     * @param model       The library model (DSV data) to query for album tracks
     * @param albumId     IDAlbum value to match in DSV
     * @param artist      Artist name for the header
     * @param album       Album name for the header
     * @param year        Year string (from conky year.txt)
     * @param artworkPath Full path to album artwork (folder.jpg)
     * @param comment     Album/artist comment (from conky detail.txt)
     */
    void populate(LibraryModel *model,
                  int albumId,
                  const QString &artist,
                  const QString &album,
                  const QString &year,
                  const QString &artworkPath,
                  const QString &comment);

private:
    /// Convert a GroupDesc star code (0-5) to a display string like "★★★★☆"
    static QString starsToDisplay(int groupDesc);

    /// Convert SQL serial time (float) to a human-readable date string
    static QString sqlTimeToDate(double sqlTime);

    /// Extract track number from filename (first 2 characters)
    static QString extractTrackNumber(const QString &songPath);

    // ── Widgets ──
    QLabel       *m_headerLabel;    ///< "Artist - Album (Year)"
    QLabel       *m_artworkLabel;   ///< Album artwork image
    QLabel       *m_commentLabel;   ///< detail.txt content
    QTreeWidget  *m_trackList;      ///< Track listing table
};

#endif // ALBUMWINDOW_H
