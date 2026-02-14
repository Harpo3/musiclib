#include <QtTest>

class TestDbReader : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {
        // Setup before all tests
    }
    
    void testDummy() {
        QVERIFY(true);
    }
};

QTEST_MAIN(TestDbReader)
#include "test_db_reader.moc"
