//
//  ViewController.swift
//  SkyWay SFU Test 2
//
//  Created by YutaroSakai on 2020/10/20.
//

import UIKit
import SkyWay

class ViewController: UIViewController, UICollectionViewDataSource,
UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    var givenRoomName: String! // 前の画面から画面遷移時に渡されるルーム名変数

    // SkyWay Configuration Parameter
    let apiKey = "4ef87046-d284-414f-9b6b-4b5ab9d4d961"
    let domain = "localhost"

    let roomNamePrefix = "sfu_video_"
    var ownId: String = ""
    let lock: NSLock = NSLock.init()
    var arrayMediaStreams: NSMutableArray = []
    var arrayVideoViews: NSMutableDictionary = [:]

    var peer: SKWPeer?
    var localStream: SKWMediaStream?
    var sfuRoom: SKWSFURoom?

    @IBOutlet var roomNameLabel: UILabel!
    @IBOutlet var submitButton: UIButton!
    @IBOutlet var endButton: UIButton!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet weak var backToTopButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        endButton.isHidden = true

        // peer connection
        let options: SKWPeerOption = SKWPeerOption.init()
        options.key = apiKey
        options.domain = domain
        // options.debug = .DEBUG_LEVEL_ALL_LOGS
        peer = SKWPeer.init(options: options)

        // peer event handling
        peer?.on(.PEER_EVENT_OPEN, callback: {obj in
            self.ownId = obj as! String

            // create local video
            let constraints: SKWMediaConstraints = SKWMediaConstraints.init()
            constraints.maxWidth = 960
            constraints.maxHeight = 540
            constraints.cameraPosition = SKWCameraPositionEnum.CAMERA_POSITION_FRONT

            SKWNavigator.initialize(self.peer!)
            self.localStream = SKWNavigator.getUserMedia(constraints)
        })

        peer?.on(.PEER_EVENT_CLOSE, callback: {obj in
            self.ownId = ""
            SKWNavigator.terminate()
            self.peer = nil
        })
        
        self.collectionView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        super.viewDidDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    deinit {
        localStream = nil
        ownId = ""
        sfuRoom = nil
        peer = nil
    }

    @IBAction func joinRoom(_ sender: Any) {
//        guard let roomName = roomName.text, roomName != "" else {
//            return
//        }
//        self.roomName.resignFirstResponder()
        
        let roomName = givenRoomName // 前の画面から渡された部屋名をSkyWayのコードに渡す
        
        backToTopButton.isHidden = true // 通話を始める前の「戻る」ボタンを見えなくする

        // join SFU room
        let option = SKWRoomOption.init()
        option.mode = .ROOM_MODE_SFU
        option.stream = self.localStream
        sfuRoom = peer?.joinRoom(withName: roomNamePrefix + roomName!, options: option) as? SKWSFURoom

        // room event handling
        sfuRoom?.on(.ROOM_EVENT_OPEN, callback: {obj in
            self.roomNameLabel.text = (obj as? String)?.replacingOccurrences(of: self.roomNamePrefix, with: "")
            self.submitButton.isHidden = true
            self.endButton.isHidden = false
        })

        sfuRoom?.on(.ROOM_EVENT_CLOSE, callback: {obj in
            self.lock.lock()

            self.arrayMediaStreams.enumerateObjects({obj, _, _ in
                let mediaStream: SKWMediaStream = obj as! SKWMediaStream
                let peerId = mediaStream.peerId!
                // remove other videos
                if let video: SKWVideo = self.arrayVideoViews.object(forKey: peerId) as? SKWVideo {
                    mediaStream.removeVideoRenderer(video, track: 0)
                    video.removeFromSuperview()
                    self.arrayVideoViews.removeObject(forKey: peerId)
                }
            })

            self.arrayMediaStreams.removeAllObjects()
            self.collectionView.reloadData()

            self.lock.unlock()

            // leave SFU room
            self.sfuRoom?.offAll()
            self.sfuRoom = nil
        })

        sfuRoom?.on(.ROOM_EVENT_STREAM, callback: {obj in
            let mediaStream: SKWMediaStream = obj as! SKWMediaStream

            self.lock.lock()

            // add videos
            self.arrayMediaStreams.add(mediaStream)
            self.collectionView.reloadData()

            self.lock.unlock()
        })

        sfuRoom?.on(.ROOM_EVENT_REMOVE_STREAM, callback: {obj in
            let mediaStream: SKWMediaStream = obj as! SKWMediaStream
            let peerId = mediaStream.peerId!

            self.lock.lock()

            // remove video
            if let video: SKWVideo = self.arrayVideoViews.object(forKey: peerId) as? SKWVideo {
                mediaStream.removeVideoRenderer(video, track: 0)
                video.removeFromSuperview()
                self.arrayVideoViews.removeObject(forKey: peerId)
            }

            self.arrayMediaStreams.remove(mediaStream)
            self.collectionView.reloadData()

            self.lock.unlock()
        })

        sfuRoom?.on(.ROOM_EVENT_PEER_LEAVE, callback: {obj in
            let peerId = obj as! String
            var checkStream: SKWMediaStream? = nil

            self.lock.lock()

            self.arrayMediaStreams.enumerateObjects({obj, _, _ in
                let mediaStream: SKWMediaStream = obj as! SKWMediaStream
                if peerId == mediaStream.peerId {
                    checkStream = mediaStream
                }
            })

            if let checkStream = checkStream {
                // remove video
                if let video: SKWVideo = self.arrayVideoViews.object(forKey: peerId) as? SKWVideo {
                    checkStream.removeVideoRenderer(video, track: 0)
                    video.removeFromSuperview()
                    self.arrayVideoViews.removeObject(forKey: peerId)
                }
                self.arrayMediaStreams.remove(checkStream)
                self.collectionView.reloadData()
            }

            self.lock.unlock()
        })
    }

    @IBAction func leaveRoom(_ sender: Any) {
        guard let sfuRoom = self.sfuRoom else {
            return
        }
        // leave SFU room
        sfuRoom.close()
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func backToTop(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    // CollectionView Delegate
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return arrayMediaStreams.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath)

        // Configure the cell
        if var view: UIView = cell.viewWithTag(1) {
            switch indexPath.row {
            case 0:
                var video: SKWVideo! = view.viewWithTag(2) as! SKWVideo
                
                self.localStream?.addVideoRenderer(video, track: 0)
                video!.frame = cell.bounds
                view.addSubview(video!)
                video!.setNeedsLayout()
                break
            default:
                if let stream: SKWMediaStream = arrayMediaStreams.object(at: indexPath.row - 1) as? SKWMediaStream {
                    let peerId: String = stream.peerId!
                    // add stream
                    var video: SKWVideo? = arrayVideoViews.object(forKey: peerId) as? SKWVideo
                    if video == nil {
                        video = SKWVideo.init(frame: cell.bounds)
                        stream.addVideoRenderer(video!, track: 0)
                        arrayVideoViews.setObject(video!, forKey: peerId as NSCopying)
                    }
                    video!.frame = cell.bounds
                    view.addSubview(video!)
                    video!.setNeedsLayout()
                }
                break
            }
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width / 2 - 30, height: UIScreen.main.bounds.height / 4)
    }
}


