#include "libraryview.h"
#include "librarymodel.h"

#include <QTableView>
#include <QLineEdit>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QSortFilterProxyModel>

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
    , m_proxyModel(new QSortFilterProxyModel(this))
    , m_tableView(new QTableView(this))
    , m_filterEdit(new QLineEdit(this))
    , m_countLabel(new QLabel(this))
{
    // --- Filter bar ---
    m_filterEdit->setPlaceholderText("Filter by artist, album, or title...");
    m_filterEdit->setClearButtonEnabled(true);

    QHBoxLayout *filterLayout = new QHBoxLayout();
    filterLayout->addWidget(new QLabel("Filter:", this));
    filterLayout->addWidget(m_filterEdit, 1);
    filterLayout->addWidget(m_countLabel);

    // --- Proxy model for filtering and sorting ---
    m_proxyModel->setSourceModel(m_model);
    m_proxyModel->setFilterCaseSensitivity(Qt::CaseInsensitive);
    m_proxyModel->setFilterKeyColumn(-1); // search all columns
    m_proxyModel->setSortRole(Qt::UserRole);

    // --- Table view ---
    m_tableView->setModel(m_proxyModel);
    m_tableView->setSortingEnabled(true);
    m_tableView->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_tableView->setSelectionMode(QAbstractItemView::SingleSelection);
    m_tableView->setAlternatingRowColors(true);
    m_tableView->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_tableView->verticalHeader()->hide();
    m_tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);
    m_tableView->horizontalHeader()->setStretchLastSection(false);
    m_tableView->setSortingEnabled(true);
    m_tableView->sortByColumn(static_cast<int>(TrackColumn::Artist), Qt::AscendingOrder);

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
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Artist),       180);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Album),        180);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::AlbumArtist),  150);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::SongTitle),    220);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::Genre),        100);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::SongLength),    60);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::GroupDesc),     55);
    m_tableView->setColumnWidth(static_cast<int>(TrackColumn::LastTimePlayed),90);
}

void LibraryView::onFilterChanged(const QString &text)
{
    m_proxyModel->setFilterFixedString(text);
    m_countLabel->setText(tr("%1 / %2 tracks")
        .arg(m_proxyModel->rowCount())
        .arg(m_model->rowCount()));
}

void LibraryView::onModelLoadError(const QString &message)
{
    emit statusMessage(tr("Error: %1").arg(message));
}
