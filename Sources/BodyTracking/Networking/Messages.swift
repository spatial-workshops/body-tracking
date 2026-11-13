import Foundation

let poseClientType = "pose-detector"

/// Sent once after every successful (re)connection.
struct RegisterMessage: Encodable {
    struct Payload: Encodable {
        let clientId: String
        let clientType: String
    }

    let operation = "client.register"
    let payload: Payload

    init(clientId: String) {
        payload = Payload(clientId: clientId, clientType: poseClientType)
    }
}

/// Sent for every processed frame of every tracker window.
struct PublishMessage: Encodable {
    struct Payload: Encodable {
        let topic: String
        let data: [Pose]
    }

    let operation = "pubsub.publish"
    let clientId: String
    let clientType = poseClientType
    let payload: Payload

    init(clientId: String, topic: String, poses: [Pose]) {
        self.clientId = clientId
        payload = Payload(topic: topic, data: poses)
    }
}

enum MessageEncoder {
    static func string<T: Encodable>(_ value: T, pretty: Bool = false) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
