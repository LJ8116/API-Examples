//
//  VideoMetadata.swift
//  APIExample
//
//  Created by Dong Yifan on 2020/5/27.
//  Copyright © 2020 Agora Corp. All rights reserved.
//
import Foundation
import UIKit
import AgoraRtcKit
import AGEVideoLayout
import CoreBluetooth
import os.log


let kCharaReadUUID: String = "2A29"

let kActionCmpNoti = "kActionCmpNoti"

let ISDoc = false

struct BTConstants {
    // These are sample GATT service strings. Your accessory will need to include these services/characteristics in its GATT database
    static let serviceUUID = CBUUID(string: "9eca0001-0ee5-a9e0-93f3-a3b50100406e")
    static let readCharacteristicUUID = CBUUID(string: "9eca0003-0ee5-a9e0-93f3-a3b50100406e")
    static let notifyCharacteristicUUID = CBUUID(string: "9ECA0003-0EE5-A9E0-93F3-A3B50100406E")
    static let writeCharacteristicUUID = CBUUID(string: "9eca0002-0ee5-a9e0-93f3-a3b50100406e")
}


class VideoMetadataEntry : UIViewController
{
    @IBOutlet weak var joinButton: AGButton!
    @IBOutlet weak var channelTextField: AGTextField!
    let identifier = "VideoMetadata"
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func doJoinPressed(sender: AGButton) {
        guard let channelName = channelTextField.text else {return}
        //resign channel text field
        channelTextField.resignFirstResponder()
        
        let storyBoard: UIStoryboard = UIStoryboard(name: identifier, bundle: nil)
        // create new view controller every time to ensure we get a clean vc
        guard let newViewController = storyBoard.instantiateViewController(withIdentifier: identifier) as? BaseViewController else {return}
        newViewController.title = channelName
        newViewController.configs = ["channelName":channelName]
        self.navigationController?.pushViewController(newViewController, animated: true)
    }
}

class VideoMetadataMain: BaseViewController {
    @IBOutlet weak var sendMetadataButton: UIButton!
    
    var localVideo = Bundle.loadView(fromNib: "VideoView", withType: VideoView.self)
    var remoteVideo = Bundle.loadView(fromNib: "VideoView", withType: VideoView.self)
    @IBOutlet weak var container: AGEVideoContainer!
    
    var agoraKit: AgoraRtcEngineKit!
    
    // indicate if current instance has joined channel
    var isJoined: Bool = false {
        didSet {
            sendMetadataButton.isHidden = !isJoined
        }
    }
    
    // video metadata to be sent later
    var metadata: Data?
    // metadata lenght limitation
    let MAX_META_LENGTH = 1024



    private var cbManager: CBCentralManager!
    private var cbState = CBManagerState.unknown
    private var cbPeripherals = [CBPeripheral]()
    var startTimer: Timer?
    var startIdx = 0
    var myPeripheral: CBPeripheral?

    var readC: CBCharacteristic?
    var writeC: CBCharacteristic?
    var notifyC: CBCharacteristic?
    var charas = [CBCharacteristic]()

    var msgLabel: UILabel?
    var startActions = [

        Data(referencing: NSData(bytes: [0x3f] as [UInt8], length: 1)),
        Data(referencing: NSData(bytes: [0x53] as [UInt8], length: 1)),
        Data(referencing: NSData(bytes: [0x76, 0x31, 0x39, 0x30, 0x32, 0x33, 0x30, 0x32, 0x31 ] as [UInt8], length: 9)),
        Data(referencing: NSData(bytes: [0x62] as [UInt8], length: 1)),
        Data(referencing: NSData(bytes: [0x72] as [UInt8], length: 1)),
        Data(referencing: NSData(bytes: [0x50, 0x53] as [UInt8], length: 2)),
//        Data(referencing: NSData(bytes: [0x5E] as [UInt8], length: 1)),
        Data(referencing: NSData(bytes: [0x40, 0x25, 0x2A, 0x25, 0x25, 0x2F, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
        Data(referencing: NSData(bytes: [0x40, 0x26, 0x2A, 0x25, 0x25, 0x2D, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
        Data(referencing: NSData(bytes: [0x40, 0x27, 0x2A, 0x25, 0x25, 0x2B, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
        Data(referencing: NSData(bytes: [0x40, 0x28, 0x2A, 0x25, 0x25, 0x29, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
        Data(referencing: NSData(bytes: [0x40, 0x29, 0x2A, 0x25, 0x25, 0x27, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
        Data(referencing: NSData(bytes: [0x40, 0x2A, 0x2A, 0x25, 0x25, 0x26, 0x26, 0x30, 0x25, 0x27, 0x27, 0x25, 0x27, 0x4D, 0x25, 0x25, 0x25, 0x25  ] as [UInt8], length: 18)),
    ]
    var actions = [
        Data(referencing: NSData(bytes: [0x78] as [UInt8], length: 1)), //start
        Data(referencing: NSData(bytes: [0x73] as [UInt8], length: 1)), //pause
        Data(referencing: NSData(bytes: [0x5A] as [UInt8], length: 1)), //recover
        Data(referencing: NSData(bytes: [0x5E] as [UInt8], length: 1)), //stop
        Data(referencing: NSData(bytes: [0x61, 0x32, 0x2B] as [UInt8], length: 3)), //+
        Data(referencing: NSData(bytes: [0x61, 0x32, 0x2D] as [UInt8], length: 3)), //-
    ]
    var actionTitles = [
        "start",
        "pause",
        "recover",
        "stop",
        "+",
        "-"
    ]

    
    override func viewDidLoad(){
        super.viewDidLoad()
        
        sendMetadataButton.isHidden = true
        
        // layout render view
        container.layoutStream(views: [localVideo, remoteVideo])
        
        // set up agora instance when view loadedlet config = AgoraRtcEngineConfig()
        let config = AgoraRtcEngineConfig()
        config.appId = KeyCenter.AppId
        config.areaCode = GlobalSettings.shared.area.rawValue
        // setup log file path
        let logConfig = AgoraLogConfig()
        logConfig.level = .info
        config.logConfig = logConfig
        
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // register metadata delegate and datasource
        agoraKit.setMediaMetadataDataSource(self, with: .video)
        agoraKit.setMediaMetadataDelegate(self, with: .video)
        
        guard let channelName = configs["channelName"] as? String,
              let resolution = GlobalSettings.shared.getSetting(key: "resolution")?.selectedOption().value as? CGSize,
              let fps = GlobalSettings.shared.getSetting(key: "fps")?.selectedOption().value as? AgoraVideoFrameRate,
              let orientation = GlobalSettings.shared.getSetting(key: "orientation")?.selectedOption().value as? AgoraVideoOutputOrientationMode else {return}
        
        // make myself a broadcaster
        agoraKit.setChannelProfile(.liveBroadcasting)
        agoraKit.setClientRole(.broadcaster)
        
        // enable video module and set up video encoding configs
        agoraKit.enableVideo()
        agoraKit.setVideoEncoderConfiguration(AgoraVideoEncoderConfiguration(size: resolution,
                frameRate: fps,
                bitrate: AgoraVideoBitrateStandard,
                orientationMode: orientation))
        
        // set up local video to render your local camera preview
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        // the view to be binded
        videoCanvas.view = localVideo.videoView
        videoCanvas.renderMode = .hidden
        agoraKit.setupLocalVideo(videoCanvas)
        
        // Set audio route to speaker
        agoraKit.setDefaultAudioRouteToSpeakerphone(true)
        
        // start joining channel
        // 1. Users can only see each other after they join the
        // same channel successfully using the same app id.
        // 2. If app certificate is turned on at dashboard, token is needed
        // when joining channel. The channel name and uid used to calculate
        // the token has to match the ones used for channel join
        let option = AgoraRtcChannelMediaOptions()
        let result = agoraKit.joinChannel(byToken: KeyCenter.Token, channelId: channelName, info: nil, uid: 0, options: option)
        if(result != 0) {
            // Usually happens with invalid parameters
            // Error code description can be found at:
            // en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
            // cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
            self.showAlert(title: "Error", message: "joinChannel call failed: \(result), please check your params")
        }


        cbManager = CBCentralManager(delegate: self, queue: nil)

//        NotificationCenter.default.addObserver(self, selector: #selector(actCmpHandler), name: NSNotification.Name(kActionCmpNoti), object: nil)

        let lab: UILabel = UILabel(frame: CGRect(x: 30, y: 360, width: 350, height: 40))
        lab.textColor = .green
        msgLabel = lab
        view.addSubview(lab)

        for ( idx, t) in actionTitles.enumerated() {
            let btn: UIButton = UIButton(type: .roundedRect)

            btn.frame = CGRect(x: 100, y: (lab.frame.origin.y + 30 + CGFloat(idx) * 55.0), width: 150, height: 50)
            btn.setTitle(t, for: .normal)
            view.addSubview(btn)
            btn.tag = idx
            btn.addTarget(self, action: #selector(btnTapped), for: .touchUpInside)
        }
    }
    @objc func btnTapped(btn: UIButton){
        if ISDoc {
            self.metadata = actionTitles[btn.tag].data(using: .utf8)
        }else{
            var endMarker = actions[btn.tag]// NSData(bytes: [0x61, 0x32, 0x2B] as [UInt8], length: 3)

            if btn.tag == 0{
                startAct()
            }else{
                //        charas.forEach { c in
//            myPeripheral?.writeValue(endMarker, for: c, type: .withoutResponse)
                myPeripheral?.writeValue(endMarker, for: writeC!, type: .withoutResponse)
//        }
            }
        }


    }

    func startAct() {
//        DispatchQueue.global().async {
//            self.myPeripheral?.writeValue(self.startActions[0], for: self.writeC!, type: .withoutResponse)
//        }
        startTimer?.invalidate()
        startTimer = Timer.scheduledTimer(withTimeInterval: 0.17, repeats: true) { timer in
            if self.startIdx >= self.startActions.count {
                self.startTimer?.invalidate()
                self.startIdx = 0
                self.myPeripheral?.writeValue(self.actions[0], for: self.writeC!, type: .withoutResponse)
            }else{
                self.myPeripheral?.writeValue(self.startActions[self.startIdx], for: self.writeC!, type: .withoutResponse)
                self.startIdx += 1
            }
        }

    }
    override func willMove(toParent parent: UIViewController?) {
        if parent == nil {
            // leave channel when exiting the view
            if isJoined {
                agoraKit.leaveChannel { (stats) -> Void in
                    LogUtils.log(message: "left channel, duration: \(stats.duration)", level: .info)
                }
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }
    
    /// callback when send metadata button hit
    @IBAction func onSendMetadata() {
        self.metadata = "\(Date())".data(using: .utf8)
    }
    
}
extension VideoMetadataMain: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // In your application, you would address each possible value of central.state and central.authorization
        switch central.state {
        case .resetting:
            os_log("Connection with the system service was momentarily lost. Update imminent")
        case .unsupported:
            os_log("Platform does not support the Bluetooth Low Energy Central/Client role")
        case .unauthorized:
            switch central.authorization {
            case .restricted:
                os_log("Bluetooth is restricted on this device")
            case .denied:
                os_log("The application is not authorized to use the Bluetooth Low Energy role")
            default:
                os_log("Something went wrong. Cleaning up cbManager")
            }
        case .poweredOff:
            os_log("Bluetooth is currently powered off")
        case .poweredOn:
            os_log("Starting cbManager")
//			let matchingOptions = [CBConnectionEventMatchingOption.serviceUUIDs: [BTConstants.sampleServiceUUID]]
//			cbManager.registerForConnectionEvents(options: matchingOptions)

            cbManager.scanForPeripherals(withServices: nil)
        default:
            os_log("Cleaning up cbManager")
        }
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        os_log("connectionEventDidOccur for peripheral: %@", peripheral)
        switch event {
        case .peerConnected:
            cbPeripherals.append(peripheral)
        case .peerDisconnected:
            os_log("Peer %@ disconnected!", peripheral)
        default:
            if let idx = cbPeripherals.firstIndex(where: { $0 === peripheral }) {
                cbPeripherals.remove(at: idx)
            }
        }

    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("peripheral: %@ connected", peripheral)
        cbManager.stopScan()
        myPeripheral = peripheral
        myPeripheral?.delegate = self
        peripheral.discoverServices(nil)

        cbPeripherals.append(peripheral)

        msgLabel?.text = "\(peripheral.name ?? "") Connected! "
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("peripheral: %@ failed to connect", peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("peripheral: %@ disconnected", peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        if let n = peripheral.name, n.hasPrefix("PowerDot") {
            myPeripheral = peripheral
            cbManager.connect(peripheral)
        }



    }


}

extension VideoMetadataMain: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        if ((error) != nil) {
            NSLog("扫描特征值失败")
        }
        else {
            print("read service(\(service.uuid))'s characteristic: ")
            for characteristic in service.characteristics! {
                charas.append(characteristic)
                //设置特征值只要有更新就获取

                print("read peripheral's characteristic: \(characteristic.uuid.uuidString)  prop: \(characteristic.properties)")
                if (characteristic.uuid.uuidString == BTConstants.readCharacteristicUUID.uuidString) {
                    readC = characteristic
                    peripheral.readValue(for: characteristic)
                }else if (characteristic.uuid.uuidString == BTConstants.writeCharacteristicUUID.uuidString) {
                    writeC = characteristic
                }else if (characteristic.uuid.uuidString == BTConstants.notifyCharacteristicUUID.uuidString) {
                    notifyC = characteristic
                }
                peripheral.setNotifyValue(true, for: characteristic)

            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("收到从蓝牙 \(characteristic.uuid.uuidString) 发出的数据:\(characteristic.value)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if ((error) != nil) {
            print("查找服务失败")
            return
        }
        else {
            for service in peripheral.services! {
                //扫描到服务后对服务逐个扫描特征值
                print("discover service: \(service.uuid)")
                if service.uuid == BTConstants.serviceUUID {
                    peripheral.discoverCharacteristics(nil, for: service)
                }

            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if ((error) != nil) {
            print ("从设备获取值失败")
            return
        }
        else {
//                if(characteristic.uuid.uuidString == "特定值") {
            var infoBytes = [UInt8](characteristic.value!)
            var infoVal:Int = Int.init(infoBytes[0])


            print("read service(\(characteristic.service?.uuid)) data of characteristic \(characteristic.uuid.uuidString): \n")
            var str = ""
            for i in infoBytes{
                str += "-\(UnicodeScalar(i))"
            }
            print(str)
            msgLabel!.text = str
//                }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            print("===写入错误：\(e)");
        }else{
            NSLog("===写入成功");
        }
    }
}

/// agora rtc engine delegate events
extension VideoMetadataMain: AgoraRtcEngineDelegate {
    /// callback when warning occured for agora sdk, warning can usually be ignored, still it's nice to check out
    /// what is happening
    /// Warning code description can be found at:
    /// en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraWarningCode.html
    /// cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraWarningCode.html
    /// @param warningCode warning code of the problem
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        LogUtils.log(message: "warning: \(warningCode.description)", level: .warning)
    }
    
    /// callback when error occured for agora sdk, you are recommended to display the error descriptions on demand
    /// to let user know something wrong is happening
    /// Error code description can be found at:
    /// en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
    /// cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
    /// @param errorCode error code of the problem
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        LogUtils.log(message: "error: \(errorCode)", level: .error)
        self.showAlert(title: "Error", message: "Error \(errorCode.description) occur")
    }
    
    /// callback when the local user joins a specified channel.
    /// @param channel
    /// @param uid uid of local user
    /// @param elapsed time elapse since current sdk instance join the channel in ms
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        isJoined = true
        LogUtils.log(message: "Join \(channel) with uid \(uid) elapsed \(elapsed)ms", level: .info)
    }
    
    /// callback when a remote user is joinning the channel, note audience in live broadcast mode will NOT trigger this event
    /// @param uid uid of remote joined user
    /// @param elapsed time elapse since current sdk instance join the channel in ms
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        LogUtils.log(message: "remote user join: \(uid) \(elapsed)ms", level: .info)
        
        // Only one remote video view is available for this
        // tutorial. Here we check if there exists a surface
        // view tagged as this uid.
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        // the view to be binded
        videoCanvas.view = remoteVideo.videoView
        videoCanvas.renderMode = .hidden
        agoraKit.setupRemoteVideo(videoCanvas)
    }
    
    /// callback when a remote user is leaving the channel, note audience in live broadcast mode will NOT trigger this event
    /// @param uid uid of remote joined user
    /// @param reason reason why this user left, note this event may be triggered when the remote user
    /// become an audience in live broadcasting profile
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        LogUtils.log(message: "remote user left: \(uid) reason \(reason)", level: .info)
        
        // to unlink your view from sdk, so that your view reference will be released
        // note the video will stay at its last frame, to completely remove it
        // you will need to remove the EAGL sublayer from your binded view
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        // the view to be binded
        videoCanvas.view = nil
        videoCanvas.renderMode = .hidden
        agoraKit.setupRemoteVideo(videoCanvas)
    }
}

/// AgoraMediaMetadataDelegate and AgoraMediaMetadataDataSource
extension VideoMetadataMain : AgoraMediaMetadataDelegate, AgoraMediaMetadataDataSource {
    func metadataMaxSize() -> Int {
        // the data to send should not exceed this size
        return MAX_META_LENGTH
    }
    
    /// Callback when the SDK is ready to send metadata.
    /// You need to specify the metadata in the return value of this method.
    /// Ensure that the size of the metadata that you specify in this callback does not exceed the value set in the metadataMaxSize callback.
    /// @param timestamp The timestamp (ms) of the current metadata.
    /// @return The metadata that you want to send in the format of Data
    func readyToSendMetadata(atTimestamp timestamp: TimeInterval) -> Data? {
        guard let metadata = self.metadata else {return nil}
        
        // clear self.metadata to nil after any success send to avoid redundancy
        self.metadata = nil
        
        if(metadata.count > MAX_META_LENGTH) {
            //if data exceeding limit, return nil to not send anything
            LogUtils.log(message: "invalid metadata: length exceeds \(MAX_META_LENGTH)", level: .info)
            return nil
        }
        LogUtils.log(message: "metadata sent", level: .info)
        self.metadata = nil
        return metadata
    }
    
    /// Callback when the local user receives the metadata.
    /// @param data The received metadata.
    /// @param uid The ID of the user who sends the metadata.
    /// @param timestamp The timestamp (ms) of the received metadata.
    func receiveMetadata(_ data: Data, fromUser uid: Int, atTimestamp timestamp: TimeInterval) {
        DispatchQueue.main.async { [self] in
            if let cmd = String(data: data, encoding: .utf8){
                LogUtils.log(message: "metadata received \(cmd)", level: .info)
                if let idx = actionTitles.firstIndex(of: cmd), idx >= 0, idx < actions.count
                {
                    var endMarker = actions[idx]// NSData(bytes: [0x61, 0x32, 0x2B] as [UInt8], length: 3)

                    if idx == 0{
                        startAct()
                    }else{
                        //        charas.forEach { c in
//            myPeripheral?.writeValue(endMarker, for: c, type: .withoutResponse)
                        myPeripheral?.writeValue(endMarker, for: writeC!, type: .withoutResponse)
//        }
                    }
                }

            }


//            let alert = UIAlertController(title: "Metadata received", message: String(data: data, encoding: .utf8), preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
//            self.present(alert, animated: true, completion: nil)
        }
    }
    
}
