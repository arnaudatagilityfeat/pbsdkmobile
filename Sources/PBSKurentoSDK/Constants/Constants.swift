import Foundation

/// PSBKurento state

enum PSBKurentoState : Int {
    case NoCall = 0
    case ProcessingCall = 1
    case InCall = 2
}

/// PBSKurento.js line 1-11
enum ServerEventType: String {
    case answer = "ANSWER"
    case iceCandidate = "ICE_CANDIDATE"
    case joined = "JOINED"
    case join = "JOIN"
    case closeSession = "CLOSE_SESSION"
    case closeConnection = "CLOSE_CONNECTION"
    case reconnect = "RECONNECT"
    case updateUserMediaStatus = "UPDATE_USER_MEDIA_STATUS"
    case muteAllUsersAudio = "MUTE_ALL_USERS_AUDIO"
}

/// PBSKurento.js line 12-17
enum GumExceptions: String {
    case unknown = "unknown"
    case notAllowed = "We are unable to access the microphone and/or camera beacause of denied access"
    case notAvailable = "We are unable to detect your microphone and/or camera. Your microphone might be in use by another application."
    case notFound = "We are unable to find your microphone and/or camera"
}

/// HttpApi is a Http manager for Kurento
public typealias Completion<T> = (Result<T, DataError>) -> Void


public enum HttpMethod : String{
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
public enum DataError: Error {
    case network(Error)
    case invalidResponse
    case invalidData
    case decoding
    case localDescription
    case remoteDescription
    case createOffer
    case emptyUserId
    case notConnected
    case invalidMediaStream
    case publisherAlreadyJoined
    case subscribeToEarlyUserJoinsFailed
    case noVideoTrack
    case noAudioTrack
}


public class ApiRequestEndpoint {
    let path: String
    let queryItems: [URLQueryItem]
    public init(path:String, queryItems: [URLQueryItem]){
        self.path = path
        self.queryItems = queryItems
    }

    /// Endpoint to get
    /// - Parameter config: the configuration file holding the base Url, admin base Url, token and iceServers
    public static func createRoom() -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/rooms",
            queryItems: [])
    }
    
    public static func deleteRoom(roomId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/rooms/\(roomId)",
            queryItems: [])
    }
    
    public static func iceCandidates() -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/iceCandidates",
            queryItems: [])
    }
    
    public static func createUser() -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/users",
            queryItems: [])
    }

    public static func addParticipant() -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/participants",
            queryItems: [])
    }

    public static func getTurnCredentials(userId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/turn/\(userId)",
            queryItems: [])
    }

    public static func getEvents(sessionId:String, userId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/sessions/\(sessionId)/users/\(userId)/events",
            queryItems: [])
    }

    public static func join(roomHash: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/sessions/\(roomHash)/notify",
            queryItems: [])
    }

    public static func joined(connectedUserId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/users/\(connectedUserId)/notify",
            queryItems: [])
    }

    static func leave(sessionId: String, userId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/sessions/\(sessionId)/users/\(userId)",
            queryItems: [])
    }

    public static func deleteSession(roomId: String, creatorToken: String?) -> ApiRequestEndpoint {
        if let token = creatorToken  {
            return ApiRequestEndpoint(
                path: "/api/rooms/\(roomId)/\(token)",
                queryItems: [])
        }
        return ApiRequestEndpoint(
            path: "/api/rooms/\(roomId)",
            queryItems: [])
    }

    public static func updateUserMediaStatus(sessionId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/sessions/\(sessionId)/media-status",
            queryItems: [])
    }

    public static func muteAllUsers(sessionId: String, userId: String) -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/sessions/\(sessionId)/\(userId)/mute-all",
            queryItems: [])
    }
    public static func offer() -> ApiRequestEndpoint {
        return ApiRequestEndpoint(
            path: "/api/offers",
            queryItems: [])
    }
}
