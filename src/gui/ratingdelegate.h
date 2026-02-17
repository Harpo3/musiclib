#pragma once

#include <QStyledItemDelegate>

class RatingDelegate : public QStyledItemDelegate
{
    Q_OBJECT

public:
    explicit RatingDelegate(QObject *parent = nullptr);

    // Render stars in the cell
    void paint(QPainter *painter,
               const QStyleOptionViewItem &option,
               const QModelIndex &index) const override;

    // Reserve enough space for 5 stars
    QSize sizeHint(const QStyleOptionViewItem &option,
                   const QModelIndex &index) const override;

    // Handle mouse click to determine new rating
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

    // Calculate which star (1-5) was clicked given x position in cell
    int starAtPosition(const QStyleOptionViewItem &option, int x) const;

    static constexpr int MAX_STARS   = 5;
    static constexpr int STAR_WIDTH  = 18; // px per star
    static constexpr int STAR_HEIGHT = 18;

    const QString FILLED_STAR  = QString::fromUtf8("\u2605"); // ★
    const QString EMPTY_STAR   = QString::fromUtf8("\u2606"); // ☆
};
