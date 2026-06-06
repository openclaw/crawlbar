import Foundation

public extension CrawlAppManifest {
    enum ExecutionKind: String, Codable, Equatable, Sendable {
        case local
        case ssh
    }

    struct Execution: Codable, Equatable, Sendable {
        public var kind: ExecutionKind
        public var kindConfigID: String?
        public var targetConfigID: String?
        public var runAsConfigID: String?
        public var remoteEnvFileConfigID: String?
        public var remoteBinary: String?

        public init(
            kind: ExecutionKind = .local,
            kindConfigID: String? = nil,
            targetConfigID: String? = nil,
            runAsConfigID: String? = nil,
            remoteEnvFileConfigID: String? = nil,
            remoteBinary: String? = nil)
        {
            self.kind = kind
            self.kindConfigID = kindConfigID
            self.targetConfigID = targetConfigID
            self.runAsConfigID = runAsConfigID
            self.remoteEnvFileConfigID = remoteEnvFileConfigID
            self.remoteBinary = remoteBinary
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case kindConfigID = "kind_config_id"
            case targetConfigID = "target_config_id"
            case runAsConfigID = "run_as_config_id"
            case remoteEnvFileConfigID = "remote_env_file_config_id"
            case remoteBinary = "remote_binary"
        }
    }
}
