////
////  SandboxEscaped.swift
////  Santander
////
////  Created by Summit on 2023/1/28.
////
//
//import Foundation
//import UIKit
//
//class SandBoxEscaped: NSObject {
//    override init() {
//        super.init()
//        DispatchQueue.main.async {
//            let window = UIApplication.shared.windows.first
//            let alert = UIAlertController(title: "Santander ios16.0-16.1.2", message: "Powered By Summit", preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "确定", style: .default, handler: nil))
//            window?.rootViewController?.present(alert, animated: true, completion: nil)
//        }
//        grant_full_disk_access() { error in
//            print(error?.localizedDescription as Any)
//        }
//
//    }
//}
