// configuretoolbarsdialog.cpp
// MusicLib Qt GUI — Configure Toolbars Dialog
//
// Copyright (c) 2026 MusicLib Project

#include "configuretoolbarsdialog.h"

#include <KLocalizedString>

#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

// Qt::UserRole slot used to store the int-cast ToolbarItemId in each
// QListWidgetItem so we can retrieve it without relying on display text.
static constexpr int ItemIdRole = Qt::UserRole;

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

ConfigureToolbarsDialog::ConfigureToolbarsDialog(
    const QList<ToolbarItem> &currentItems,
    const QList<ToolbarItem> &availableItems,
    QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle(i18n("Configure Toolbars"));
    setMinimumSize(600, 380);
    setupUi(currentItems, availableItems);
}

// ─────────────────────────────────────────────────────────────────────────────
// UI construction
// ─────────────────────────────────────────────────────────────────────────────

void ConfigureToolbarsDialog::setupUi(
    const QList<ToolbarItem> &currentItems,
    const QList<ToolbarItem> &availableItems)
{
    auto *mainLayout = new QVBoxLayout(this);

    // ── Top section: two list panels with transfer buttons in between ──────
    auto *listsLayout = new QHBoxLayout;

    // ── Left: Available Actions ────────────────────────────────────────────
    auto *leftLayout = new QVBoxLayout;
    auto *availLabel = new QLabel(i18n("Available Actions:"), this);
    leftLayout->addWidget(availLabel);

    m_availableList = new QListWidget(this);
    m_availableList->setAlternatingRowColors(true);
    m_availableList->setIconSize(QSize(22, 22));
    leftLayout->addWidget(m_availableList);

    // ── Middle: Add / Remove transfer buttons ──────────────────────────────
    auto *middleLayout = new QVBoxLayout;
    middleLayout->addStretch();

    m_addBtn    = new QPushButton(i18n("Add →"),      this);
    m_removeBtn = new QPushButton(i18n("← Remove"),   this);
    m_addBtn->setToolTip(i18n("Add the selected action to the toolbar"));
    m_removeBtn->setToolTip(i18n("Remove the selected action from the toolbar"));

    middleLayout->addWidget(m_addBtn);
    middleLayout->addSpacing(6);
    middleLayout->addWidget(m_removeBtn);
    middleLayout->addStretch();

    // ── Right: Current Actions + Move Up / Down ────────────────────────────
    auto *rightLayout = new QVBoxLayout;
    auto *currLabel   = new QLabel(i18n("Current Actions:"), this);
    rightLayout->addWidget(currLabel);

    m_currentList = new QListWidget(this);
    m_currentList->setAlternatingRowColors(true);
    m_currentList->setIconSize(QSize(22, 22));
    rightLayout->addWidget(m_currentList);

    // Move Up / Move Down sit below the current list, right-aligned
    auto *moveLayout = new QHBoxLayout;
    m_moveUpBtn   = new QPushButton(i18n("Move Up"),   this);
    m_moveDownBtn = new QPushButton(i18n("Move Down"), this);
    m_moveUpBtn->setToolTip(i18n("Move the selected action up in the toolbar"));
    m_moveDownBtn->setToolTip(i18n("Move the selected action down in the toolbar"));
    moveLayout->addStretch();
    moveLayout->addWidget(m_moveUpBtn);
    moveLayout->addWidget(m_moveDownBtn);
    rightLayout->addLayout(moveLayout);

    // Give the two list columns equal width
    listsLayout->addLayout(leftLayout,  1);
    listsLayout->addLayout(middleLayout, 0);
    listsLayout->addLayout(rightLayout, 1);

    mainLayout->addLayout(listsLayout);
    mainLayout->addSpacing(4);

    // ── Bottom: OK / Cancel ───────────────────────────────────────────────
    auto *buttonBox = new QDialogButtonBox(
        QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    mainLayout->addWidget(buttonBox);

    // ── Populate lists ─────────────────────────────────────────────────────
    for (const auto &item : availableItems)
        appendItem(m_availableList, item);
    for (const auto &item : currentItems)
        appendItem(m_currentList, item);

    // ── Connect signals ────────────────────────────────────────────────────
    connect(m_addBtn,    &QPushButton::clicked,
            this, &ConfigureToolbarsDialog::onAddItem);
    connect(m_removeBtn, &QPushButton::clicked,
            this, &ConfigureToolbarsDialog::onRemoveItem);
    connect(m_moveUpBtn,   &QPushButton::clicked,
            this, &ConfigureToolbarsDialog::onMoveUp);
    connect(m_moveDownBtn, &QPushButton::clicked,
            this, &ConfigureToolbarsDialog::onMoveDown);

    connect(m_availableList, &QListWidget::itemSelectionChanged,
            this, &ConfigureToolbarsDialog::updateButtons);
    connect(m_currentList,   &QListWidget::itemSelectionChanged,
            this, &ConfigureToolbarsDialog::updateButtons);

    // Double-clicking an Available item adds it; double-clicking a Current
    // item removes it — matches the feel of KDE's own toolbar configurator.
    connect(m_availableList, &QListWidget::itemDoubleClicked,
            this, &ConfigureToolbarsDialog::onAddItem);
    connect(m_currentList,   &QListWidget::itemDoubleClicked,
            this, &ConfigureToolbarsDialog::onRemoveItem);

    connect(buttonBox, &QDialogButtonBox::accepted, this, [this]() {
        emit toolbarConfigChanged(currentItemIds());
        accept();
    });
    connect(buttonBox, &QDialogButtonBox::rejected,
            this, &QDialog::reject);

    updateButtons();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: add one item to a list widget
// ─────────────────────────────────────────────────────────────────────────────

void ConfigureToolbarsDialog::appendItem(QListWidget *list,
                                         const ToolbarItem &item)
{
    auto *lwItem = new QListWidgetItem(list);
    lwItem->setText(item.name);
    lwItem->setData(ItemIdRole, static_cast<int>(item.id));

    if (!item.iconName.isEmpty())
        lwItem->setIcon(QIcon::fromTheme(item.iconName));
}

// ─────────────────────────────────────────────────────────────────────────────
// Slots
// ─────────────────────────────────────────────────────────────────────────────

void ConfigureToolbarsDialog::onAddItem()
{
    QListWidgetItem *sel = m_availableList->currentItem();
    if (!sel)
        return;

    // Move the item over to the Current list (preserves icon & data)
    auto *newItem = new QListWidgetItem(sel->icon(), sel->text());
    newItem->setData(ItemIdRole, sel->data(ItemIdRole));
    m_currentList->addItem(newItem);
    m_currentList->setCurrentItem(newItem);

    delete m_availableList->takeItem(m_availableList->row(sel));

    updateButtons();
}

void ConfigureToolbarsDialog::onRemoveItem()
{
    QListWidgetItem *sel = m_currentList->currentItem();
    if (!sel)
        return;

    // Move the item back to the Available list
    auto *newItem = new QListWidgetItem(sel->icon(), sel->text());
    newItem->setData(ItemIdRole, sel->data(ItemIdRole));
    m_availableList->addItem(newItem);
    m_availableList->setCurrentItem(newItem);

    delete m_currentList->takeItem(m_currentList->row(sel));

    updateButtons();
}

void ConfigureToolbarsDialog::onMoveUp()
{
    const int row = m_currentList->currentRow();
    if (row <= 0)
        return;

    swapCurrentRows(row - 1, row);
    m_currentList->setCurrentRow(row - 1);

    updateButtons();
}

void ConfigureToolbarsDialog::onMoveDown()
{
    const int row = m_currentList->currentRow();
    if (row < 0 || row >= m_currentList->count() - 1)
        return;

    swapCurrentRows(row, row + 1);
    m_currentList->setCurrentRow(row + 1);

    updateButtons();
}

void ConfigureToolbarsDialog::swapCurrentRows(int rowA, int rowB)
{
    QListWidgetItem *a = m_currentList->item(rowA);
    QListWidgetItem *b = m_currentList->item(rowB);

    // Swap every visible and data property so the list repaints both rows
    // correctly without removing/reinserting items (which causes Qt to
    // silently shift the current-row selection before we can restore it).
    const QString  textA = a->text();
    const QIcon    iconA = a->icon();
    const QVariant dataA = a->data(ItemIdRole);

    a->setText(b->text());
    a->setIcon(b->icon());
    a->setData(ItemIdRole, b->data(ItemIdRole));

    b->setText(textA);
    b->setIcon(iconA);
    b->setData(ItemIdRole, dataA);
}

void ConfigureToolbarsDialog::updateButtons()
{
    const int availRow  = m_availableList->currentRow();
    const int currRow   = m_currentList->currentRow();
    const int currCount = m_currentList->count();

    m_addBtn->setEnabled(availRow >= 0);
    m_removeBtn->setEnabled(currRow >= 0);
    m_moveUpBtn->setEnabled(currRow > 0);
    m_moveDownBtn->setEnabled(currRow >= 0 && currRow < currCount - 1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Result accessor
// ─────────────────────────────────────────────────────────────────────────────

QList<ToolbarItemId> ConfigureToolbarsDialog::currentItemIds() const
{
    QList<ToolbarItemId> result;
    result.reserve(m_currentList->count());
    for (int i = 0; i < m_currentList->count(); ++i) {
        result.append(static_cast<ToolbarItemId>(
            m_currentList->item(i)->data(ItemIdRole).toInt()));
    }
    return result;
}
