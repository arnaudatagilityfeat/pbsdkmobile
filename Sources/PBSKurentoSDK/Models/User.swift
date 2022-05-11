//
//  User.swift
//
//
//  Created by Arnaud Phommasone on 30/12/2021.
//

import WebRTC

public struct Offer : Codable {
    public var sdpOffer: String?
    public var typeMessage: String?
    public var callerUserId: String?
    public var calleeUserId: String?
    public var sessionId: String?
    public var user: User?
    
}

public struct Session : Codable {
  public var id: String?
}

public struct Track : Codable {
  public var stream: String?
  public var userId: String?
  public var trackKind: String?
}

public class PeerConnection{
    public let pc : RTCPeerConnection?
    public let remoteVideoId : Int?
    public let userId : String?
    public let user : User?
    init(user: User?, userId: String? = nil, pc: RTCPeerConnection?, remoteVideoId: Int?) {
            self.user = user
            if userId == nil {
                self.userId = user?.userId
            }
        else {
            self.userId = userId
        }
            
            self.pc = pc
            self.remoteVideoId = remoteVideoId
    }
}


public struct Event : Codable {
    public let exceptionId: String?
    public let explanation: String?
    public let typeMessage: String?
    public let timestamp: String?
    public let answer: String?
    public let calleeUserId :String?
    public let userId :[String]?
    public let mediaType :String?
    public let newStatus :Bool?
    public let user : UserResponse?
    public let sdpMLineIndex: Int32?
    public let sdpMid: String?
    public let candidate: String?
    public let spd: String?
    public let completed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case exceptionId
        case explanation
        case typeMessage
        case timestamp
        case answer
        case calleeUserId
        case userId
        case mediaType
        case newStatus
        case user
        case sdpMLineIndex
        case sdpMid
        case candidate
        case spd
        case completed
    }
}

public struct UserResponse : Codable{
    var userId : String?
    var id : String?
    var socketId : String?
    var firstName : String?
    var lastName : String?
    var userName : String?
    var email : String?
    var avatar : String?
    var initials : String?
    public let mediaType :String?
    public let newStatus :Bool?
}


public struct Login : Codable {
    public var login: User?
}

public struct User : Codable {
    public var userName: String?
    public var userId: String?
    public var codableUserId: String?
    public var firstName: String?
    public var lastName: String?
    public var initials: String?
    public var avatar: String?
    public var email: String?
    
    enum CodingKeys: String, CodingKey {
        case userName = "login"
        case userId = "id"
        case codableUserId = "userId"
        case firstName
        case lastName
        case initials
        case avatar
        case email
    }
    
    func provide() -> String { 
        return userId ?? ""
    }
    
    
}

public struct IceServer : Codable {
    let urls: [String]
    let username: String
    let credentials: String
    let ttl: Int
    
    enum CodingKeys: String, CodingKey {
        case urls = "uris"
        case username
        case credentials = "password"
        case ttl
    }
    
    func provide() -> String {
        return credentials ?? ""
    }
}

public struct PeerMediaStatus {
    var pc: RTCPeerConnection?
    var remoteVideoId: Int?
    var audioStatus: Bool?
    var videoStatus: Bool?
}

//public struct UserMediaConstraint : Codable {
//    let audioConfig: Bool
//    let videoConfig: Bool
//    let audioOuputId: Int
//    
//    enum CodingKeys: String, CodingKey {
//        case audioConfig
//        case videoConfig
//        case audioOutputId
//    }
//}

public class RTCIceCandidateRich {
    public var calleeUserId: String?
    public var candidate: String?
    public var rtcIceCandidate : RTCIceCandidate?
    init(calleeUserId: String?, candidate: String?, rtcIceCandidate: RTCIceCandidate?) {
        self.calleeUserId = calleeUserId
        self.candidate = candidate
        self.rtcIceCandidate = rtcIceCandidate
    }
}

