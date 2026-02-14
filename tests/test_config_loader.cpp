#include <QtTest>

class TestConfigLoader : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {
        // Setup before all tests
    }
    
    void testDummy() {
        QVERIFY(true);
    }
};

QTEST_MAIN(TestConfigLoader)
#include "test_config_loader.moc"
