import UIKit
import WebRTC
import PromiseKit
import CoreMedia

/// PBSKurento.js line 18
/// Ref : https://www.swiftbysundell.com/articles/constructing-urls-in-swift/
public class PBSKurentoConfig {
    let PBSKurentoApiServer: String?
    let PBSKurentoAdminApiServer: String?
    let token: String?
    let iceServers: String?
    let videoContainerDivId: String?
    let localVideoElemId: String?
    public init(PBSKurentoApiServer: String?,PBSKurentoAdminApiServer: String?,token: String?) {
        self.PBSKurentoApiServer = PBSKurentoApiServer
        self.PBSKurentoAdminApiServer = PBSKurentoAdminApiServer
        self.token = token
        self.iceServers = nil
        self.videoContainerDivId = nil
        self.localVideoElemId = nil
    }
}

/// This is the PBS
/// # Overview
public class PBSKurentoSDK : NSObject, RTCPeerConnectionDelegate {
    /// MARK: - Properties
    private var callState: PSBKurentoState = .NoCall
    private var isLoopback: Bool = false
    
    /// PeerConnection, returns pc
    private var pc: RTCPeerConnection?
    /// The WebRTC local stream
    private var localStream: RTCMediaStream?
    /// The WebRTC current local audio track
    private var localAudioTrack: RTCAudioTrack?
    /// The WebRTC current local video track
    private var localVideoTrack: RTCVideoTrack?
    /// The WebRTC media capturer (front or back camera)
    private var videoCapturer: RTCVideoCapturer?
    /// The WebRTC remote video tracks
    private var remoteVideoTracks: [Int: RTCVideoTrack]? = [:]
    /// A map of all the peer connection ids and its audio and video status, returns HashMap of {pc, remoteVideoId, audioStatus, videoStatus}
    private var peerMediaStatus: [String: PeerMediaStatus]? = [:]
    /// PeerConnections, returns HashMap of {pc, remoteVideoId, userName}
    private var peerConnections: [String: PeerConnection]? = [:]
    /// Remote PeerConnections, returns pcs
    private var remoteFeedsNum: Int = 0
    /// Indicate if audio should be used or not.
    private var enableAudio: Bool = true
    /// Indicate if video has been muted. Read only
    private var enableVideo: Bool = true
    /// Indicate if video has been muted. Read only
    private var isMutedVideo: Bool = false
    /// Indicate if audio has been muted. Read only
    private var isMutedAudio: Bool = false
    
    /// A lock for handling the events
    let eventsGroup = DispatchGroup()
    
    /// Work item to fetch Events from WebRTC
    private var fetchEventWorkItem: DispatchWorkItem?
    
    /// Local renderer
    #if arch(arm64)
    var localRenderer : RTCMTLVideoView?
    #else
    var localRenderer : RTCEAGLVideoView?
    #endif
    
    /// Callback when there's remote render views being displayed
    public var onRenderRemoteView: ((RTCVideoTrack?, Int, String, Bool)->Void)? = nil
    
    /// Callback when there's a local render view being displayed
    public var onRenderLocalView: ((RTCVideoTrack?)->Void)? = nil
    
    /// Callback when there's a local or remote render views being removed
    public var onRemovedRemoteView: ((RTCVideoTrack?, Int, Bool)->Void)? = nil
    
    /// Callback when there's a user media status changes
    public var onUserMediaStatusChanged: ((Int, String, Bool)->Void)? = nil
    
    /// Callback when there's a change of connection
    public var onConnected: ((Bool)->Void)? = nil
    
    /// Callback when there's a user left the room
    public var onLeavedUsers: (([Int])->Void)? = nil
    
    private var stopEventPolling: Bool = false
    private let mediaConstrains = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                   kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    /// Self user object (e.g: { userId, username } )
    private var selfUserObject: User?
    private var session : Session?
    private var roomHash : String?
    private var isConnected : Bool = false
    private var retries: Int = 0
    private var earlyCandidates: [String: [RTCIceCandidateRich]]? = [:]
    
    /// earlyUserJoins, returns HashMap of { [User] }
    private var earlyUserJoins: [String: User]? = [:]
    private var eventsHandlers: EventHandlers?
    
    private var publisherJoined: Bool = false
    
    private static let peerConnectionFactory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    private var iceServers: [IceServer] = []
    private var token: String?
    
    public var httpClient: HttpApi = HttpApi(baseUrl: nil, token: nil, adminBaseUrl: nil)
    
    /// Constructor
    /// - Parameter config: the configuration file holding the base Url, admin base Url, token and iceServers
    public init(config: PBSKurentoConfig?) {
        if let config = config, config.PBSKurentoApiServer != nil {
            httpClient = HttpApi(baseUrl: config.PBSKurentoApiServer, token: config.token, adminBaseUrl: config.PBSKurentoAdminApiServer)
//            selfUserObject = config.selfUserObject
            eventsHandlers = EventHandlers()
        }
    }
    
    /// Constructor
    /// - Parameter config: the configuration file holding the base Url, admin base Url, token and iceServers
    public init(PBSKurentoApiServer: String?, token: String?, PBSKurentoAdminApiServer: String?) {
            httpClient = HttpApi(baseUrl: PBSKurentoApiServer, token: token, adminBaseUrl: PBSKurentoAdminApiServer)
//            selfUserObject = config.selfUserObject
            eventsHandlers = EventHandlers()
    }
    
    // We have to set up the original claler
    
    // It's important to set the selfUserObject later
    public func setSelfUserObject(userId: String? = nil,
                             userName: String? = nil,
                             codableUserId: String? = nil,
                             firstName: String? = nil,
                             lastName: String? = nil,
                             initials: String? = nil,
                             avatar: String? = nil,
                             email: String? = nil) -> Promise<Void>{
        if self.selfUserObject == nil {
            self.selfUserObject = User()
        }
        self.selfUserObject?.userId = userId
        self.selfUserObject?.avatar = avatar
        self.selfUserObject?.initials = initials
        self.selfUserObject?.firstName = firstName
        self.selfUserObject?.lastName = lastName
        self.selfUserObject?.email = email
        self.selfUserObject?.userName = userName
        return Promise()
    }
    
    public func getUserObject() -> User? {
        return self.selfUserObject
    }
    
    /*
     Start listening to application state
     */
    public func startListening() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    /*
     Stop listening to application state
     */
    public func stopListening() {
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    /*
     Return the remote media as array
     */
    public func getRemoteVideoTracks() -> [RTCVideoTrack?]{
        if let keys = self.remoteVideoTracks?.keys {
            var results: [RTCVideoTrack?] = []
            for key in keys {
                results.append(self.remoteVideoTracks?[key])
            }
            return results
        }
        return []
    }
    /*
     Return the number of tracks available
     */
    
    public func remoteVideoTracksCount() -> Int{
        return self.remoteVideoTracks?.keys.count ?? 0
    }
    
    /*
     Return the remoteview, username for a given index
     */
    
    public func getRemoteVideoTrack(index: Int) -> RTCVideoTrack?{
        let tracks = self.getRemoteVideoTracks()
        if tracks.count <= (index + 1) {
            return tracks[index]
        }
        return nil
    }
    
    /*
     * Create New Kurento Framework User
     * @param body - object
     * @example
     * createUser(['firstName': 'firstName', 'lastName': 'lastName', 'username': user, 'email': 'user@email.com'])
     */
    
    public func createUser(body: [String: Any]) -> Promise<User?> {
        // This method call is only needed if userId doesn't exist in KF
        // UserId will be updated with the id of this new created user
        let (promise, seal) = Promise<User?>.pending()
        
        firstly {
            httpClient.request(ApiRequestEndpoint.createUser(), type: User.self, body: body, httpMethod: HttpMethod.post.rawValue)
        }
        .then { user -> Promise<(User?, IceServer?)> in
            self.selfUserObject = user
            if let username = body["login"] as? String {
                self.selfUserObject?.userName = username
            }
            return self.requestTurnCredentials().map { (self.selfUserObject, $0) }
        }
        .done({ (user, iceServer) in
            seal.fulfill(user)
        })
        .catch { error in
            seal.reject(error)
        }
        
        return promise
    }
    
    // Convenient method
    public func createUser(with username: String) -> Promise<[String:Any]> {
       // This method call is only needed if userId doesn't exist in KF
       // UserId will be updated with the id of this new created user
       let (promise, seal) = Promise<[String:Any]>.pending()
       
       firstly {
           createUser(body: ["login" : username])
       }
       .done({ (user) in
           let userData = try JSONEncoder().encode(user)
           let userMap = try JSONSerialization.jsonObject(with: userData, options: .allowFragments) as! [String: Any]
           seal.fulfill(userMap)
       })
       .catch { error in
           seal.reject(error)
       }
       
       return promise
    }
    
    public func disconnect() -> Promise<Bool> {
        let (promise, seal) = Promise<Bool>.pending()
        firstly {
            leave()
        }
        .done { _ in
            seal.fulfill(true)
        }
        .catch { error in
            print(error)
            seal.fulfill(false)
        }
        return promise
    }
    
    public func startCall(username: String? = nil, sessionId: String){
        #if arch(arm64)
        self.localRenderer = RTCMTLVideoView(frame: CGRect.zero)
        self.localRenderer?.videoContentMode = .scaleAspectFill
        #else
        self.localRenderer = RTCEAGLVideoView(frame: CGRect.zero)
        #endif
        if let username = username {
            firstly {
                self.createUser(body: ["login": username])
            }
            .then { user -> Promise<Bool> in
                if user != nil{
                    return Promise.value(true)
                }
                return Promise.init(error: DataError.invalidResponse)
            }
            .then({ gotValue -> Promise<Bool> in
                if gotValue == true {
                    return self.join(localRenderer: self.localRenderer, sessionId: sessionId)
                }
                return Promise.init(error: DataError.invalidData)
            })
            .done { _ in
                self.startCaptureLocalVideo(renderer: self.localRenderer)
            }.catch { error in
                print(error)
            }
        }
        else {
            firstly {
                self.join(localRenderer: self.localRenderer, sessionId: sessionId)
            }
            .done { _ in
                self.startCaptureLocalVideo(renderer: self.localRenderer)
            }.catch { error in
                print(error)
            }
        }
    }
    
    // Convenient method
    public func startCall(sessionId: String) -> Promise<Bool> {
        #if arch(arm64)
        self.localRenderer = RTCMTLVideoView(frame: CGRect.zero)
        self.localRenderer?.videoContentMode = .scaleAspectFill
        #else
        self.localRenderer = RTCEAGLVideoView(frame: CGRect.zero)
        #endif
        
        let (promise, seal) = Promise<Bool>.pending()
        
        firstly {
            self.join(localRenderer: self.localRenderer, sessionId: sessionId)
        }
        .done { _ in
            self.startCaptureLocalVideo(renderer: self.localRenderer)
            seal.fulfill(true)
        }.catch { error in
            print(error)
            seal.reject(error)
        }
        
        return promise
    }
    
    public func requestTurnCredentials() -> Promise<IceServer?>{
        return Promise<IceServer?> { seal in
            if let userId = self.selfUserObject?.userId {
                firstly {
                    httpClient.request(ApiRequestEndpoint.getTurnCredentials(userId: userId), type: IceServer.self, httpMethod: HttpMethod.get.rawValue)
                }
                .done({ result in
                    if let iceServer = result{
                        self.iceServers.append(iceServer)
                        print(self.iceServers)
                        print("result iceserver: ",iceServer)
                        seal.fulfill(iceServer)
                    }
                })
                .catch { error in
                    seal.reject(error)
                }
            }
            
        }
    }
    
    func onIceStateChange(pc: RTCPeerConnection, event:RTCSignalingState, isRemote: Bool) {
        
        if let userId =  self.userId(for: pc){
            let pcObj = self.peerConnections?[userId]
            let videoId = pcObj?.remoteVideoId
            print("\(pc) \(isRemote ? "Remote" : "") videoId:\(String(describing: videoId)) ICE state: \(pc.iceConnectionState.rawValue)")
            
            switch pc.connectionState {
                case .closed :
                print("connection state closed")
                break
                case .connected:
                    print("connection state connected")
                    break
                case .new:
                    print("connection state new")
                    break
                case .connecting:
                    print("connection state connecting")
                    break
                case .disconnected:
                    print("connection state disconnected")
                    break
                case .failed:
                    print("connection state failed")
                    break
                default:
                    break
            }
        }
    }
    
    func onConnectionStateChange(pc: RTCPeerConnection, newState: RTCIceConnectionState) {
        print("Connection state change: \(self.getConnectionState(pc: pc))");
        // Need to find the peerconnection associated with pc
        if let userId = self.userId(for: pc) {
                let pcObj = self.peerConnections?[userId]
                if pc.connectionState == .connected {
                    setCallState(nextState: .InCall)
                    if let pcObj = pcObj {
                        eventsHandlers?.onPcConnected(pc: pcObj)
                    }
                }
            else if pc.connectionState == .failed || pc.connectionState == .closed
                {
                    if let userId = pcObj?.userId {
                        removeConnection(userId: userId)
                        
                        // Retrieve all remote Ids and signal they left
                        var remoteVideoIds: [Int] = []
                        if let pc = self.peerConnections?[userId], let remoteVideoId = pc.remoteVideoId {
                            remoteVideoIds.append(remoteVideoId)
                            pc.pc?.close()
                        }
                        self.onLeavedUsers?(remoteVideoIds)
                    }
                }
                else if pc.connectionState == .disconnected && selfUserObject?.userId == pcObj?.userId {
                    stopEventsAndStreams()
                    self.pc?.close()
                }
        }
    }
        
    /*
     * Create Kurento room
     * @param roomConfig - Object (optional)
     * @example
     * createRoom({ permanent: false, ttl: 0, record: false })
     * Returns room object
     */
    public func createRoom() -> Promise<Rooms?> {
        let (promise, seal) = Promise<Rooms?>.pending()
        print("create room for user \(self.selfUserObject?.userId)");
        
        if let userId = self.selfUserObject?.userId {
            firstly {
                httpClient.request(ApiRequestEndpoint.createRoom(), type: Rooms.self, body: ["userId": userId ,
                                                                                             "permanent":  false,
                                                                                             "ttl": 2592000,
                                                                                             "record":  false], httpMethod: HttpMethod.post.rawValue)
            }
            .done { room in
                seal.fulfill(room)
            }
            .catch { error in
                seal.reject(error)
            }
        }
        else {
            seal.reject(DataError.invalidData)
        }
        
        return promise
    }
    
    // Convenient method
    public func createRoom(with userId: String? = nil) -> Promise<[String:Any]> {
        if userId != nil {
            self.selfUserObject?.userId = userId
        }
        
        let (promise, seal) = Promise<[String:Any]>.pending()
        firstly {
            createRoom()
        }
        .done { room in
            let roomData = try JSONEncoder().encode(room)
            let roomMap = try JSONSerialization.jsonObject(with: roomData, options: .allowFragments) as! [String: Any]
            seal.fulfill(roomMap)
        }
        .catch { error in
            seal.reject(error)
        }
        return promise
    }
    
    public func createRoomAndJoin(with userId: String? = nil) -> Promise<[String:Any]> {
        if userId != nil {
            self.selfUserObject?.userId = userId
        }
        
        let (promise, seal) = Promise<[String:Any]>.pending()
        var roomUuid: String?
        firstly {
            createRoom()
        }
        .then({ room -> Promise<Session?> in
            roomUuid = room?.uuid
            return self.joinSession(roomHash: room?.uuid ?? "")
        })
        .done { room in
            var roomData = try JSONEncoder().encode(room)
            var roomMap = try JSONSerialization.jsonObject(with: roomData, options: .allowFragments) as! [String: Any]
            roomMap["uuid"] = roomUuid
            seal.fulfill(roomMap)
        }
        .catch { error in
            seal.reject(error)
        }
        
//        firstly {
//            joinSession(roomHash: roomHash)
//        }
//        .done({ (session) in
//            let joinSessionData = try JSONEncoder().encode(session)
//            let joinSessionMap = try JSONSerialization.jsonObject(with: joinSessionData, options: .allowFragments) as! [String: Any]
//            seal.fulfill(joinSessionMap)
//        })
//        .catch { error in
//            seal.reject(error)
//        }
//
        return promise
    }
    
    /*
     * Delete Kurento room
     * @param roomConfig - Object (optional)
     * @example
     * deleteRoom()
     * Returns 200 or 500
     */
    public func deleteRoom(roomId: String) -> Promise<Bool> {
        let (promise, seal) = Promise<Bool>.pending()
        firstly {
            httpClient.requestVoid(ApiRequestEndpoint.deleteRoom(roomId: roomId))
        }
        .done { room in
            seal.fulfill(true)
        }
        .catch { error in
            seal.reject(error)
        }
        return promise
    }
    
    public func join(localRenderer: RTCVideoRenderer?, sessionId: String) -> Promise<Bool>{
        // join room via api
        return Promise<Bool> { seal in
            firstly {
                self.joinSession(roomHash: sessionId)
            }
            .then { _ in
                self.initUserMedia(renderer: localRenderer)
            }
            .then { result in
                self.publish()
            }
            // Toggle the media video
            .then({ _ in
                self.changeMediaStatus(shouldMute: false, isVideo: true)
            })
            .done { _ in
                seal.fulfill(true)
            }
            .catch { error in
                seal.reject(error)
            }
        }
    }
    
    /*
     * Join Kurento session, it will join previously created room or passed room id
     * @param config - object
     * @example
     * joinSession({ audio: {object | boolean}, video: {object | boolean}, localVideoContainerId: '', localvideoElemId: '', sessionId: '', roomId: '' })
     */
    public func joinSession(roomHash: String) -> Promise<Session?>{
        let promise = Promise<Session?> { seal in
            self.stopEventPolling = false
            
            //TODO: mock room id
            self.roomHash = roomHash
            
            guard self.roomHash != nil else {
                print(" Missing room hash to join")
                return seal.reject(DataError.invalidData)
            }
            
            guard self.selfUserObject?.userId != nil else {
                print("Missing userId")
                return seal.reject(DataError.invalidData)
            }
            
            //TODO: detect audio/video devices changes
            
            // start join the room
            if let userId = self.selfUserObject?.userId , let roomHash = self.roomHash {
                print("Join Room \(String(describing: self.roomHash))")
                
                firstly {
                    self.httpClient.request(ApiRequestEndpoint.join(roomHash: roomHash), type: Session.self, body: ["userId": userId], httpMethod: HttpMethod.post.rawValue)
                }
                .then { session -> Promise<(User?, Session?)> in
                    self.session = Session(id: session?.id)
                    print("Successful join request to ${roomHash}. Generated sessionId: ${roomSessionId}");
                    return self.addParticipant().map { ($0, session)  }
                }
                .then({ (user, session) -> Promise<Session?> in
                    // TODO: change to addParticipantResult.exceptionId
                    print("participant added! \(user)");
                    return self.getEventsSetup().map { _ in session }
                })
//                .then({ session -> Promise<Session?> in
//                    if !self.isConnected {
//                        print("Not connected")
//                        return Promise<Session?>.value(nil)
//                    }
//                    else {
//                        return self.getEvents().map { _ in session }
//                    }
//                })
                .done({ session in
                    if session == nil {
                        seal.reject(DataError.invalidData)
                    }
                    else {
                        self.getEvents().map { _ in session }
                        seal.fulfill(session)
                    }
                })
                .catch { error in
                    seal.reject(error)
                }
            }
        }
        return promise
    }
    
    // Convenient method
    public func joinSession(with roomHash: String) -> Promise<[String: Any]>{
        let (promise, seal) = Promise<[String:Any]>.pending()
        
        firstly {
            joinSession(roomHash: roomHash)
        }
        .done({ (session) in
            let joinSessionData = try JSONEncoder().encode(session)
            let joinSessionMap = try JSONSerialization.jsonObject(with: joinSessionData, options: .allowFragments) as! [String: Any]
            seal.fulfill(joinSessionMap)
        })
        .catch { error in
            seal.reject(error)
        }
        
        return promise
    }
    
    // Add participant
    public func addParticipant() -> Promise<User?>{
        let (promise, seal) = Promise<User?>.pending()
        if let userId = self.selfUserObject?.userId, let roomUuid = self.roomHash{
            firstly {
                httpClient.request(ApiRequestEndpoint.addParticipant(), type: User.self, body: ["userId": userId, "roomUuid": roomUuid], httpMethod: HttpMethod.post.rawValue)
            }
            .done { user in
                seal.fulfill(user)
            }
            .catch { error in
                seal.reject(error)
            }
        }
        else {
            seal.reject(DataError.invalidData)
        }
        return promise
    }
    
    // Add event
    public func getEventsSetup() -> Promise<Event?>{
        let (promise, seal) = Promise<Event?>.pending()
        if let userId = self.selfUserObject?.userId, let sessionId = self.session?.id {
            print("get events setup for \(sessionId)")
            firstly {
                httpClient.request(ApiRequestEndpoint.getEvents(sessionId: sessionId, userId: userId), type: Event.self, body: [:], httpMethod: HttpMethod.post.rawValue)
            }
            .done { user in
                print("---> setup success: \(user)")
                self.isConnected = true
                seal.fulfill(user)
            }
            .catch { error in
                self.isConnected = false
                seal.reject(error)
            }
        }
        else {
            seal.reject(DataError.invalidData)
        }
        return promise
    }
    
    
    public func getEventV2() -> Promise<Bool>{
        return Promise<Bool> { seal in
            if !self.isConnected {
                seal.reject(DataError.notConnected)
                return
            }}
    }
        
    
    public func getEvents() -> Promise<Bool>{
        return Promise<Bool> { seal in
            if !self.isConnected {
                seal.reject(DataError.notConnected)
                return
            }
            
            if let userId = self.selfUserObject?.userId, let sessionId = self.session?.id {
                firstly {
                    httpClient.request(ApiRequestEndpoint.getEvents(sessionId: sessionId, userId: userId), type: [Event].self, httpMethod: HttpMethod.get.rawValue)
                }
                .then({ events in
                    self.handleEvent(events: events)
                })
                .done { events in
                    self.retries = 0
                    seal.fulfill(true)
                }
                .catch { error in
                    print("getEvent error: \(error)")
                    print("try to reconnect \(self.retries)")
                    
                    self.retries += 1
                    if self.retries > 10 {
                        // Did we just lose the server? :-(
                        
                        print("Lost connection to the server (is it down?)")
                        self.isConnected = false
                        
                        self.eventsHandlers?.onConnected(connected: self.isConnected)
                        self.onConnected?(self.isConnected)
                        return
                    }
                
                    seal.reject(error)
                }
            }
            else {
                print("userId or sessionId are empty...")
            }
            
//            workItem = DispatchWorkItem { // Set the work item with the block you want to execute
//                      self.performSegue(withIdentifier: "introLogin", sender: self)
//                  }
//                  DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(11), execute: workItem!)
            
            fetchEventWorkItem = DispatchWorkItem {
                if self.stopEventPolling{
                    print("Stopped Event Polling")
                } else {
                    firstly {
                        self.getEvents()
                    }
                    .done({ _ in
                    })
                    .catch({ _ in
                    })
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: fetchEventWorkItem!)
            
//            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
//                if self.stopEventPolling{
//                    print("Stopped Event Polling")
//                } else {
//                    firstly {
//                        self.getEvents()
//                    }
//                    .done({ _ in
//                    })
//                    .catch({ _ in
//                    })
//                }
//            }
        }
    }
    
    private func rtcPeerConnections() -> [(RTCPeerConnection?, String?)] {
        // Need to find the peerconnection associated with pc
        if let peerConnections = self.peerConnections {
            let pcs = peerConnections.keys.compactMap { key in
                peerConnections[key]
            }.map { pc in
                    (pc.pc, pc.userId)
                }
            return pcs
        }
        return []
    }
    
    private func userId(for peerConnection: RTCPeerConnection) -> String? {
        let userId = self.rtcPeerConnections().first { (peer, userId) in
            return peer == peerConnection
        }?.1
        return userId
    }
    
    // MARK: Media
    public func startCaptureLocalVideo(renderer: RTCVideoRenderer?) {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer, let renderer = renderer else {
            return
        }
        
        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
            
            // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            
            // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }
        
        capturer.startCapture(with: frontCamera,
                              format: format,
                              fps: Int(fps.maxFrameRate))
    }
    
    func setCallState(nextState: PSBKurentoState) {
        switch (nextState) {
        case .NoCall:
            break;
        case .ProcessingCall:
            break;
        case .InCall:
            break;
        }
        callState = nextState;
    }
    
    // MARK: - RTC Connection
    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = PBSKurentoSDK.peerConnectionFactory.audioSource(with: audioConstrains)
        let audioTrack = PBSKurentoSDK.peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }
    
    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = PBSKurentoSDK.peerConnectionFactory.videoSource()
        
        if #available(iOS 10, *) {
            #if targetEnvironment(simulator)
            self.videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
            #else
            self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
            #endif
        } else {
            // Fallback on earlier versions
        }
        
        let videoTrack = PBSKurentoSDK.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        return videoTrack
    }
    
    /// Initialize user media publishing
    public func initUserMedia(renderer: RTCVideoRenderer?) -> Promise<RTCMediaStream?> {
        // Default to audio/video true if constraints undefined
        struct VideoConfig {
            let width: Int
            let height: Int
            let frameRate: Int
        }
        let mediaStream = Promise<RTCMediaStream?> { seal in
            let streamId = self.selfUserObject?.userId ?? UUID().uuidString
            
            self.localStream = PBSKurentoSDK.peerConnectionFactory.mediaStream(withStreamId: streamId)
            
            // Audio
            let audioTrack = self.createAudioTrack()
            
            self.pc?.add(audioTrack, streamIds: [streamId])
            
            // Video
            let videoTrack = self.createVideoTrack()
            self.localVideoTrack = videoTrack
            self.pc?.add(videoTrack, streamIds: [streamId])
            
            if let renderer = renderer {
                self.localVideoTrack?.add(renderer)
                self.onRenderLocalView?(localVideoTrack)
            }else{
                seal.reject(DataError.invalidData)
            }
            
            if let localVideoTrack = self.localVideoTrack{
                localVideoTrack.isEnabled = true
                self.localStream?.addVideoTrack(localVideoTrack)
                self.localStream?.addAudioTrack(audioTrack)
            }
           
            if let videoTracks = self.localStream?.videoTracks, videoTracks.count > 0, let firstVideoTrack = videoTracks.first {
                print("Using video device: \(String(describing: videoTracks.first?.description))");
                // If we were muted before pass that state to new device
                if self.isMutedVideo == true {
                    firstVideoTrack.isEnabled = false
                }
                
                if localVideoTrack == nil || localVideoTrack?.trackId != videoTracks.first?.trackId {
                    self.localVideoTrack = videoTracks.first
                    if var senders = pc?.senders, let senderIndex = pc?.senders.firstIndex(where: { sender in
                        sender.senderId == videoTracks.first?.trackId
                    }) {
                        let sender = senders[senderIndex]
                        senders.replaceSubrange(senderIndex.asRange, with: [sender])
                    }
                }
            }
            //TODO: make the local stream make it crash
            if let audioTracks = self.localStream?.audioTracks, audioTracks.count > 0 {
                print("Using audio device: \(String(describing: audioTracks.first?.description))");
                if localAudioTrack == nil || localAudioTrack?.trackId != audioTracks.first?.trackId {
                    self.localAudioTrack = audioTracks.first
                    if var senders = pc?.senders, let senderIndex = senders.firstIndex(where: { sender in
                        sender.senderId == audioTracks.first?.trackId
                    }) {
                        let sender = senders[senderIndex]
                        senders.replaceSubrange(senderIndex.asRange, with: [sender])
                    }
                }
            }
            seal.fulfill(self.localStream)
        }
        return mediaStream
    }
    
    /// Unmute video
    public func changeMediaStatus(shouldMute: Bool, isVideo: Bool) -> Promise<Bool> {
        if localStream == nil {
            return Promise.init(error: DataError.invalidMediaStream)
        }
        
        let mediaType = isVideo ? "video" : "audio"
        
        if isVideo == true {
            if let videoTracks = localStream?.videoTracks, videoTracks.isEmpty {
                return Promise.init(error: DataError.noVideoTrack)
            }
            
            localStream?.videoTracks.first?.isEnabled = !shouldMute
            isMutedVideo = shouldMute
        }
        else {
            if let audioTracks = localStream?.audioTracks, audioTracks.isEmpty {
                return Promise.init(error: DataError.noAudioTrack)
            }
            
            localStream?.audioTracks.first?.isEnabled = !shouldMute
            isMutedAudio = shouldMute
        }
        
        guard let sessionId = self.session?.id, let userId = self.selfUserObject?.userId else {
            return Promise.init(error: DataError.invalidData)
        }
        
        return Promise<Bool> { seal in
            firstly {
                self.httpClient.requestVoid(ApiRequestEndpoint.updateUserMediaStatus(sessionId: sessionId), body: ["userId": userId, "mediaType": mediaType, "newStatus": !shouldMute], httpMethod: HttpMethod.post.rawValue)
            }
            .done { value in
                if value == true {
                    seal.fulfill(true)
                }
                else {
                    seal.reject(DataError.invalidResponse)
                }
            }
            .catch { error in
                seal.reject(DataError.invalidResponse)
            }
        }
    }
    
    func toggleMute(isVideo: Bool) -> Promise<Bool> {
        if localStream == nil {
            return Promise.init(error: DataError.invalidMediaStream)
        }
        guard let isMuted: Bool = isMuted(video: isVideo) else {
            return Promise.init(error: DataError.invalidData)
        }
        
        let mute = !isMuted
        print("toggle \(mute ? "mute" : "unmute") \(isVideo ? "video" : "audio")")
        
        if isVideo {
            if let videoTracks = localStream?.videoTracks, videoTracks.isEmpty {
                return Promise.init(error: DataError.noVideoTrack)
            }
            localStream?.videoTracks.first?.isEnabled = !mute
            isMutedVideo = mute
        }
        else {
            if let audioTracks = localStream?.audioTracks, audioTracks.isEmpty {
                return Promise.init(error: DataError.noAudioTrack)
            }
            localStream?.audioTracks.first?.isEnabled = !mute
            isMutedAudio = mute
        }
        
        let mediaType = isVideo ? "video" : "audio"
        guard let sessionId = self.session?.id, let userId = self.selfUserObject?.userId else {
            return Promise.init(error: DataError.invalidData)
        }
        
        return Promise<Bool> { seal in
            firstly {
                self.httpClient.requestVoid(ApiRequestEndpoint.updateUserMediaStatus(sessionId: sessionId), body: ["userId": userId, "mediaType": mediaType, "newStatus": true], httpMethod: HttpMethod.post.rawValue)
            }
            .done { value in
                if value == true {
                    seal.fulfill(true)
                }
                else {
                    seal.reject(DataError.invalidResponse)
                }
            }
            .catch { error in
                seal.reject(DataError.invalidResponse)
            }
        }
    }
    
    /// Is Muted function
    func isMuted(video: Bool) -> Bool? {
        guard localStream != nil else {
            return nil
        }
        
        if video {
            if localStream?.videoTracks == nil || localStream?.videoTracks.count == 0 || isMutedVideo == true {
                return true
            }
            if let isEnabled = localStream?.videoTracks.first?.isEnabled {
                return !isEnabled
            }
        }
        else {
            if localStream?.audioTracks == nil || localStream?.audioTracks.count == 0 || isMutedVideo == true {
                return true
            }
            if let isEnabled = localStream?.audioTracks.first?.isEnabled {
                return !isEnabled
            }
        }
        return nil
    }
    
    /// Leave
    func leave() -> Promise<Bool> {
        guard let sid = self.session?.id, let userId = self.selfUserObject?.userId else {
            print("Missing sessionId or userId to leave")
            return Promise.init(error: DataError.invalidData)
        }
        
        stopEventPolling = true
        self.session = nil
        fetchEventWorkItem?.cancel()
        setCallState(nextState: .NoCall)
        
        if localStream != nil {
            var videoTracks: [RTCVideoTrack] = []
            var audioTracks: [RTCAudioTrack] = []
            if let videos = self.localStream?.videoTracks {
                videoTracks.append(contentsOf: videos)
            }
            if let audios = self.localStream?.audioTracks {
                audioTracks.append(contentsOf: audios)
            }
            
            for audioTrack in audioTracks {
                self.localStream?.removeAudioTrack(audioTrack)
            }
            
            for videoTrack in videoTracks {
                self.localStream?.removeVideoTrack(videoTrack)
            }
        }
        return self.httpClient.requestVoid(ApiRequestEndpoint.leave(sessionId: sid, userId: userId), httpMethod: HttpMethod.delete.rawValue)
    }
    
    /// Connect and call, loopback stream to Kurento, broken after refactor FIXME
    public func loopback() {
        print("loopback()")
        setCallState(nextState: .ProcessingCall)
        isLoopback = true
        let rtcConf = RTCConfiguration()
        rtcConf.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let mediaConstraints = RTCMediaConstraints.init(mandatoryConstraints: nil, optionalConstraints: nil)
        
        pc = PBSKurentoSDK.peerConnectionFactory.peerConnection(with: rtcConf, constraints: mediaConstraints, delegate: self)
        
        if let audioTracks = localStream?.audioTracks {
            for audioTrack in audioTracks {
                print("Add track: ")
                print(audioTrack)
                localStream?.addAudioTrack(audioTrack)
            }
        }
        if let videoTracks = localStream?.videoTracks {
            for videoTrack in videoTracks {
                print("Add track: ")
                print(videoTrack)
                localStream?.addVideoTrack(videoTrack)
            }
        }
        
        // make the api call to /offer through HttpAPI
        let constraints = RTCMediaConstraints.init(mandatoryConstraints: nil, optionalConstraints: nil)
        pc?.offer(for: constraints)
    }
    
    /// Publish, starting sending media to kf
    public func publish() -> Promise<Bool> {
        print("publish()")
        return Promise<Bool> { seal in
            setCallState(nextState: .ProcessingCall)
            
            guard let userId = self.selfUserObject?.userId else {
                // Need to throw an error
                print("missing self user id")
                seal.reject(DataError.invalidData)
                return
            }
            
            let rtcConf = RTCConfiguration()
            
//            ▿ 0 : IceServer
//              ▿ urls : 2 elements
//                - 0 : "turn:12.208.21.119:3478?transport=udp"
//                - 1 : "turn:12.208.21.119:443"
//              - username : "1652113421:6277ee8da9e11679f54ab55b"
//              - credentials : "EI5MbnO19XeXjjWE7nC2LBK2qBM="
//              - ttl : 86400

            let username = iceServers[0].username
            let credential = iceServers[0].credentials
            
            rtcConf.iceServers = self.iceServers.map { iceServer in
                RTCIceServer(urlStrings: iceServer.urls, username: username, credential: credential)
            }
            // We want to add the default google STUN
            rtcConf.iceServers.append(RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]))
        
            let remoteVideoId = 0
            // Unified plan is more superior than planB
            rtcConf.sdpSemantics = .unifiedPlan
            
            // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
            rtcConf.continualGatheringPolicy = .gatherContinually
            
            // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
            let constraints = RTCMediaConstraints(mandatoryConstraints: mediaConstrains,
                                                   optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue,
                                                                         "RtpDataChannels":kRTCMediaConstraintsValueTrue, kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue, kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue])
            // TODO: need to create property peerConnections and assign that objcet above
            self.pc = PBSKurentoSDK.peerConnectionFactory.peerConnection(with: rtcConf, constraints: constraints, delegate: self)
            let newPeerConnection = PeerConnection(user: self.selfUserObject, pc: self.pc, remoteVideoId: remoteVideoId)
            self.peerConnections?[userId] = newPeerConnection
            self.pc?.delegate = self
            
            // adding local tracks, outbound
            let videoTracks = localStream?.videoTracks ?? []
            let audioTracks = localStream?.audioTracks ?? []
            var tracks: Array<RTCMediaStreamTrack> = []
            tracks.append(contentsOf: videoTracks)
            tracks.append(contentsOf: audioTracks)
            
            tracks.forEach { track in
                if let streamId = self.localStream?.streamId {
                    self.pc?.add(track, streamIds: [streamId])
                }
                
                if var localPeerMediaStatus = peerMediaStatus?[userId] {
                    if track.kind == "audio" {
                        localPeerMediaStatus.audioStatus = track.isEnabled
                    }
                    else if track.kind == "video" {
                        localPeerMediaStatus.videoStatus = track.isEnabled
                    }
                }
                else {
                    var peerMediaStatus = PeerMediaStatus(pc: self.pc, remoteVideoId: remoteVideoId, audioStatus: nil, videoStatus: nil)
                    if track.kind == "audio" {
                        peerMediaStatus.audioStatus = track.isEnabled
                    }
                    else if track.kind == "video" {
                        peerMediaStatus.videoStatus = track.isEnabled
                    }
                    self.peerMediaStatus?[userId] = peerMediaStatus
                }
            }
            
            self.pc?.transceivers.forEach({ transceiver in
                transceiver.direction = .sendOnly
            })
            
            // send offer SDP
            let sessionId = self.session?.id
            
            firstly {
                self.createOffer(pc: self.pc)
            }
            .then { offer in
                self.setLocalDescription(pc: self.pc, sdp: offer)
            }
            .then({ offer -> Promise<RTCSessionDescription> in
                return Promise<RTCSessionDescription> { offerSeal in
                    if let sessionId = sessionId {
                        var selfUserObjectAsString = ""
                        let jsonEncoder = JSONEncoder()
                        if let selfUser = self.selfUserObject {
                            let jsonData = try jsonEncoder.encode(selfUser)
                            selfUserObjectAsString = String(data: jsonData, encoding: String.Encoding.utf8) ?? ""
                        }
                        
                        var offerRequest = Offer()
                        offerRequest.typeMessage = "OFFER"
                        offerRequest.callerUserId = userId
                        offerRequest.calleeUserId = userId
                        offerRequest.sessionId = sessionId
                        offerRequest.sdpOffer = offer.sdp
                        offerRequest.user = self.selfUserObject
                        offerRequest.user?.codableUserId = self.selfUserObject?.userId
//                        let body: [String:Any] = ["typeMessage": "OFFER","callerUserId":userId,"calleeUserId":userId,"sessionId":sessionId,"sdpOffer":offer.sdp, "user": selfUserObjectAsString]
                        
                        
                        firstly {
//                            self.httpClient.requestVoid(ApiRequestEndpoint.offer(), body: body, httpMethod: HttpMethod.post.rawValue)
                            self.httpClient.requestOfferSDP(ApiRequestEndpoint.offer(), offer: offerRequest, httpMethod: HttpMethod.post.rawValue)
                        }
                        .done { _ in
                            offerSeal.fulfill(offer)
                        }
                        .catch { error in
                            offerSeal.reject(error)
                        }
                    }
                    else {
                        offerSeal.reject(DataError.invalidData)
                    }
                }
            })
            .done { offer in
                seal.fulfill(true)
            }
            .catch { error in
                print("Create offer or set description error: \(error)")
                seal.reject(error)
            }
        }
    }
    
    /// Subscribe, shouldn't be necessary to manually subscribe to a user. * This is done automatically when you join a room
    func subscribe(user: inout User) -> Promise<Bool> {
        return Promise<Bool> { seal in
            guard let userId = user.userId else {
                // Need to throw an error
                print("Missing user id")
                seal.reject(DataError.invalidData)
                return
            }
            
            // handle condition where we get multiple subscription request to the same user
            let peerConnectionAlreadyCreated = self.peerConnections?[userId]
            if peerConnectionAlreadyCreated != nil {
                let conState = self.peerConnections?[userId]?.pc?.connectionState
                
                if conState == RTCPeerConnectionState.failed || conState == RTCPeerConnectionState.closed {
                    print(" Re-subscribe...")
                }
                else {
                    seal.reject(DataError.invalidData)
                    return
                }
            }
            
            print("subscribe() \(userId)")
            
            let rtcConf = RTCConfiguration()
            let username = iceServers[0].username
            let credential = iceServers[0].credentials
            rtcConf.iceServers = self.iceServers.map { iceServer in
                RTCIceServer(urlStrings: iceServer.urls, username: username, credential: credential)
            }
            
            // We want to add the default google STUN
            rtcConf.iceServers.append(RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]))
            
            rtcConf.sdpSemantics = .unifiedPlan
            
            // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
            rtcConf.continualGatheringPolicy = .gatherContinually
            
            let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: mediaConstrains,
                                                   optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue,
                                                                         "RtpDataChannels":kRTCMediaConstraintsValueTrue, kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue, kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue])
            
            let pc = PBSKurentoSDK.peerConnectionFactory.peerConnection(with: rtcConf, constraints: mediaConstraints, delegate: self)
            
            remoteFeedsNum += 1
            
            let remoteVideoId = getFirstAvailableVideoContainer()
            
            user.userId = userId
            
            self.peerConnections?[userId] = PeerConnection(user: user, pc: pc, remoteVideoId: remoteVideoId)
            print("subscribe first for \(userId) (remoteId \(remoteVideoId)) with peer connection \(pc)")
            
            if self.enableAudio == true {
                let transceiver = RTCRtpTransceiverInit()
                transceiver.direction = .recvOnly
                pc.addTransceiver(of: .audio, init: transceiver)
            }
            
            if self.enableVideo == true {
                let transceiver = RTCRtpTransceiverInit()
                transceiver.direction = .recvOnly
                pc.addTransceiver(of: .video, init: transceiver)
            }
            
            firstly {
                self.createOffer(pc: pc)
            }
            .then { offer  -> Promise<RTCSessionDescription?> in
                print("Offer to receive from remote user \(userId), SDP:\n\(offer.sdp)");
                if let _ = self.selfUserObject?.userId, let _ = self.session?.id{
                    return self.setLocalDescription(pc: pc, sdp: offer).map { session in
                        return session
                    }
                }
                else {
                    seal.reject(DataError.invalidData)
                    return Promise<RTCSessionDescription?>.value(nil)
                }
            }
            .then { offer -> Promise<Bool> in
                if let offer = offer{
                    if let selfUserId = self.selfUserObject?.userId, let sessionId = self.session?.id{
                        let body: [String:Any] = ["typeMessage": "OFFER","callerUserId":selfUserId,"calleeUserId":userId,"sessionId":sessionId,"sdpOffer":offer.sdp]
                        return self.httpClient.requestVoid(ApiRequestEndpoint.offer(), body: body, httpMethod: HttpMethod.post.rawValue)
                    }else{
                        return Promise<Bool>.value(false)
                    }
                }else{
                    seal.reject(DataError.invalidData)
                    return Promise<Bool>.value(false)
                }
               
            }.done { value in
                if value == false {
                    seal.reject(DataError.invalidData)
                }
                else {
                    seal.fulfill(true)
                }
            }.catch { error in
                print("Create offer or set description error: \(error)")
                seal.reject(error)
            }
        }
    }
    
    // MARK: Async existing WebRTC
    public func setLocalDescription(pc: RTCPeerConnection?, sdp: RTCSessionDescription) -> Promise<RTCSessionDescription> {
        return Promise<RTCSessionDescription> { seal in
            if let pc = pc {
                pc.setLocalDescription(sdp) { error in
                    if error != nil {
                        seal.reject(error!)
                    }
                    else {
                        seal.fulfill(sdp)
                    }
                }
            }
            else {
                seal.reject(DataError.localDescription)
            }
        }
    }
    
    public func setRemoteDescription(pc: RTCPeerConnection?, sdp: RTCSessionDescription) -> Promise<RTCSessionDescription> {
        return Promise<RTCSessionDescription> { seal in
            if let pc = pc {
                pc.setRemoteDescription(sdp) { error in
                    if error != nil {
                        seal.reject(error!)
                    }
                    else{
                        seal.fulfill(sdp)
                    }
                }
            }
            else {
                seal.reject(DataError.remoteDescription)
            }
        }
    }
    
    // MARK: Signaling
    public func createOffer(pc: RTCPeerConnection?) -> Promise<RTCSessionDescription> {
         return Promise<RTCSessionDescription> { seal in
             let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains,
                                                  optionalConstraints: nil)
             
             if let pc = pc {
                 pc.offer(for: constrains) { (offer, error) in
                     print("createOffer: \(String(describing: pc))")
                     guard let offer = offer else {
                         return
                     }
                     seal.fulfill(offer)
                 }
             }
             else {
                 seal.reject(DataError.createOffer)
             }
        }
    }
    
    func getFirstAvailableVideoContainer() -> Int {
        let pcs = self.peerConnections;
        var remoteVidLocationArr: [Int] = []
        pcs?.forEach({ (key: String, pc: PeerConnection) in
            if let remoteVideoId = pc.remoteVideoId, remoteVideoId != 0 {
                remoteVidLocationArr.append(remoteVideoId)
            }
        })
        
        let size = remoteVidLocationArr.count
        
        // Mark vId[i] as visited by making
        // vId[vId[i] - 1] negative.
        // Mark positive the one before missing num
        remoteVidLocationArr.forEach { vId in
            let x = abs(vId)
            if (x - 1 < size && remoteVidLocationArr[x - 1] > 0) {
                remoteVidLocationArr[x - 1] = -remoteVidLocationArr[x - 1]
            }
        }
        
        // Return the first index value at which
        // is positive
        if size > 0{
            for i in 0...(size - 1) {
                if (remoteVidLocationArr[i] > 0){
                    return i + 1; // 1 is added becuase indexes
                }
            }
        }
        
        // start from 0
        return size + 1;
    }
    
    func muteAudio() {
        guard self.localStream != nil else {
            print("Invalid local MediaStream")
            return
        }
        print("mute audio")
        if let audioTracks = self.localStream?.audioTracks {
            audioTracks.first?.isEnabled = false
            self.isMutedAudio = true
        }else{
            print("No audio track")
        }
    }
    
    func removeConnection(userId: String) {
        if let connection = self.peerConnections?[userId], let userIdLocal = self.selfUserObject?.userId{
            if(userId != userIdLocal){
                self.remoteFeedsNum -= 1
            }
            self.peerConnections?.removeValue(forKey: userId)
            self.peerMediaStatus?.removeValue(forKey: userId)
        }
    }
    
    func removeConnections(userIds: [String]) {
        var leftUsers : [String: PeerConnection]?
        if  let connections = self.peerConnections{
            if connections.count == 0 {
                print("Missing peer connections to remove")
            }
            
            connections.keys.forEach(){ key in
                if(userIds.contains(key)){
                    leftUsers?[key] = connections[key]
                }
            }
            
            // Retrieve all remote Ids
            var remoteVideoIds: [Int] = []
            for userId in userIds {
                if let pc = self.peerConnections?[userId], let remoteVideoId = pc.remoteVideoId {
                    remoteVideoIds.append(remoteVideoId)
                }
                self.removeConnection(userId: userId)
            }
            self.onLeavedUsers?(remoteVideoIds)
        }
    }
    
    func stopEventsAndStreams() {
        self.stopEventPolling = true
        self.session?.id = nil
        self.setCallState(nextState: .NoCall)
        
        var userIds: [String] = []
        
        self.peerConnections?.keys.forEach(){userId in
            userIds.append(userId)
        }
        self.removeConnections(userIds: userIds)
    }
    
    func addIceCandidateToPc(rtcConnection: RTCPeerConnection?, candidateObject: RTCIceCandidateRich?) {
        if let userId = self.selfUserObject?.userId{
            let isLocalPubStream : Bool  = candidateObject?.calleeUserId == userId
            if candidateObject == nil {
                if let rtcIceCandidate = candidateObject?.rtcIceCandidate{
                    rtcConnection?.remove([rtcIceCandidate])
                }
            }else{
                if let rtcIceCandidate = candidateObject?.rtcIceCandidate{
                    rtcConnection?.add(rtcIceCandidate)
                    if let rtcConnection = rtcConnection {
                        self.onAddIceCandidateSuccess(pc: rtcConnection, isLocal: isLocalPubStream)
                    }
                    else
                    {
                        print("\(String(describing: pc)) \(isLocalPubStream ? "local" : "remote") failed to add ICE Candidate:")
                        self.onAddIceCandidateError(pc: pc, isLocal: isLocalPubStream)
                    }
                    
                }
            }
        }
        
        
    }
    func onAddIceCandidateSuccess(pc: RTCPeerConnection?, isLocal: Bool) {
        print("\(String(describing: pc)) \(isLocal ? "local" : "remote") addIceCandidate success")
    }
    
    func onAddIceCandidateError(pc: RTCPeerConnection?, isLocal: Bool) {
        print("\(String(describing: pc)) \(isLocal ? "local" : "remote") failed to add ICE Candidate")
    }
    
    func onJoined(user: UserResponse) -> Promise<Bool> {
        var userData = User(userName: user.userName, userId: user.userId == nil ? user.id : user.userId)
        return self.subscribe(user: &userData)
    }
    
    func onJoin(sessionId: String, joinedUUID:String, selfUser: User,user: UserResponse) -> Promise<Bool> {
        let (promise, seal) = Promise<Bool>.pending()
        var joinBodyNotify: [String: Any] = [:]
        do {
            let joinBodyData = try JSONEncoder().encode(selfUser)
            joinBodyNotify = try JSONSerialization.jsonObject(with: joinBodyData, options: .allowFragments) as! [String: Any]
        }
        catch { }
        firstly {
            self.httpClient.requestVoid(ApiRequestEndpoint.joined(connectedUserId: joinedUUID), body: ["sessionId": sessionId, "user": joinBodyNotify] ,httpMethod: HttpMethod.post.rawValue)
        }.then{ _ -> Promise<Bool> in
            self.removeConnections(userIds: [joinedUUID])
            var userData = User(userName: user.userName, userId: user.userId)
            return self.subscribe(user: &userData)
        }
        .done { _ in
            seal.fulfill(true)
        }
        .catch { error in
            seal.reject(DataError.invalidData)
        }
        return promise
    }
    
    func trySubscribe(user: inout User) -> Promise<Bool> {
        return Promise<Bool> { seal in
            if let userId = user.userId, peerConnections?[userId] != nil {
                print("\(userId) connection already exists")
            }
            else {
                firstly {
                    subscribe(user: &user)
                }
                .done { isDone in
                    seal.fulfill(isDone)
                }
                .catch { error in
                    seal.reject(error)
                }
            }
        }
    }
    
    func subscribeToEarlyUserJoins() -> Promise<Bool> {
        if let keys = earlyUserJoins?.keys {
            // notify remote participant about local user
            let earlyUserJoinsPromises = keys.map { key -> Promise<Bool> in
                guard let sessionId = self.session?.id, var user = earlyUserJoins?[key], let userId = user.userId else {
                    print("subscribeToEarlyUserJoins > The userId is empty")
                    print("subscribeToEarlyUserJoins > The sessionId is empty")
                    return Promise<Bool>.value(false)
                }
                
                let userJson = try! JSONEncoder().encode(user)
                let userString = String(data: userJson, encoding: .utf8)!
                let body: [String: Any] = ["sessionId" : sessionId, "user" : userString]
                
                return Promise<Bool> { seal in
                    firstly {
                        self.httpClient.requestVoid(ApiRequestEndpoint.joined(connectedUserId: userId), body: body, httpMethod:HttpMethod.post.rawValue)
                    }
                    .then({ _ in
                        self.trySubscribe(user: &user)
                    })
                    .done { _ in
                    }
                    .catch { error in
                        seal.reject(error)
                    }
                }
            }
            
            return Promise<Bool> { seal in
                when(fulfilled: earlyUserJoinsPromises).done { results in
                    seal.fulfill(true)
                }
                .catch { error in
                    seal.reject(error)
                }
            }
            
        }
        else {
            return Promise<Bool>.value(false)
        }
    }
    
    func onAnswer(event: Event) -> Promise<Bool> {
        return Promise<Bool>{ seal in
            if  let calleeIdInt = event.calleeUserId, let t = event.answer, let rtcConnection =  self.peerConnections?[calleeIdInt]?.pc,
                    let remoteVideoId =  self.peerConnections?[calleeIdInt]?.remoteVideoId{
                let rtcSessionDescription : RTCSessionDescription = RTCSessionDescription(type: RTCSdpType.answer, sdp: t)
                print("answer then for \(calleeIdInt) (remoteId \(String(describing: remoteVideoId))) with peer connection \(String(describing: rtcConnection))")
                
                firstly {
                    self.setRemoteDescription(pc: rtcConnection, sdp:rtcSessionDescription )
                }.done { data in
                    // Add candidates that arrived before peerconnection creation/offer
                    if let candidates = self.earlyCandidates{
                        if let candidates = candidates[calleeIdInt]{
                            candidates.forEach(){ c in
                                self.addIceCandidateToPc(rtcConnection: rtcConnection, candidateObject: c)
                            }
                            self.earlyCandidates?.removeValue(forKey: calleeIdInt)
                            seal.fulfill(true)
                        }
                    }
                }.catch{ error in
                    seal.reject(error)
                }
                
            }else{
                seal.reject(DataError.invalidData)
            }
        }
    }
    
    func onReconnect(sessionId: String, joinedUUID:String, selfUser: User,user: UserResponse) -> Promise<Bool> {
        var joinBodyNotify: [String: Any] = [:]
        do {
            let joinBodyData = try JSONEncoder().encode(selfUser)
            joinBodyNotify = try JSONSerialization.jsonObject(with: joinBodyData, options: .allowFragments) as! [String: Any]
        }
        catch { }
        return Promise<Bool>{ seal in
            firstly {
                self.httpClient.requestVoid(ApiRequestEndpoint.joined(connectedUserId: joinedUUID),body: ["sessionId": sessionId, "user": joinBodyNotify], httpMethod: HttpMethod.post.rawValue)
            }.then {data ->Promise<Bool>  in
                self.removeConnections(userIds: [joinedUUID])
                var userData = User(userName: user.userName, userId: user.userId)
                return self.subscribe(user: &userData)
            }.done { data in
                seal.fulfill(true)
            }.catch { error in
                seal.reject(error)
            }
            
        }
    }
    
    func onMuteAllUsers(userId: String, sessionId: String) -> Promise<Bool> {
        return self.httpClient.requestVoid(ApiRequestEndpoint.updateUserMediaStatus(sessionId: sessionId), body: ["userId": userId, "mediaType":"audio", "newStatus":false],httpMethod: HttpMethod.post.rawValue)
    }
    
    
    
    
    func handleEvent(events : [Event]?) -> Promise<Bool> {
        if self.session?.id == nil || events == nil {
            print("Missing sessionId and/or events to handle")
            return Promise.init(error: DataError.invalidData)
        }
        
        let (promise, seal) = Promise<Bool>.pending()
        if let events = events  {
            events.forEach(){ event in
                eventsGroup.enter()
                var joinedUUID : String?
                if  let eventType = event.typeMessage{
                    switch(eventType){
                    case ServerEventType.answer.rawValue:
                        firstly {
                            self.onAnswer(event: event)
                        }.done { data in
                            seal.fulfill(true)
                            self.eventsGroup.leave()
                        }.catch { error in
                            seal.reject(error)
                            self.eventsGroup.leave()
                        }
                        break
                        
                    case ServerEventType.joined.rawValue:
                        print("(joined) start!")
                        // We got notified about a previously joined participant
                        if let userId = event.user?.userId == nil ? event.user?.id : event.user?.userId, let user = event.user {
                            self.removeConnections(userIds: [userId])
                            firstly {
                                self.onJoined(user:user)
                            }.done { data in
                                seal.fulfill(true)
                                self.eventsGroup.leave()
                            }.catch { error in
                                seal.reject(error)
                                self.eventsGroup.leave()
                            }
                            print("(joined) done!")
                        }else{
                            print("(joined) error: userId or user are nil!")
                            seal.reject(DataError.invalidData)
                            self.eventsGroup.leave()
                        }
                        
                        break
                    case ServerEventType.join.rawValue:
                        print("(join) start!")
                        if let user = event.user, let userId = user.userId, let selfUser = self.selfUserObject, let sessionId = self.session?.id{
                            joinedUUID = userId
                            // if not my join, subscribe to user
                            if let joinedUUID = joinedUUID{
                                if joinedUUID != selfUser.userId{
                                    // if publisher join already arrived, subscribe to user and send joined to him
                                    if publisherJoined == true {
                                        firstly {
                                            self.onJoin(sessionId: sessionId, joinedUUID: joinedUUID, selfUser: selfUser, user: user)
                                        }.done { data in
                                            seal.fulfill(true)
                                            self.eventsGroup.leave()
                                        }.catch { error in
                                            seal.reject(error)
                                            self.eventsGroup.leave()
                                        }
                                    }
                                    else {
                                        print("adding early user join: \(joinedUUID)")
                                        // if publisher join has not arrived yet, add to list of early user joins
                                        seal.reject(DataError.publisherAlreadyJoined)
                                        let userData = User(userName: user.userName, userId: user.userId)
                                        earlyUserJoins?[joinedUUID] = userData
                                        self.eventsGroup.leave()
                                    }
                                }
                                else {
                                    print("publisher joined, subscribe to early user joins")
                                    publisherJoined = true
                                    
                                    firstly {
                                        subscribeToEarlyUserJoins()
                                    }
                                    .done { value in
                                        if value == true {
                                            seal.fulfill(value)
                                        }
                                        else {
                                            seal.reject(DataError.subscribeToEarlyUserJoinsFailed)
                                        }
                                        self.eventsGroup.leave()
                                    }
                                    .catch { error in
                                        seal.reject(error)
                                        self.eventsGroup.leave()
                                    }
                                }
                            }
                        }else{
                            seal.reject(DataError.invalidData)
                        }
                        break
                    case ServerEventType.iceCandidate.rawValue:
                        if let calleeInt = event.calleeUserId, let candidate = event.candidate{
                            if let remotePeer = self.peerConnections?[calleeInt]{
                                print("(iceCandidate) calleInt \(calleeInt) was added before")
                                let rtcConnection = remotePeer.pc
                                self.addIceCandidateToPc(rtcConnection: rtcConnection, candidateObject: RTCIceCandidateRich(calleeUserId: calleeInt, candidate: candidate, rtcIceCandidate: RTCIceCandidate(sdp: candidate, sdpMLineIndex: event.sdpMLineIndex ?? 0, sdpMid: event.sdpMid)))
                            }else{
                                print("(iceCandidate) calleInt \(calleeInt) was never added before")
                                var earlyCandidateUserList = self.earlyCandidates?[calleeInt] ?? []
                                earlyCandidateUserList.append(RTCIceCandidateRich(calleeUserId: calleeInt, candidate: candidate, rtcIceCandidate: RTCIceCandidate(sdp: candidate, sdpMLineIndex: event.sdpMLineIndex ?? 0, sdpMid:  event.sdpMid)))
                                self.earlyCandidates?[calleeInt] = earlyCandidateUserList
                            }
                        }else {
                            seal.reject(DataError.invalidData)
                        }
                        self.eventsGroup.leave()
                        break
                    case ServerEventType.reconnect.rawValue:
                        print("(reconnect) start!")
                        // A participant just rejoined
                        if let user = event.user{
                            joinedUUID = user.userId
                            if joinedUUID != self.selfUserObject?.userId{
                                if let sessionId = self.session?.id, let userLocal = self.selfUserObject, let joinedUUID = joinedUUID{
                                    firstly {
                                        self.onReconnect(sessionId: sessionId, joinedUUID: joinedUUID, selfUser: userLocal, user: user)
                                    }.done { data in
                                        seal.fulfill(true)
                                        self.eventsGroup.leave()
                                    }.catch { error in
                                        seal.reject(error)
                                        self.eventsGroup.leave()
                                    }
                                    
                                }else {
                                    seal.reject(DataError.invalidData)
                                }
                            }
                        }else {
                            seal.reject(DataError.invalidData)
                        }
                    case ServerEventType.closeSession.rawValue:
                        print("(closeSession) start!")
                        self.stopEventsAndStreams()
                        self.eventsHandlers?.destroyedSession()
                        print("(closeSession) done!")
                        self.eventsGroup.leave()
                        break
                    case ServerEventType.closeConnection.rawValue:
                        print("(closeConnection) start!")
                        if let userId = event.userId {
                            self.removeConnections(userIds: userId)
                            print("(closeConnection) done!")
                        }else{
                            seal.reject(DataError.invalidData)
                        }
                        self.eventsGroup.leave()
                        break
                    case ServerEventType.updateUserMediaStatus.rawValue:
                        print("(updateUserMediaStatus) start!")
                        if let user = event.user ,let userId = user.userId, let mediaType = user.mediaType, let newStatus = user.newStatus{
                            var peerMediaStatus =  self.peerMediaStatus?[userId]
                            // modify peer's audio/video status
                            if mediaType == "audio"{
                                peerMediaStatus?.audioStatus = newStatus
                            } else if mediaType == "video"{
                                peerMediaStatus?.videoStatus = newStatus
                            }
                            
                            // Notify handlers that something changed
                            if let pc = self.peerConnections?[userId], let remoteVideoId = pc.remoteVideoId {
                                print("### remoteVideoId \(remoteVideoId)")
                                print("### mediaType \(mediaType)")
                                print("### newStatus \(newStatus)")
                                let mediaType = mediaType
                                let status = newStatus
                                self.onUserMediaStatusChanged?(remoteVideoId, mediaType, status)
                            }
                            
                            if let remoteVideoId = peerMediaStatus?.remoteVideoId, let status = self.peerMediaStatus?.values{
                                let streamPropertyChangedObject = [
                                    "userId": userId,
                                    "username": self.selfUserObject?.userName ?? "",
                                    "mediaType": mediaType,
                                    "newStatus": newStatus,
                                    "remoteVideoId": remoteVideoId,
                                    "peerMediaStatus": status
                                ] as [String : Any]
                                
                                //TODO: setRemoteContainerClass(mediaType, newStatus, remoteVideoId);
                                self.eventsHandlers?.streamPropertyChanged(streamPropertyChanged: streamPropertyChangedObject)
                            }
                            print("(updateUserMediaStatus) done!")
                        }
                        else{
                            seal.reject(DataError.invalidData)
                        }
                        self.eventsGroup.leave()
                        break
                    case ServerEventType.muteAllUsersAudio.rawValue:
                        print("(muteAllUsersAudio) start!")
                        if let userId = self.selfUserObject?.userId,let sessionId = self.session?.id{
                            event.userId?.forEach({ id in
                                if id != userId{
                                    self.muteAudio()
                                    firstly {
                                        self.onMuteAllUsers(userId: userId, sessionId: sessionId)
                                    }.done { data in
                                        seal.fulfill(true)
                                        self.eventsGroup.leave()
                                    }.catch { error in
                                        seal.reject(error)
                                        self.eventsGroup.leave()
                                    }
                                }
                            })
                        }else{
                            seal.reject(DataError.invalidData)
                        }
                        break
                    default:
                        seal.reject(DataError.invalidData)
                    }
                }else{
                    seal.reject(DataError.invalidData)
                }
                
            }
        }else{
            seal.reject(DataError.invalidData)
        }
        return promise
    }
}

class EventHandlers {
    func onConnected(connected: Bool) {
        print("connected? \(connected)")
    }
    
    func getUserMediaError(gumError: String) {
        print("Err \(gumError)")
    }
    
    func onJoined(sessionId: String, isConnected: Bool) {
        if isConnected {
            print("Not connected")
        }
        print("Joined to \(sessionId)")
    }
    
    func onPcConnected(pc: PeerConnection) {
        print("pc connected! \(pc)")
    }
    
    func onTrack(track: Track) {
        print("new track! \(track)")
    }
    
    func leavedUsers (leavedUsers: [String: PeerConnection]?) {
        print("leaved users! \(String(describing: leavedUsers))")
    }
    
    func destroyedSession () {
        print("destroyed!")
    }
    
    //TODO: type of streamPropertyChanged
    func streamPropertyChanged (streamPropertyChanged: [String : Any]) {
        print("streamPropertyChanged \(streamPropertyChanged)")
    }
    
    //TODO: type of usersAudioLevels
    func usersAudioLevels (usersAudioLevels: Any) {
        print("usersAudioLevels \(usersAudioLevels)")
    }
}

// MARK: - PeerConnection Delegeates
extension PBSKurentoSDK {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("iceconnectionstatechange")
        let userId = self.userId(for: peerConnection)
        print("userID found for peerconnection \(String(describing: userId))")
        let isRemote = userId == self.selfUserObject?.userId
        onIceStateChange(pc: peerConnection, event: stateChanged, isRemote: isRemote)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        // TODO: this is the equivalent of below from the PBSDK javascript code
        onConnectionStateChange(pc: peerConnection, newState: newState)
        
        // We need to close those peer connection after the state = close
        if newState == .closed {
            peerConnection.close()
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let userId = self.userId(for: peerConnection), let pc = self.peerConnections?[userId], let remoteVideoId = pc.remoteVideoId, let rtcPc = pc.pc, userId != self.selfUserObject?.userId {
            print("GotRemoteStream \(remoteVideoId) \(userId)  \(pc) --- \(pc.user?.userName)")
            
            let rfIndex = remoteVideoId
            
            if let remoteVideoTrack = rtcPc.transceivers.first(where: { $0.mediaType == .video })?.receiver.track as? RTCVideoTrack {
                    rtcPc.add(remoteVideoTrack, streamIds: [rtcPc.localStreams.first?.streamId ?? "0"])
                    self.remoteVideoTracks?[rfIndex] = remoteVideoTrack
                    // Mute by default and no username is ""
                    let usename = pc.user?.userName ?? ""
                    self.onRenderRemoteView?(remoteVideoTrack, rfIndex, usename, false)
            }
        }
    }
    
    private func getConnectionState(pc: RTCPeerConnection) -> String {
        switch pc.connectionState {
        case .connected:
            return "connected"
        case .new:
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnected:
            return "disconnected"
        case .failed:
            return "failed"
        case .closed:
            return "closed"
        @unknown default:
            return "default"
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if let userId = self.selfUserObject?.userId ,let sessionId = self.session?.id, let serverUrl = candidate.serverUrl, let sdpMid = candidate.sdpMid {
            let body : [String:Any] = [
                "typeMessage": "ICE_CANDIDATE",
                "candidate": serverUrl,
                "callerUserId": userId,
                "calleeUserId": userId,
                "sessionId": sessionId,
                "sdpMid": sdpMid,
                "sdpMLineIndex": candidate.sdpMLineIndex,
            ]
            let result = firstly(execute: {
                self.httpClient.requestVoid(ApiRequestEndpoint.iceCandidates(), body: body, httpMethod: HttpMethod.post.rawValue)
            })
            .then({ _ -> Promise<Bool> in
                return Promise { _ in
                    let result = after(seconds:1).then { _ -> Promise<Bool> in
                        self.httpClient.requestVoid(ApiRequestEndpoint.iceCandidates(), body: body, httpMethod: HttpMethod.post.rawValue)
                     }
                    print("to silence warning : \(result)")
                }
            })
            .done { _ in
                print("icecandidate done!!!")
            }
            print("to silence warning : \(result)")
        }else{
            print("peerConnection error")
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        if let userId = self.userId(for: peerConnection), let pc = self.peerConnections?[userId], let remoteVideoId = pc.remoteVideoId, userId != self.selfUserObject?.userId {
            print("GotRemoteStream \(remoteVideoId) \(userId)  \(pc)")
            
            let rfIndex = remoteVideoId
            
            self.remoteVideoTracks?.removeValue(forKey: rfIndex)
            
            self.onLeavedUsers?([rfIndex])
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("peerConnectionShouldNegotiate with \(peerConnection)")
    }
}

/// Application state changes
extension PBSKurentoSDK {
    @objc internal func appMovedToBackground() {
        
    }

    @objc internal func appMovedToForeground() {
        
    }
}

extension Int {
    var asRange: Range<Int> {
        return self..<self+1 as Range<Int>
    }
}
