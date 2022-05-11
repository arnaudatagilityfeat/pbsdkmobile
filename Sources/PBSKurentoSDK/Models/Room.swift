public struct Rooms : Codable {
        public let id: String
        public let user: User
        public let userLogin: String
        public let phoneClients: String?
        public let participantList: [Int]
        public let uuid: String
        public let sessionId: String?
        public let creatorToken: String
        public let permanent: Bool
        public let ttl: Int
        public let record: Bool
        public let createdAt: String
        public let updatedAt: String
}
