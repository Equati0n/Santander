//
//  SerializedDocumentViewController.swift
//  Santander
//
//  Created by Serena on 16/08/2022.
//

import UIKit

typealias SerializedDictionaryType = [String: SerializedItemType]

/// A ViewController which displays the contents of a PropertyList or JSON file
class SerializedDocumentViewController: UITableViewController, SerializedItemViewControllerDelegate {
    
    var serializedDict: SerializedDictionaryType
    
    var filteredDict: SerializedDictionaryType = [:]
    
    var keys: [String] {
        let keysArr = Array(isSearching ? filteredDict.keys : serializedDict.keys)
        return keysArr
    }
    
    var fileURL: URL?
    var canEdit: Bool
    var isSearching: Bool = false
    let type: SerializedDocumentViewerType
    let parentController: SerializedControllerParent?
    
    init(
        dictionary: SerializedDictionaryType,
        type: SerializedDocumentViewerType,
        title: String,
        fileURL: URL? = nil,
        parentController: SerializedControllerParent?,
        canEdit: Bool
    ) {
        self.serializedDict = dictionary
        self.type = type
        self.fileURL = fileURL
        self.canEdit = canEdit
        self.parentController = parentController
        
        super.init(style: .userPreferred)
        self.title = title
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction(withClosure: dismissVC))
        let searchController = UISearchController()
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = !UserPreferences.alwaysShowSearchBar
    }
    
    convenience init?(
        type: SerializedDocumentViewerType,
        fileURL: URL,
        data: Data,
        canEdit: Bool
    ) {
        
        switch type {
        case .json:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            let newDict = json.asSerializedDictionary()
            self.init(dictionary: newDict, type: .json, title: fileURL.lastPathComponent, fileURL: fileURL, parentController: nil, canEdit: canEdit)
        case .plist(_):
            let fmt: UnsafeMutablePointer<PropertyListSerialization.PropertyListFormat>? = .allocate(capacity: 4)
            defer {
                fmt?.deallocate()
            }
            
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: fmt) as? [String: Any] else {
                return nil
            }
            
            let newDict = plist.asSerializedDictionary()
            
            self.init(dictionary: newDict, type: .plist(format: fmt?.pointee), title: fileURL.lastPathComponent, fileURL: fileURL, parentController: nil, canEdit: canEdit)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return keys.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value2, reuseIdentifier: nil)
        var conf = cell.defaultContentConfiguration()
        let text = keys[indexPath.row]
        
        conf.text = text
        let elem = dictElement(forKey: text)
        
        switch elem {
        case .dictionary(_), .array(_):
            cell.accessoryType = .disclosureIndicator
        default:
            cell.accessoryType = .detailButton
        }
        
        conf.secondaryText = valueDescription(forElement: elem)
        cell.contentConfiguration = conf
        return cell
    }
    
    func dismissVC() {
        self.dismiss(animated: true)
    }
    
    /// Present the SerializedDocumentViewController for a specified indexPath
    func presentViewController(forIndexPath indexPath: IndexPath) {
        let text = keys[indexPath.row]
        let elem = dictElement(forKey: text)!
        
        if case .array(let arr) = elem {
            let vc = SerializedArrayViewController(array: arr, type: type, parentController: .dictionary(self), title: text, fileURL: fileURL, canEdit: canEdit)
            self.navigationController?.pushViewController(vc, animated: true)
        } else if case .dictionary(let dict) = elem {
            let newDict = dict.asSerializedDictionary()
            
            let vc = SerializedDocumentViewController(dictionary: newDict, type: type, title: text, fileURL: fileURL, parentController: .dictionary(self), canEdit: true)
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = SerializedItemViewController(item: elem, itemKey: text)
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        presentViewController(forIndexPath: indexPath)
    }
    
    func didChangeName(ofItem item: String, to newName: String) -> Bool {
        guard let value = serializedDict[item] else {
            return false
        }
        
        var newDict: SerializedDictionaryType = serializedDict
        newDict[item] = nil
        newDict[newName] = value
        
        let didSucceed = writeToFile(newDict: newDict)
        tableView.reloadData()
        return didSucceed
    }
    
    func didChangeValue(ofItem item: String, to newValue: SerializedItemType) -> Bool {
        var newDict: SerializedDictionaryType = serializedDict
        newDict[item] = newValue
        
        let didSucceed = writeToFile(newDict: newDict)
        if isSearching {
            tableView.reloadData()
        } else {
            updateFilteredDict(reloadData: true, searchText: nil)
        }
        return didSucceed
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presentViewController(forIndexPath: indexPath)
    }
    
    @discardableResult
    func writeToFile(newDict: SerializedDictionaryType) -> Bool {
        // TODO: - Support for editing nested dicts!
        guard let fileURL = fileURL, canEdit else {
            return false
        }
        
        // write to parent dictionary / array
        if let parentController = parentController {
            let didSucced: Bool
            switch parentController {
            case .dictionary(let parent):
                let key = parent.serializedDict.first { (_, value) in
                    value == SerializedItemType.dictionary(self.serializedDict.asAnyDictionary())
                }?.key
                
                guard let key = key else {
                    return false
                }
                
                var parentDict = parent.serializedDict
                parentDict[key] = .dictionary(newDict.asAnyDictionary())
                didSucced = parent.writeToFile(newDict: parentDict)
            case .array(let parent):
                var parentArr = parent.array
                let indx = parentArr.firstIndex { item in
                    guard let item = item as? Dictionary<String, Any> else {
                        return false
                    }
                    
                    return serializedDict == item.asSerializedDictionary()
                }
                
                guard let indx = indx else {
                    return false
                }
                
                parentArr[indx] = newDict.asAnyDictionary()
                didSucced = parent.writeToFile(newArray: parentArr)
            }
            
            if didSucced {
                self.serializedDict = newDict
                return true
            }
            
            return false
        }
        
        switch type {
        case .json:
            do {
                let newData = try JSONSerialization.data(withJSONObject: newDict.asAnyDictionary(), options: .prettyPrinted)
                try FSOperation.perform(.writeData(url: fileURL, data: newData), rootHelperConf: RootConf.shared)
                self.serializedDict = newDict
                return true
            } catch {
                self.errorAlert(error, title: "Unable to write to file \(fileURL.lastPathComponent)", presentingFromIfAvailable: presentedViewController)
                return false
            }
        case .plist(let format):
            guard let format = format else {
                self.errorAlert("Unable to get plist format", title: "Can't write to Property List file", presentingFromIfAvailable: presentedViewController)
                return false
            }
            
            do {
                let newData = try PropertyListSerialization.data(fromPropertyList: newDict.asAnyDictionary(), format: format, options: 0)
                try FSOperation.perform(.writeData(url: fileURL, data: newData), rootHelperConf: RootConf.shared)
                self.serializedDict = newDict
                return true
            } catch {
                self.errorAlert(error, title: "Unable to write to file \(fileURL.lastPathComponent)", presentingFromIfAvailable: presentedViewController)
                return false
            }
        }
    }
    
    /// Returns the element to be used for the given key
    /// in the dictionary
    func dictElement(forKey key: String) -> SerializedItemType? {
        return isSearching ? filteredDict[key] : serializedDict[key]
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard canEdit else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: nil) { _, _, completion in
            var newDict = self.serializedDict
            newDict[self.keys[indexPath.row]] = nil
            if self.writeToFile(newDict: newDict) {
                self.updateFilteredDict(reloadData: false, searchText: nil)
                self.tableView.deleteRows(at: [indexPath], with: .fade)
                completion(true)
            } else {
                completion(false)
            }
        }
        deleteAction.image = .remove
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

/// The types openable in SerializedDocumentViewController
enum SerializedDocumentViewerType {
    case json
    case plist(format: PropertyListSerialization.PropertyListFormat?)
}

extension SerializedDocumentViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        tableView.reloadData()
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        isSearching = !searchText.isEmpty

        updateFilteredDict(reloadData: true, searchText: searchText)
    }
    
    func valueDescription(forElement element: SerializedItemType?) -> String? {
        switch element {
        case .array(_), .dictionary(_):
            return element?.typeDescription
        default:
            return element?.description
        }
    }
    
    func updateFilteredDict(reloadData: Bool, searchText text: String?) {
        if isSearching {
            let searchText = text ?? navigationItem.searchController?.searchBar.text ?? ""
            filteredDict = serializedDict.filter { (key, value) in
                return key.localizedCaseInsensitiveContains(searchText) ||
                valueDescription(forElement: value)?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        if reloadData {
            tableView.reloadData()
        }
    }
}
