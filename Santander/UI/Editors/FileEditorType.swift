//
//  FileEditorType.swift
//  Santander
//
//  Created by Serena on 16/08/2022.
//

import UIKit
import AVKit

struct FileEditor {
    let type: FileEditorType
    let viewController: UIViewController
    
    static func preferred(forURL url: URL) -> FileEditor? {
        if url.pathExtension == "car", let carVC = FileEditorType.assetCatalog.viewController(forPath: url, data: nil) {
            return FileEditor(type: .assetCatalog, viewController: carVC)
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        let type = url.contentType
        if type == .unixExecutable {
            return FileEditor(type: .executable, viewController: BinaryExecutionViewController(executableURL: url))
        }
        
        if type?.isOfType(.audio) ?? false, let audio = FileEditorType.audio.viewController(forPath: url, data: data) {
            return FileEditor(type: .audio, viewController: audio)
        }
        
        if type?.isOfType(.font) ?? false, let fontVC = FileEditorType.font.viewController(forPath: url, data: data) {
            return FileEditor(type: .font, viewController: fontVC)
        }
        
        if let imageVC = FileEditorType.image.viewController(forPath: url, data: data) {
            return FileEditor(type: .image, viewController: imageVC)
        }
        
        if (type?.isOfType(.video) ?? false || type?.isOfType(.movie) ?? false),
            let videoPlayer = FileEditorType.video.viewController(forPath: url, data: data) {
            return FileEditor(type: .video, viewController: videoPlayer)
        }
        
            
        if let plistVc = FileEditorType.propertyList.viewController(forPath: url, data: data) {
            return FileEditor(type: .propertyList, viewController: plistVc)
        }
        
        if url.pathExtension == "json", let jsonVC = FileEditorType.json.viewController(forPath: url, data: data) {
            return FileEditor(type: .json, viewController: jsonVC)
        }
        
        if let textEditorVc = FileEditorType.text.viewController(forPath: url, data: data) {
            return FileEditor(type: .text, viewController: textEditorVc)
        }
        
        return nil
    }
    
    static func allEditors(forURL url: URL) -> [FileEditor] {
        let data = try? Data(contentsOf: url)
        
        return FileEditorType.allCases.compactMap { type in
            guard let vc = type.viewController(forPath: url, data: data) else {
                return nil
            }
            return FileEditor(type: type, viewController: vc)
        }
    }
    
    func display(senderVC: UIViewController) {
        let vcToPresent: UIViewController
        if type.useNavigationController {
            vcToPresent = UINavigationController(rootViewController: viewController)
        } else {
            vcToPresent = viewController
        }
        
        if type.presentAsFullScreen {
            vcToPresent.modalPresentationStyle = .fullScreen
        }
        
        senderVC.present(vcToPresent, animated: true)
    }
}

enum FileEditorType: CustomStringConvertible, CaseIterable {
    case audio, image, video
    case propertyList, json, text, font
    case assetCatalog
    case executable
    
    /// Returns the view controller to be used for the file editor type
    /// the Data parameter is used so that, when looping over all editor types,
    /// it tries to get the data for only one time
    func viewController(forPath path: URL, data: Data?) -> UIViewController? {
        if self == .assetCatalog {
            guard path.pathExtension == "car",
                  let vc = try? AssetCatalogViewController(catalogFileURL: path) else {
                return nil
            }
            
            if UIDevice.isiPad {
                return __makeSplitViewController(with: AssetCatalogSidebarListView(catalogController: vc), for: .primary)
            }
            
            return vc
        }
        
        guard let data = data else { return nil }
        
        switch self {
        case .audio:
            return try? AudioPlayerViewController(fileURL: path, data: data)
        case .propertyList:
            let fmt: UnsafeMutablePointer<PropertyListSerialization.PropertyListFormat> = .allocate(capacity: 4)
            let plist = try? PropertyListSerialization.propertyList(from: data, format: fmt)
            
            if let dict = plist as? [String: Any] {
                return SerializedDocumentViewController(dictionary: dict.asSerializedDictionary(), type: .plist(format: fmt.pointee), title: path.lastPathComponent, fileURL: path, parentController: nil, canEdit: true)
            } else if let arr = plist as? Array<Any> {
                return SerializedArrayViewController(array: arr, type: .plist(format: fmt.pointee), parentController: nil, title: path.lastPathComponent, fileURL: path, canEdit: true)
            }
            
            return nil
        case .json:
            
            let json = try? JSONSerialization.jsonObject(with: data)
            
            if let dict = json as? [String: Any] {
                return SerializedDocumentViewController(dictionary: dict.asSerializedDictionary(), type: .json, title: path.lastPathComponent, fileURL: path, parentController: nil, canEdit: true)
            } else if let arr = json as? Array<Any> {
                return SerializedArrayViewController(array: arr, type: .json, parentController: nil, title: path.lastPathComponent, fileURL: path, canEdit: true)
            }
            
            return nil
        case .text:
            guard let stringContents = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            let textVC = TextFileEditorViewController(fileURL: path, contents: stringContents)
            if UIDevice.isiPad {
                return __makeSplitViewController(with: textVC, for: .secondary)
            }
            
            return textVC
        case .image:
            guard let image = UIImage(data: data) else {
                return nil
            }
            
            return ImageViewerController(fileURL: path, image: image)
        case .video:
            let type = path.contentType
            guard (type?.isOfType(.movie) ?? false || type?.isOfType(.video) ?? false) else {
                return nil
            }
            
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: path)
            return controller
        case .font:
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(path as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else {
                return nil
            }
            
            return FontViewerController(selectedFont: descriptors.first!.uiFont, descriptors: descriptors)
        case .executable:
            return BinaryExecutionViewController(executableURL: path)
        case .assetCatalog: return nil // already covered!
        }
    }
    
    private func __makeSplitViewController(with vc: UIViewController, for column: UISplitViewController.Column) -> UISplitViewController {
        let splitVC = UISplitViewController(style: .doubleColumn)
        splitVC.setViewController(vc, for: column)
        return splitVC
    }
    
    var description: String {
        switch self {
        case .audio:
            return "Audio Player"
        case .video:
            return "Video Player"
        case .image:
            return "Image Viewer"
        case .propertyList:
            return "Property List Viewer"
        case .json:
            return "JSON Viewer"
        case .font:
            return "Font Viewer"
        case .text:
            return "Text Editor"
        case .assetCatalog:
            return "Asset Catalog Viewer"
        case .executable:
            return "Executable Runner"
        }
    }
    
    var presentAsFullScreen: Bool {
        switch self {
        case .text, .image, .video, .executable:
            return true
        case .audio, .font:
            return false
        case .propertyList, .json, .assetCatalog:
            return UIDevice.isiPad
        }
    }
    
    var useNavigationController: Bool {
        switch self {
        case .video:
            return false
        case .text, .assetCatalog:
            return !UIDevice.isiPad
        default:
            return true
        }
    }
}
