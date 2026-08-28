import XCTest
import CoreBluetooth
@testable import StandingDesk

final class DeskMovementPolicyTests: XCTestCase {
    func testRawTargetMatchesDeskProtocol() {
        XCTAssertEqual(rawTarget(for: 70, baseHeight: 62), 800)
        XCTAssertEqual(rawTarget(for: 110, baseHeight: 62), 4_800)
        XCTAssertNil(rawTarget(for: 61, baseHeight: 62))
    }

    func testDecodesHeightAndSignedSpeed() throws {
        let reading = try XCTUnwrap(decodeReading(Data([0x20, 0x03, 0x9c, 0xff]), baseHeight: 62))
        XCTAssertEqual(reading.heightCm, 70, accuracy: 0.001)
        XCTAssertEqual(reading.speed, -1, accuracy: 0.001)
    }

    func testNudgeClampsWithoutReversingDirection() {
        XCTAssertEqual(nudgedTarget(currentHeight: 126.5, delta: 1, minimumHeight: 62, maximumHeight: 127), 127)
        XCTAssertNil(nudgedTarget(currentHeight: 128, delta: 1, minimumHeight: 62, maximumHeight: 127))
        XCTAssertEqual(nudgedTarget(currentHeight: 128, delta: -1, minimumHeight: 62, maximumHeight: 127), 127)
    }

    func testRejectsTargetWhoseRoundingCrossesConfiguredLimit() {
        let configuration = DeskConfiguration(
            deskName: "Desk",
            baseHeight: 62,
            minimumHeight: 62.04,
            maximumHeight: 127,
            stepHeight: 1
        )

        XCTAssertThrowsError(try configuration.validatedTarget(62.04))
    }

    func testRequiresTwoStableTargetReadings() {
        var evaluator = DeskMovementEvaluator(targetHeight: 110)
        let first = DeskReading(heightCm: 109.8, speed: 0.1)
        XCTAssertEqual(evaluator.evaluate(first, previous: nil, elapsed: 1), .moving)
        XCTAssertEqual(evaluator.evaluate(DeskReading(heightCm: 110.1, speed: 0), previous: first, elapsed: 1.4), .reached)
    }

    func testDetectsFiveStationaryReadingsAfterGracePeriod() {
        var evaluator = DeskMovementEvaluator(targetHeight: 110)
        var previous = DeskReading(heightCm: 80, speed: 0)
        XCTAssertEqual(evaluator.evaluate(previous, previous: nil, elapsed: 2.1), .moving)
        for index in 1...4 {
            let reading = DeskReading(heightCm: 80, speed: 0)
            XCTAssertEqual(
                evaluator.evaluate(reading, previous: previous, elapsed: 2.1 + Double(index) * 0.4),
                .moving
            )
            previous = reading
        }
        XCTAssertEqual(evaluator.evaluate(DeskReading(heightCm: 80, speed: 0), previous: previous, elapsed: 4.1), .stalled)
    }

    func testRefreshQueuesBehindStopWhenReplacingActiveMovement() {
        XCTAssertEqual(
            deskRequestDisposition(
                replacingMovement: true,
                stopInProgress: false,
                canSendStop: true
            ),
            .stopThenQueue
        )
    }

    func testLatestRequestQueuesWhileStopIsInProgress() {
        XCTAssertEqual(
            deskRequestDisposition(
                replacingMovement: true,
                stopInProgress: true,
                canSendStop: true
            ),
            .queue
        )
    }

    func testConnectingMovementCanBeReplacedBeforeTargetWasSent() {
        XCTAssertEqual(
            deskRequestDisposition(
                replacingMovement: true,
                stopInProgress: false,
                canSendStop: false
            ),
            .activate
        )
    }

    func testStatusReplacementDoesNotAddUnnecessaryStop() {
        XCTAssertEqual(
            deskRequestDisposition(
                replacingMovement: false,
                stopInProgress: false,
                canSendStop: true
            ),
            .activate
        )
    }

    func testCentralStateWaitsForInitialBluetoothResolution() {
        XCTAssertEqual(deskCentralStateDisposition(for: .unknown), .wait)
        XCTAssertEqual(deskCentralStateDisposition(for: .poweredOn), .ready)
    }

    func testCentralStateRejectsUnavailableBluetooth() {
        XCTAssertEqual(deskCentralStateDisposition(for: .poweredOff), .unavailable)
        XCTAssertEqual(deskCentralStateDisposition(for: .unauthorized), .unavailable)
        XCTAssertEqual(deskCentralStateDisposition(for: .unsupported), .unavailable)
        XCTAssertEqual(deskCentralStateDisposition(for: .resetting), .unavailable)
    }

    func testStatusNeedsOnlyTheOutputCharacteristic() {
        XCTAssertTrue(
            deskHasRequiredCharacteristics(
                for: .status,
                hasControl: false,
                hasOutput: true,
                hasInput: false
            )
        )
        XCTAssertFalse(
            deskHasRequiredCharacteristics(
                for: .status,
                hasControl: true,
                hasOutput: false,
                hasInput: true
            )
        )
    }

    func testMovementWaitsForEveryRequiredCharacteristic() {
        XCTAssertTrue(
            deskHasRequiredCharacteristics(
                for: .move,
                hasControl: true,
                hasOutput: true,
                hasInput: true
            )
        )
        XCTAssertFalse(
            deskHasRequiredCharacteristics(
                for: .move,
                hasControl: true,
                hasOutput: true,
                hasInput: false
            )
        )
    }

    func testStopWaitsForTheControlCharacteristic() {
        XCTAssertTrue(
            deskHasRequiredCharacteristics(
                for: .stop,
                hasControl: true,
                hasOutput: false,
                hasInput: false
            )
        )
        XCTAssertFalse(
            deskHasRequiredCharacteristics(
                for: .stop,
                hasControl: false,
                hasOutput: true,
                hasInput: true
            )
        )
    }
}
