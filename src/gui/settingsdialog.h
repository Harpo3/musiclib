// settingsdialog.h
// MusicLib Qt GUI — Settings Dialog (KConfigDialog + musiclib.conf sync)
//
// Three-tab KConfigDialog that mirrors musiclib.conf:
//   Tab 1 — General:           Paths, default rating, download dir
//   Tab 2 — Playback & Mobile: Audacious, KDE Connect, mobile sync
//   Tab 3 — Advanced:          Scripts dir, lock timeout, conky, backups
//
// On Apply/OK:
//   1. KConfigDialog writes to KConfig automatically (fast cache)
//   2. Our settingsChanged slot calls ConfWriter to sync → musiclib.conf
//   3. Signals emitted for any values that require live GUI refresh
//
// Copyright (c) 2026 MusicLib Project

#ifndef SETTINGSDIALOG_H
#define SETTINGSDIALOG_H

#include <KConfigDialog>
#include <QPair>
#include <QList>

class ConfWriter;
class QCheckBox;
class QSpinBox;
class QLineEdit;
class QPushButton;
class QLabel;
class KUrlRequester;

/**
 * @brief Settings dialog with three tabbed pages, backed by KConfigXT.
 *
 * Constructed as a singleton — only one instance exists at a time.
 * KConfigDialog manages this internally via the dialog name.
 */
class SettingsDialog : public KConfigDialog
{
    Q_OBJECT

public:
    explicit SettingsDialog(QWidget *parent, ConfWriter *conf);
    ~SettingsDialog() override;

Q_SIGNALS:
    void databasePathChanged();
    void deviceIdChanged();
    void systemTraySettingsChanged();
    void pollIntervalChanged(int newIntervalMs);

protected Q_SLOTS:
    void updateSettings() override;
    void updateWidgets() override;
    bool hasChanged() override;

private Q_SLOTS:
    void onDetectDevices();

private:
    // ── Page builders ──
    QWidget *createGeneralPage();
    QWidget *createPlaybackMobilePage();
    QWidget *createAdvancedPage();

    // ── Sync helpers ──
    void syncConfToKConfig();
    void syncKConfigToConf();

    // ── Shell variable resolution ──
    void buildVarTable();
    QString resolveConfVars(const QString &raw) const;
    QList<QPair<QString, QString>> m_varTable;

    // ── External reference ──
    ConfWriter *m_conf;

    // ── General page widgets ──
    KUrlRequester *m_musicRepoUrl;
    KUrlRequester *m_databaseUrl;
    KUrlRequester *m_downloadDirUrl;
    QSpinBox      *m_defaultRatingSpin;
    QSpinBox      *m_defaultGroupDescSpin;

    // ── Playback & Mobile page widgets ──
    KUrlRequester *m_audaciousPlaylistsDirUrl;
    QSpinBox      *m_scrobbleThresholdSpin;
    QLineEdit     *m_deviceIdEdit;
    QPushButton   *m_detectDevicesBtn;
    QSpinBox      *m_mobileWindowDaysSpin;
    QSpinBox      *m_minPlayWindowSpin;

    // ── Advanced page widgets ──
    KUrlRequester *m_scriptsDirUrl;
    QSpinBox      *m_lockTimeoutSpin;
    KUrlRequester *m_conkyOutputDirUrl;
    KUrlRequester *m_tagBackupDirUrl;
    QSpinBox      *m_backupAgeDaysSpin;
    QLabel        *m_apiVersionLabel;
    QSpinBox      *m_pollIntervalSpin;

    // System tray behaviour checkboxes (GUI Behavior group)
    QCheckBox *m_closeToTrayCheck    = nullptr;
    QCheckBox *m_minimizeToTrayCheck = nullptr;
    QCheckBox *m_startMinimizedCheck = nullptr;

    // ── Snapshot of conf values at dialog open (for hasChanged) ──
    QMap<QString, QString> m_savedSnapshot;
};

#endif // SETTINGSDIALOG_H