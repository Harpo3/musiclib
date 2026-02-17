#pragma once

#include <QWidget>

class QTableView;
class QLineEdit;
class QLabel;
class QSortFilterProxyModel;
class LibraryModel;
class RatingDelegate;
class ScriptRunner;

class LibraryView : public QWidget
{
    Q_OBJECT

public:
    explicit LibraryView(QWidget *parent = nullptr);

    // Load the DSV database file
    bool loadDatabase(const QString &path);

    // Return the number of tracks loaded
    int trackCount() const;

signals:
    void statusMessage(const QString &message);

private slots:
    void onFilterChanged(const QString &text);
    void onModelLoadError(const QString &message);
    void onRatingChanged(int sourceRow, int newRating);
    void onRateSuccess(const QString &filePath, int stars);
    void onRateDeferred(const QString &filePath, int stars);
    void onRateError(const QString &filePath, int stars, const QString &message);

private:
    void setupColumns();

    LibraryModel          *m_model;
    QSortFilterProxyModel *m_proxyModel;
    QTableView            *m_tableView;
    QLineEdit             *m_filterEdit;
    QLabel                *m_countLabel;
    RatingDelegate        *m_ratingDelegate;
    ScriptRunner          *m_scriptRunner;
};
