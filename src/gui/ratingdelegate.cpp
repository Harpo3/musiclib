#include "ratingdelegate.h"
#include "librarymodel.h"

#include <QPainter>
#include <QMouseEvent>
#include <QApplication>
#include <QAbstractItemView>
#include <QSortFilterProxyModel>

RatingDelegate::RatingDelegate(QObject *parent)
    : QStyledItemDelegate(parent)
{
}

void RatingDelegate::setView(QAbstractItemView *view)
{
    m_view = view;
}

void RatingDelegate::paint(QPainter *painter,
                           const QStyleOptionViewItem &option,
                           const QModelIndex &index) const
{
    // Draw standard background (handles selection highlight)
    QStyledItemDelegate::paint(painter, option, index);

    int rating = ratingFromIndex(index);

    // Determine how many stars to show as filled:
    // If this cell is being hovered, preview that star count instead
    int displayStars = rating;
    bool isHovered = (m_hoveredStar > 0 && m_hoveredIndex.isValid()
                      && m_hoveredIndex == index);
    if (isHovered)
        displayStars = m_hoveredStar;

    // Build star string: filled stars + empty stars
    QString stars;
    for (int i = 1; i <= MAX_STARS; ++i)
        stars += (i <= displayStars) ? FILLED_STAR : EMPTY_STAR;

    // Choose text colour
    QColor starColor;
    if (option.state & QStyle::State_Selected) {
        starColor = Qt::white;
    } else if (isHovered) {
        starColor = QColor(255, 200, 50);   // brighter gold for hover preview
    } else {
        starColor = QColor(218, 165, 32);   // goldenrod for committed rating
    }

    painter->save();
    painter->setPen(starColor);

    QFont font = painter->font();
    font.setPixelSize(STAR_HEIGHT - 2);
    painter->setFont(font);

    // Left-align stars within the cell with a small margin
    QRect textRect = option.rect.adjusted(2, 0, 0, 0);
    painter->drawText(textRect, Qt::AlignVCenter | Qt::AlignLeft, stars);
    painter->restore();
}

QSize RatingDelegate::sizeHint(const QStyleOptionViewItem &option,
                                const QModelIndex &index) const
{
    Q_UNUSED(option)
    Q_UNUSED(index)
    return QSize(MAX_STARS * STAR_WIDTH + 4, STAR_HEIGHT + 4);
}

bool RatingDelegate::editorEvent(QEvent *event,
                                  QAbstractItemModel *model,
                                  const QStyleOptionViewItem &option,
                                  const QModelIndex &index)
{
    Q_UNUSED(model)

    // Only handle events on the Stars (GroupDesc) column
    if (index.column() != static_cast<int>(TrackColumn::GroupDesc))
        return false;

    // --- Hover tracking ---
    if (event->type() == QEvent::MouseMove) {
        QMouseEvent *mouseEvent = static_cast<QMouseEvent *>(event);
        int star = starAtPosition(option, mouseEvent->pos().x());

        if (star < 1 || star > MAX_STARS) {
            // Mouse moved outside the star area within the cell
            clearHover();
            return false;
        }

        // Only repaint if something actually changed
        if (index != m_hoveredIndex || star != m_hoveredStar) {
            QPersistentModelIndex oldIndex = m_hoveredIndex;

            m_hoveredIndex = index;
            m_hoveredStar  = star;

            // Repaint the old hovered cell (if different) and the new one
            if (m_view) {
                if (oldIndex.isValid() && oldIndex != index)
                    m_view->update(oldIndex);
                m_view->update(index);
            }
        }
        return false;   // don't consume — let the view handle selection etc.
    }

    // --- Mouse leaves the cell entirely ---
    if (event->type() == QEvent::Leave) {
        clearHover();
        return false;
    }

    // --- Click handling (existing logic) ---
    if (event->type() != QEvent::MouseButtonRelease)
        return false;

    QMouseEvent *mouseEvent = static_cast<QMouseEvent *>(event);
    if (mouseEvent->button() != Qt::LeftButton)
        return false;

    int clickedStar = starAtPosition(option, mouseEvent->pos().x());
    if (clickedStar < 1 || clickedStar > MAX_STARS)
        return false;

    int currentRating = ratingFromIndex(index);

    // Clicking the same star as current rating toggles to 0 (unrated)
    int newRating = (clickedStar == currentRating) ? 0 : clickedStar;

    // Clear hover state now that a click was committed
    clearHover();

    // Resolve source row through proxy model if present
    const QSortFilterProxyModel *proxy =
        qobject_cast<const QSortFilterProxyModel *>(index.model());
    int sourceRow = proxy
        ? proxy->mapToSource(index).row()
        : index.row();

    emit ratingChanged(sourceRow, newRating);
    return true;
}

int RatingDelegate::ratingFromIndex(const QModelIndex &index) const
{
    // Try UserRole first (numeric), fall back to DisplayRole string
    QVariant v = index.data(Qt::UserRole);
    if (v.isValid())
        return v.toInt();
    return index.data(Qt::DisplayRole).toString().trimmed().toInt();
}

int RatingDelegate::starAtPosition(const QStyleOptionViewItem &option, int x) const
{
    // Stars start at left edge of cell + 2px margin
    int relX = x - option.rect.left() - 2;
    if (relX < 0) return 0;
    int star = (relX / STAR_WIDTH) + 1;
    return qBound(1, star, MAX_STARS);
}

void RatingDelegate::clearHover()
{
    if (m_hoveredStar == 0 && !m_hoveredIndex.isValid())
        return;     // nothing to clear

    QPersistentModelIndex oldIndex = m_hoveredIndex;
    m_hoveredIndex = QPersistentModelIndex();
    m_hoveredStar  = 0;

    if (m_view && oldIndex.isValid())
        m_view->update(oldIndex);
}
