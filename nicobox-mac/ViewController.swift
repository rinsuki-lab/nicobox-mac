//
//  ViewController.swift
//  nicobox-mac
//
//  Created by user on 2018/10/16.
//  Copyright © 2018 rinsuki. All rights reserved.
//

import Cocoa
import Fuzi
import Alamofire
import SwiftyJSON
import AVKit
import AVFoundation

class ViewController: NSViewController {

    @IBOutlet weak var videoUrlField: NSTextField!
    @IBOutlet weak var playerView: AVPlayerView!
    var heartbeatInfo: JSON?
    let player = AVPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.playerView.showsFullScreenToggleButton = true
        self.playerView.player = player

        DispatchQueue.global(qos: .background).async {
            while true {
                if let info = self.heartbeatInfo {
                    sleep(info["session"]["keep_method"]["heartbeat"]["lifetime"].uInt32! / 1500)
                    Alamofire.request("https://api.dmc.nico/api/sessions/" + info["session"]["id"].stringValue + "?_format=json&_method=PUT", method: .post, parameters: info.dictionaryObject!, encoding: JSONEncoding.default, headers: [
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"
                    ]).responseJSON(completionHandler: { (res) in
                        switch res.result {
                        case .success(let data):
                            let json = JSON(data)
                            if let status = json["meta"]["status"].int, status >= 400 {
                                DispatchQueue.main.async {
                                    let alert = NSAlert()
                                    alert.messageText = "ニコニコ動画: DMCセッションの延長に失敗しました"
                                    alert.informativeText = "\(json["meta"]["message"].stringValue) (\(json["meta"]["status"].intValue))"
                                    alert.alertStyle = NSAlert.Style.critical
                                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                                }
                                self.heartbeatInfo = nil
                                return
                            }
                            self.heartbeatInfo = json["data"]
                            print("heartbeat success")
                        case .failure(let error):
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "ニコニコ動画: DMCセッションの延長に失敗しました"
                                alert.informativeText = error.localizedDescription
                                alert.alertStyle = NSAlert.Style.critical
                                alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                            }
                        }
                    })
                }
                sleep(1)
            }
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @IBAction func clickedFetchButton(_ sender: NSButton) {
        let videoId = self.videoUrlField.stringValue
        let watchUrl = "https://www.nicovideo.jp/watch/" + videoId
        sender.isEnabled = false
        Alamofire.request(watchUrl, method: .get, headers: [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"
        ]).responseData { (res) in
            switch res.result {
            case .success(let data):
                print(data)
                let doc = try! Fuzi.HTMLDocument(data: data)
                guard let attr = doc.firstChild(xpath: "//*[@id=\"js-initial-watch-data\"]/@data-api-data") else {
                    let alert = NSAlert()
                    alert.messageText = "ニコニコ動画: watchページのデータ読み取りに失敗しました"
                    if let errorMessage = doc.firstChild(css: "body > div.container > div > div > div > p.messageDescription") {
                        alert.informativeText += errorMessage.stringValue+"\n"
                    }
                    alert.alertStyle = .critical
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                    return
                }
                let json = JSON(parseJSON: attr.stringValue)
                print(json)
                let dmcInfo = json["video"]["dmcInfo"]
                let api = [
                    "session": [
                        "client_info": ["player_id": dmcInfo["session_api"]["player_id"].stringValue],
                        "content_auth": [
                            "auth_type": dmcInfo["session_api"]["auth_types"]["http"].stringValue,
                            "content_key_timeout": dmcInfo["session_api"]["content_key_timeout"].intValue,
                            "service_id": "nicovideo",
                            "service_user_id": dmcInfo["session_api"]["service_user_id"].stringValue,
                        ],
                        "content_id": dmcInfo["session_api"]["content_id"].stringValue,
                        "content_src_id_sets": [[
                            "content_src_ids": [[
                                "src_id_to_mux": [
                                    "audio_src_ids": [dmcInfo["quality"]["audios"].arrayValue.filter({ $0["available"].boolValue }).sorted(by: {$0["bitrate"] > $1["bitrate"]}).first!["id"].stringValue],
                                    "video_src_ids": [dmcInfo["quality"]["videos"].arrayValue.filter({ $0["available"].boolValue }).sorted(by: {$0["bitrate"] > $1["bitrate"]}).first!["id"].stringValue],
                                ]
                            ]]
                        ]],
                        "content_type": "movie",
                        "content_uri": "",
                        "keep_method": [
                            "heartbeat": ["lifetime": dmcInfo["session_api"]["heartbeat_lifetime"].intValue]
                        ],
                        "priority": dmcInfo["session_api"]["priority"].doubleValue,
                        "protocol": [
                            "name": "http",
                            "parameters": [
                                "http_parameters": [
                                    "parameters": [
                                        "http_output_download_parameters": [
                                            "transfer_preset": "",
                                            "use_ssl": "yes",
                                            "use_well_known_port": "yes",
                                        ]
                                    ]
                                ]
                            ]
                        ],
                        "recipe_id": dmcInfo["session_api"]["recipe_id"].stringValue,
                        "session_operation_auth": [
                            "session_operation_auth_by_signature": [
                                "signature": dmcInfo["session_api"]["signature"].stringValue,
                                "token": dmcInfo["session_api"]["token"].stringValue,
                            ]
                        ],
                        "timing_constraint": "unlimited",
                    ]
                ]
                print(JSON(api))
                Alamofire.request("https://api.dmc.nico/api/sessions?_format=json", method: .post, parameters: api, encoding: JSONEncoding.default, headers: [
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"
                ]).responseJSON(completionHandler: { (res) in
                    sender.isEnabled = true
                    print("finish session request")
                    switch res.result {
                    case .success(let data):
                        print(data)
                        let json = JSON(data)
                        if let status = json["meta"]["status"].int, status >= 400 {
                            let alert = NSAlert()
                            alert.messageText = "ニコニコ動画: DMCセッションの取得に失敗しました"
                            alert.informativeText = "\(json["meta"]["message"].stringValue) (\(json["meta"]["status"].intValue))"
                            alert.alertStyle = NSAlert.Style.critical
                            alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                            return
                        }
                        if let url = json["data"]["session"]["content_uri"].url {
                            let playerItem = AVPlayerItem(url: url)
                            NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { (notify) in
                                self.player.seek(to: CMTime.zero)
                                self.player.play()
                            }
                            self.player.replaceCurrentItem(with: playerItem)
                            self.player.play()
                            self.heartbeatInfo = json["data"]
                        }
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "ニコニコ動画: DMCセッションの取得に失敗しました"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = NSAlert.Style.critical
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                    }
                })
            case .failure(let error):
                sender.isEnabled = true
                let alert = NSAlert()
                alert.messageText = "ニコニコ動画: watchページの取得に失敗しました"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = NSAlert.Style.critical
                alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
            }
        }
    }
}
