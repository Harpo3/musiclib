#pragma once

#include <QStyledItemDelegate>
#include <QPersistentModelIndex>

class QAbstractItemView;

class RatingDelegate : public QStyledItemDelegate
{
    Q_OBJECT

public:
    explicit RatingDelegate(QObject *parent = nullptr);

    // Give the delegate a reference to the view so it can trigger repaints
    void setView(QAbstractItemView *view);

    // Render stars in the cell (with hover preview)
    void paint(QPainter *painter,
               const QStyleOptionViewItem &option,
               const QModelIndex &index) const override;

    // Reserve enough space for 5 stars
    QSize sizeHint(const QStyleOptionViewItem &option,
                   const QModelIndex &index) const override;

    // Handle mouse click and hover to determine rating / preview
    bool editorEvent(QEvent *event,
                     QAbstractItemModel *model,
                     const QStyleOptionViewItem &option,
                     const QModelIndex &index) override;

signals:
    // Emitted when user clicks a star; sourceRow is the row in the source model
    void ratingChanged(int sourceRow, int newRating) const;

private:
    // Return star count from index data
    int ratingFromIndex(const QModelIndex &index) const;

    // Calculate which star (1-5) corresponds to x position in cell
    int starAtPosition(const QStyleOptionViewItem &option, int x) const;

    // Clear hover state and repaint the previously hovered cell
    void clearHover();

    static constexpr int MAX_STARS   = 5;
    static constexpr int STAR_WIDTH  = 18; // px per star
    static constexpr int STAR_HEIGHT = 18;

    const QString FILLED_STAR  = QString::fromUtf8("\u2605"); // ★
    const QString EMPTY_STAR   = QString::fromUtf8("\u2606"); // ☆

    // Hover tracking
    QAbstractItemView      *m_view        = nullptr;
    QPersistentModelIndex   m_hoveredIndex;          // which cell is hovered
    int                     m_hoveredStar  = 0;      // 1-5, or 0 = none
};
