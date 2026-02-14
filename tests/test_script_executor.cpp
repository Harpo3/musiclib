#include <QtTest>

class TestScriptExecutor : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {
        // Setup before all tests
    }
    
    void testDummy() {
        QVERIFY(true);
    }
};

QTEST_MAIN(TestScriptExecutor)
#include "test_script_executor.moc"
