//
//  TypeSelectionViewController.swift
//  Santander
//
//  Created by Serena on 01/07/2022
//
	

import UIKit
import UniformTypeIdentifiers

/// A View Controller to select one or multiple UniformTypeIdentifiers
class TypesSelectionCollectionViewController: UICollectionViewController {
    typealias DismissHandler = (([UTType]) -> Void)
    
    typealias Item = DiffableDataSourceItem<Section, UTType>
    typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    typealias CellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item>
    
    var dismissHandler: DismissHandler
    var dataSource: DataSource!
    var selectedTypes: Set<UTType> = [] {
        didSet {
            // Enable or disable done button based on whether or not the selection is empty
            navigationItem.rightBarButtonItem?.isEnabled = !selectedTypes.isEmpty
        }
    }
    
    let allItems = TypesCollection.all()
    
    init(dismissHandler: @escaping DismissHandler) {
        self.dismissHandler = dismissHandler
        
        let layout = UICollectionViewCompositionalLayout { _, env in
            var layoutConf = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            layoutConf.headerMode = .firstItemInSection
            return NSCollectionLayoutSection.list(using: layoutConf, layoutEnvironment: env)
        }
        
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        title = "Types"
        
        let cancelAction = UIAction {
            self.selectedTypes = []
            self.dismiss(animated: true)
        }
        
        let doneAction = UIAction {
            self.dismiss(animated: true)
        }
        
        let searchController = UISearchController()
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelAction)
        let rightBarButton = UIBarButtonItem(systemItem: .done, primaryAction: doneAction)
        rightBarButton.isEnabled = false // not enabled by default bc no items are selected rn in setup
        navigationItem.rightBarButtonItem = rightBarButton
        makeDataSource()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dismissHandler(Array(selectedTypes))
    }
    
    func makeDataSource() {
        let cellRegistration = CellRegistration { [self] cell, indexPath, itemIdentifier in
            var conf: UIListContentConfiguration
            switch itemIdentifier {
            case .section(let section):
                conf = .sidebarHeader()
                conf.text = section.description
                cell.accessories = [.outlineDisclosure()]
            case .item(let type):
                conf = cell.defaultContentConfiguration()
                conf.text = type.localizedDescription
                cell.accessories = selectedTypes.contains(type) ? [.checkmark()] : []
            }
            
            cell.contentConfiguration = conf
        }
        
        self.dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }
        
        showItems(fromCollections: allItems)
    }
    
    func showItems(fromCollections coll: [TypesCollection], animatingDifferences: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let justSections = coll.map(\.section)
        snapshot.appendSections(justSections)
        dataSource.apply(snapshot, animatingDifferences: false)
        
        for collection in coll {
            let collectionSection = Item.section(collection.section)
            var section = NSDiffableDataSourceSectionSnapshot<Item>()
            section.append([collectionSection])
            
            let types = Item.fromItems(collection.types)
            section.append(types, to: collectionSection)
            section.expand([collectionSection])
            dataSource.apply(section, to: collection.section, animatingDifferences: animatingDifferences)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // "why force unwrap here!" because silently failing is a worse option, and the user will be questioning
        // why tapping didn't work
        collectionView.deselectItem(at: indexPath, animated: false)
        let item = dataSource.itemIdentifier(for: indexPath)!
        switch item {
        case .section(_): break // never supposed to get here
        case .item(let type):
            // if the item is already selected, remove this UTType from selectedTyps
            // otherwise, insert it to our selected types
            if selectedTypes.contains(type) {
                selectedTypes.remove(type)
            } else {
                selectedTypes.insert(type)
            }
            
            var snapshot = dataSource.snapshot()
            snapshot.reloadItems([.item(type)])
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
    
    enum Section: CustomStringConvertible {
        case generic
        case audio
        case programming
        case archive
        case image
        case document
        case executable
        case systemTypes
        
        var description: String {
            switch self {
            case .generic:
                return "Generic"
            case .audio:
                return "Audio"
            case .programming:
                return "Programming"
            case .archive:
                return "Archive"
            case .image:
                return "Image"
            case .document:
                return "Document"
            case .executable:
                return "Executable"
            case .systemTypes:
                return "System"
            }
        }
    }
    
    struct TypesCollection {
        let section: Section
        let types: [UTType]
        
        static func all() -> [TypesCollection] {
            return [
                TypesCollection(section: .generic, types: UTType.generictypes()),
                TypesCollection(section: .audio, types: UTType.audioTypes()),
                TypesCollection(section: .programming, types: UTType.programmingTypes()),
                TypesCollection(section: .archive, types: UTType.compressedFormatTypes()),
                TypesCollection(section: .image, types: UTType.imageTypes()),
                TypesCollection(section: .document, types: UTType.documentTypes()),
                TypesCollection(section: .systemTypes, types: UTType.systemTypes())
            ]
        }
    }
}

extension TypesSelectionCollectionViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else {
            showItems(fromCollections: allItems)
            return
        }
        
        var newCollection: [TypesCollection] = []
        for collection in allItems {
            let filtered = collection.types.filter { type in
                type.localizedDescription?.localizedCaseInsensitiveContains(searchText) ?? false ||
                type.preferredFilenameExtension?.localizedCaseInsensitiveContains(searchText) ?? false
            }
            
            if !filtered.isEmpty {
                newCollection.append(TypesCollection(section: collection.section, types: filtered))
            }
        }
        
        showItems(fromCollections: newCollection, animatingDifferences: false)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        showItems(fromCollections: allItems)
    }
}
