#include "libraryview.h"
#include "librarymodel.h"
#include "ratingdelegate.h"
#include "scriptrunner.h"

#include <QTableView>
#include <QLineEdit>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QSortFilterProxyModel>
#include <QCheckBox>
#include <QMessageBox>
#include <QMenu>
#include <QProcess>
#include <QDir>
#include <QFile>
#include <QUrl>

// ---------------------------------------------------------------------------
// Custom proxy: adds "exclude unrated" filtering on top of the standard
// text filter provided by QSortFilterProxyModel.
// ---------------------------------------------------------------------------
class LibraryFilterProxyModel : public QSortFilterProxyModel
{
public:
    explicit LibraryFilterProxyModel(QObject *parent = nullptr)
        : QSortFilterProxyModel(parent) {}

    void setExcludeUnrated(bool exclude) {
        if (m_excludeUnrated != exclude) {
            m_excludeUnrated = exclude;
            beginFilterChange();
            endFilterChange();
        }
    }

    void setExcludeRated(bool exclude) {
        if (m_excludeRated != exclude) {
            m_excludeRated = exclude;
            beginFilterChange();
            endFilterChange();
        }
    }

protected:
    bool filterAcceptsRow(int sourceRow,
                          const QModelIndex &sourceParent) const override
    {
        // Apply star-rating filters first
        if (m_excludeUnrated || m_excludeRated) {
            QModelIndex idx = sourceModel()->index(
                sourceRow,
                static_cast<int>(TrackColumn::GroupDesc),
                sourceParent);
            // UserRole returns the numeric star value (int)
            int stars = sourceModel()->data(idx, Qt::UserRole).toInt();
            if (m_excludeUnrated && stars == 0)
                return false;
            if (m_excludeRated && stars > 0)
                return false;
        }
        // Then apply the normal text filter
        return QSortFilterProxyModel::filterAcceptsRow(sourceRow, sourceParent);
    }

private:
    bool m_excludeUnrated = false;
    bool m_excludeRated   = false;
};

// Columns visible by default (hide ID, IDAlbum, SongPath, Custom2, Rating)
static const QSet<int> HIDDEN_COLUMNS = {
    static_cast<int>(TrackColumn::ID),
    static_cast<int>(TrackColumn::IDAlbum),
    static_cast<int>(TrackColumn::SongPath),
    static_cast<int>(TrackColumn::Custom2),
    static_cast<int>(TrackColumn::Rating),
};

LibraryView::LibraryView(QWidget *parent)
    : QWidget(parent)
    , m_model(new LibraryModel(this))
    , m_proxyModel(new LibraryFilterProxyModel(this))
    , m_tableView(new QTableView(this))
    , m_filterEdit(new QLineEdit(this))
    , m_countLabel(new QLabel(this))
    , m_ratingDelegate(new RatingDelegate(this))
    , m_scriptRunner(new ScriptRunner(this))
{
    // --- Filter bar ---
    m_filterEdit->setPlaceholderText("Filter by artist, album, or title...");
    m_filterEdit->setClearButtonEnabled(true);

    m_excludeUnratedCheckbox = new QCheckBox(tr("Exclude Unrated"), this);
    m_excludeUnratedCheckbox->setChecked(true);

    m_excludeRatedCheckbox = new QCheckBox(tr("Exclude Rated"), this);
    m_excludeRatedCheckbox->setChecked(false);
    // Unrated starts checked, so Rated starts dimmed (mutually exclusive)
    m_excludeRatedCheckbox->setEnabled(false);

    QHBoxLayout *filterLayout = new QHBoxLayout();
    filterLayout->addWidget(new QLabel("Filter:", this));
    filterLayout->addWidget(m_filterEdit, 1);
    filterLayout->addWidget(m_excludeUnratedCheckbox);
    filterLayout->addWidget(m_excludeRatedCheckbox);
    filterLayout->addWidget(m_countLabel);

    // --- Proxy model for filtering and sorting ---
    m_proxyModel->setSourceModel(m_model);
    m_proxyModel->setFilterCaseSensitivity(Qt::CaseInsensitive);
    m_proxyModel->setFilterKeyColumn(-1); // search all columns
    m_proxyModel->setSortRole(Qt::UserRole);

    // Match the checkbox default — exclude unrated on startup
    static_cast<LibraryFilterProxyModel *>(m_proxyModel)->setExcludeUnrated(true);

    // --- Table view ---
    m_tableView->setModel(m_proxyModel);
    m_tableView->setSortingEnabled(true);
    m_tableView->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_tableView->setSelectionMode(QAbstractItemView::ExtendedSelection);
    m_tableView->setAlternatingRowColors(true);
    m_tableView->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_tableView->setMouseTracking(true);
    m_tableView->verticalHeader()->hide();
    m_tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);
    m_tableView->horizontalHeader()->setStretchLastSection(false);
    m_tableView->setSortingEnabled(true);
    m_tableView->sortByColumn(static_cast<int>(TrackColumn::Artist), Qt::AscendingOrder);

    // Install star rating delegate on the GroupDesc (Stars) column
    m_tableView->setItemDelegateForColumn(
        static_cast<int>(TrackColumn::GroupDesc), m_ratingDelegate);
    m_ratingDelegate->setView(m_tableView);

    // Enable right-click context menu on table rows
    m_tableView->setContextMenuPolicy(Qt::CustomContextMenu);

    // --- Main layout ---
    QVBoxLayout *mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(4, 4, 4, 4);
    mainLayout->addLayout(filterLayout);
    mainLayout->addWidget(m_tableView, 1);
    setLayout(mainLayout);

    // --- Connections ---
    connect(m_filterEdit, &QLineEdit::textChanged,
            this, &LibraryView::onFilterChanged);
    connect(m_model, &LibraryModel::loadError,
            this, &LibraryView::onModelLoadError);

    // Re-sort correctly when any column header is clicked
    connect(m_tableView->horizontalHeader(), &QHeaderView::sectionClicked,
            this, [this](int col) {
                m_proxyModel->invalidate();
                m_tableView->sortByColumn(
                    col, m_tableView->horizontalHeader()->sortIndicatorOrder());
            });

    // Rating delegate -> script runner
    connect(m_ratingDelegate, &RatingDelegate::ratingChanged,
            this, &LibraryView::onRatingChanged);

    // Script runner results — rating
    connect(m_scriptRunner, &ScriptRunner::rateSuccess,
            this, &LibraryView::onRateSuccess);
    connect(m_scriptRunner, &ScriptRunner::rateDeferred,
            this, &LibraryView::onRateDeferred);
    connect(m_scriptRunner, &ScriptRunner::rateError,
            this, &LibraryView::onRateError);

    // Script runner results — record removal
    connect(m_scriptRunner, &ScriptRunner::removeSuccess,
            this, &LibraryView::onRemoveSuccess);
    connect(m_scriptRunner, &ScriptRunner::removeError,
            this, &LibraryView::onRemoveError);

    // Exclude-unrated / exclude-rated checkboxes (mutually exclusive)
    connect(m_excludeUnratedCheckbox, &QCheckBox::toggled,
            this, &LibraryView::onExcludeUnratedToggled);
    connect(m_excludeRatedCheckbox, &QCheckBox::toggled,
            this, &LibraryView::onExcludeRatedToggled);

    // Context menu on right-click
    connect(m_tableView, &QTableView::customContextMenuRequested,
            this, &LibraryView::showContextMenu);
}

bool LibraryView::loadDatabase(const QString &path)
{
    bool ok = m_model->loadFromFile(path);
    setupColumns();
    m_countLabel->setText(tr("%1 tracks").arg(m_model->rowCount()));
    if (ok)
        emit statusMessage(tr("Loaded: %1  (%2 tracks)").arg(path).arg(m_model->rowCount()));
    return ok;
}

int LibraryView::trackCount() const
{
    return m_model->rowCount();
}

void LibraryView::setupColumns()
{
    // Hide internal/technical columns by default
    for (int col = 0; col < m_model->columnCount(); ++col) {
        m_tableView->setColumnHidden(col, HIDDEN_COLUMNS.contains(col));
    }

    // Set sensible default widths for visible columns
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Artist),        180);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Album),         180);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::AlbumArtist),   150);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::SongTitle),     220);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Genre),         100);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::SongLength),     60);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::GroupDesc),      95);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::LastTimePlayed), 90);
}

void LibraryView::onFilterChanged(const QString &text)
{
    m_proxyModel->setFilterFixedString(text);

    if (text.isEmpty()) {
        // Force the proxy to re-evaluate all rows, then re-sort
        m_proxyModel->invalidate();
        m_proxyModel->sort(static_cast<int>(TrackColumn::Artist), Qt::AscendingOrder);
        m_tableView->horizontalHeader()->setSortIndicator(
            static_cast<int>(TrackColumn::Artist), Qt::AscendingOrder);
    }

    // Show filtered count when any filtering is active
    bool anyFilter = !text.isEmpty() || m_excludeUnratedCheckbox->isChecked()
                     || m_excludeRatedCheckbox->isChecked();
    m_countLabel->setText(anyFilter
        ? tr("%1 / %2 tracks").arg(m_proxyModel->rowCount()).arg(m_model->rowCount())
        : tr("%1 tracks").arg(m_model->rowCount()));
}

void LibraryView::onExcludeUnratedToggled(bool checked)
{
    static_cast<LibraryFilterProxyModel *>(m_proxyModel)->setExcludeUnrated(checked);

    // Dim the "Exclude Rated" checkbox while this one is active (mutually exclusive)
    m_excludeRatedCheckbox->setEnabled(!checked);

    // Refresh the displayed count to reflect the new filter state
    bool anyFilter = !m_filterEdit->text().isEmpty() || checked
                     || m_excludeRatedCheckbox->isChecked();
    m_countLabel->setText(anyFilter
        ? tr("%1 / %2 tracks").arg(m_proxyModel->rowCount()).arg(m_model->rowCount())
        : tr("%1 tracks").arg(m_model->rowCount()));
}

void LibraryView::onExcludeRatedToggled(bool checked)
{
    static_cast<LibraryFilterProxyModel *>(m_proxyModel)->setExcludeRated(checked);

    // Dim the "Exclude Unrated" checkbox while this one is active (mutually exclusive)
    m_excludeUnratedCheckbox->setEnabled(!checked);

    // Refresh the displayed count to reflect the new filter state
    bool anyFilter = !m_filterEdit->text().isEmpty() || checked
                     || m_excludeUnratedCheckbox->isChecked();
    m_countLabel->setText(anyFilter
        ? tr("%1 / %2 tracks").arg(m_proxyModel->rowCount()).arg(m_model->rowCount())
        : tr("%1 tracks").arg(m_model->rowCount()));
}

void LibraryView::onModelLoadError(const QString &message)
{
    emit statusMessage(tr("Error: %1").arg(message));
}

void LibraryView::onRatingChanged(int sourceRow, int newRating)
{
    TrackRecord track = m_model->trackAt(sourceRow);
    if (track.songPath.isEmpty()) {
        emit statusMessage(tr("Error: could not resolve track path for row %1").arg(sourceRow));
        return;
    }
    emit statusMessage(tr("Rating %1 -> %2 stars...").arg(track.songTitle).arg(newRating));
    m_scriptRunner->rate(track.songPath, newRating);
}

void LibraryView::onRateSuccess(const QString &filePath, int stars)
{
    Q_UNUSED(filePath)
    emit statusMessage(tr("Rating saved: %1 star(s)").arg(stars));
    // DSV watcher will trigger model refresh automatically
}

void LibraryView::onRateDeferred(const QString &filePath, int stars)
{
    Q_UNUSED(filePath)
    emit statusMessage(tr("Rating queued (%1 star(s)) -- database busy, will retry").arg(stars));
}

void LibraryView::onRateError(const QString &filePath, int stars, const QString &message)
{
    Q_UNUSED(filePath)
    Q_UNUSED(stars)
    emit statusMessage(tr("Rating error: %1").arg(message));
    QMessageBox::warning(this, tr("Rating Failed"), message);
}

// ===========================================================================
//  Context menu — right-click on a table row
// ===========================================================================

void LibraryView::showContextMenu(const QPoint &pos)
{
    // Determine which row was right-clicked
    QModelIndex proxyIdx = m_tableView->indexAt(pos);
    if (!proxyIdx.isValid())
        return;

    // Map right-clicked row to source (used for Remove Record)
    QModelIndex sourceIdx = m_proxyModel->mapToSource(proxyIdx);
    TrackRecord track = m_model->trackAt(sourceIdx.row());
    if (track.songPath.isEmpty())
        return;

    // Build the track list for Audacious actions.
    // If the right-clicked row is part of the current selection, use all selected
    // rows; otherwise fall back to just the right-clicked row.
    QModelIndexList selectedProxyRows = m_tableView->selectionModel()->selectedRows();
    bool clickInSelection = false;
    for (const QModelIndex &idx : selectedProxyRows) {
        if (idx.row() == proxyIdx.row()) { clickInSelection = true; break; }
    }

    QVector<TrackRecord> tracks;
    if (clickInSelection && selectedProxyRows.size() > 1) {
        for (const QModelIndex &idx : selectedProxyRows) {
            TrackRecord t = m_model->trackAt(m_proxyModel->mapToSource(idx).row());
            if (!t.songPath.isEmpty())
                tracks.append(t);
        }
    } else {
        tracks.append(track);
    }

    // Label suffix shown when multiple tracks are targeted
    QString countLabel = tracks.size() > 1
        ? tr(" (%1 tracks)").arg(tracks.size())
        : QString();

    // Build the context menu
    QMenu menu(this);

    QAction *openAct = menu.addAction(tr("Open with Audacious") + countLabel);
    openAct->setToolTip(tr("Play the selected track(s) in Audacious"));

    connect(openAct, &QAction::triggered, this, [this, tracks]() {
        QStringList args;
        for (const TrackRecord &t : tracks)
            args << t.songPath;
        if (!QProcess::startDetached("audacious", args))
            emit statusMessage(tr("Failed to launch Audacious"));
    });

    QAction *queueAct = menu.addAction(tr("Add to Queue in Audacious") + countLabel);
    queueAct->setToolTip(tr("Append the selected track(s) to the Audacious play queue"));

    connect(queueAct, &QAction::triggered, this, [this, tracks]() {
        int queued = 0;
        for (const TrackRecord &t : tracks) {
            // Step 1: append the file to the active playlist
            if (QProcess::execute("audtool", {"playlist-addurl", t.songPath}) != 0) {
                emit statusMessage(tr("Failed to add \"%1\" to Audacious playlist").arg(t.songTitle));
                continue;
            }

            // Step 2: the new entry landed at the end — find its 1-based position
            QProcess lenProc;
            lenProc.start("audtool", {"playlist-length"});
            if (!lenProc.waitForFinished(3000)) {
                emit statusMessage(tr("audtool timed out querying playlist length"));
                continue;
            }
            bool ok = false;
            int pos = lenProc.readAllStandardOutput().trimmed().toInt(&ok);
            if (!ok || pos <= 0) {
                emit statusMessage(tr("Failed to determine playlist position for \"%1\"").arg(t.songTitle));
                continue;
            }

            // Step 3: add that position to the play queue
            if (QProcess::execute("audtool", {"--playqueue-add", QString::number(pos)}) != 0) {
                emit statusMessage(tr("Failed to queue \"%1\" in Audacious").arg(t.songTitle));
                continue;
            }
            ++queued;
        }

        if (queued == 1)
            emit statusMessage(tr("Queued: %1").arg(tracks.first().songTitle));
        else if (queued > 1)
            emit statusMessage(tr("Queued %1 tracks").arg(queued));
    });

    QAction *kid3Act = menu.addAction(tr("Open with kid3"));
    kid3Act->setToolTip(tr("Edit tags for this track in kid3"));

    connect(kid3Act, &QAction::triggered, this, [this, track]() {
        if (!QProcess::startDetached("kid3", {track.songPath}))
            emit statusMessage(tr("Failed to launch kid3"));
    });

    menu.addSeparator();

    QAction *removeAct = menu.addAction(tr("Remove Record"));
    removeAct->setToolTip(tr("Remove this track from the database (file is not deleted)"));

    connect(removeAct, &QAction::triggered, this, [this, track]() {
        // Confirmation dialog — show artist + title so user knows what they're removing
        QString display = track.songTitle;
        if (!track.artist.isEmpty())
            display = track.artist + QStringLiteral(" — ") + track.songTitle;

        int result = QMessageBox::question(
            this,
            tr("Remove Record"),
            tr("Remove \"%1\" from the database?\n\n"
               "The audio file itself will not be deleted.")
                .arg(display),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No);

        if (result == QMessageBox::Yes) {
            emit statusMessage(tr("Removing record: %1...").arg(track.songTitle));
            m_scriptRunner->removeRecord(track.songPath);
        }
    });

    menu.exec(m_tableView->viewport()->mapToGlobal(pos));
}

// ===========================================================================
//  Record removal result handlers
// ===========================================================================

void LibraryView::onRemoveSuccess(const QString &filePath)
{
    Q_UNUSED(filePath)
    emit statusMessage(tr("Record removed successfully"));
    // DSV watcher will trigger model refresh automatically
}

void LibraryView::onRemoveError(const QString &filePath, const QString &message)
{
    Q_UNUSED(filePath)
    emit statusMessage(tr("Remove error: %1").arg(message));
    QMessageBox::warning(this, tr("Remove Failed"), message);
}
