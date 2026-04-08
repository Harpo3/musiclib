// configuretoolbarsdialog.h
// MusicLib Qt GUI — Configure Toolbars Dialog
//
// Presents a two-panel interface for customising the main toolbar:
//
//   Left  — Available Actions   (items not currently on the toolbar)
//   Right — Current Actions     (items currently on the toolbar, in order)
//
// The user can:
//   • Add items from Available → Current
//   • Remove items from Current → Available
//   • Re-order items within Current via Move Up / Move Down
//
// When the user clicks OK, the toolbarConfigChanged(newOrder) signal is
// emitted with the new ordered list of ToolbarItemIds.
//
// The "Now Playing" label and star-rating buttons are fixed built-ins and do
// NOT appear in this dialog.  Only the five configurable actions below can be
// reordered or hidden.
//
// Adding new toolbar actions in the future:
//   1.  Add a new enumerator to ToolbarItemId below (never re-use values).
//   2.  Add the ToolbarItem descriptor inside MainWindow::showConfigureToolbarsDialog().
//   3.  Wire up the QAction / QWidgetAction in MainWindow::setupToolbar().
//   4.  Handle the new id in the switch inside MainWindow::rebuildToolbar().
//
// Copyright (c) 2026 MusicLib Project

#pragma once

#include <QDialog>
#include <QList>
#include <QString>

class QListWidget;
class QListWidgetItem;
class QPushButton;

// ─────────────────────────────────────────────────────────────────────────────
// ToolbarItemId
//
// Stable integer IDs for each logical toolbar element.
// These values are stored in KConfig, so existing entries must never be
// renumbered.  Mark removed entries with a comment instead of deleting them.
// ─────────────────────────────────────────────────────────────────────────────
enum class ToolbarItemId {
    // 0 — reserved (was NowPlaying, now fixed built-in)
    // 1 — reserved (was StarRatings, now fixed built-in)
    Album        = 2,   ///< Album detail button
    Playlist     = 3,   ///< Playlist selector (label + dropdown)
    Audacious    = 4,   ///< Launch / raise Audacious
    Kid3         = 5,   ///< Open track in Kid3 tag editor
    Dolphin      = 6,   ///< Open track folder in Dolphin

    RipCD        = 7,   ///< Launch / raise K3b CD ripper (disabled when K3B_INSTALLED=false)

    // Future additions — append here, do NOT renumber entries above:
    // RefreshFromAudacious = 8,  ///< Pull current track from Audacious (Mobile)
    // RebuildTag           = 9,  ///< Rebuild tag for selected track
    // RemoveRecord         = 10, ///< Remove selected record from library
};

// ─────────────────────────────────────────────────────────────────────────────
// ToolbarItem
//
// Descriptor for a single logical toolbar element.
// ─────────────────────────────────────────────────────────────────────────────
struct ToolbarItem {
    ToolbarItemId id;          ///< Stable identifier (persisted to KConfig)
    QString       name;        ///< Display name shown in the dialog (i18n'd)
    QString       iconName;    ///< QIcon::fromTheme() key; may be empty
};

// ─────────────────────────────────────────────────────────────────────────────
// ConfigureToolbarsDialog
// ─────────────────────────────────────────────────────────────────────────────
class ConfigureToolbarsDialog : public QDialog
{
    Q_OBJECT

public:
    /**
     * @param currentItems   Items currently on the toolbar, in display order.
     * @param availableItems Items that can be added but are not currently shown.
     * @param parent         Parent widget.
     */
    explicit ConfigureToolbarsDialog(
        const QList<ToolbarItem> &currentItems,
        const QList<ToolbarItem> &availableItems,
        QWidget *parent = nullptr);

    /**
     * @returns Ordered list of IDs representing the user's chosen toolbar
     *          configuration.  Call only after exec() returned QDialog::Accepted.
     */
    QList<ToolbarItemId> currentItemIds() const;

Q_SIGNALS:
    /**
     * Emitted when the user accepts the dialog.
     * @param newOrder New ordered list of toolbar item IDs.
     */
    void toolbarConfigChanged(const QList<ToolbarItemId> &newOrder);

private Q_SLOTS:
    void onAddItem();
    void onRemoveItem();
    void onMoveUp();
    void onMoveDown();
    void updateButtons();

private:
    void setupUi(const QList<ToolbarItem> &currentItems,
                 const QList<ToolbarItem> &availableItems);

    /// Append a ToolbarItem entry to the given list widget.
    void appendItem(QListWidget *list, const ToolbarItem &item);

    /// Swap the display text, icon, and id data of two rows in m_currentList.
    void swapCurrentRows(int rowA, int rowB);

    QListWidget *m_availableList  = nullptr;
    QListWidget *m_currentList    = nullptr;

    QPushButton *m_addBtn         = nullptr;
    QPushButton *m_removeBtn      = nullptr;
    QPushButton *m_moveUpBtn      = nullptr;
    QPushButton *m_moveDownBtn    = nullptr;
};
