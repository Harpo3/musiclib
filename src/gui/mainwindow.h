#pragma once

#include <QMainWindow>

class LibraryView;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

private:
    void loadDatabase();

    LibraryView *m_libraryView = nullptr;
};
