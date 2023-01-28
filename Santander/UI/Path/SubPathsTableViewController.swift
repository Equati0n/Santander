//
//  SubPathsTableViewController.swift
//  Santander
//
//  Created by Serena on 21/06/2022
//


import UIKit
import QuickLook
import UniformTypeIdentifiers
import ApplicationsWrapper
import CompressionWrapper

/// A table view controller showing the subpaths under a Directory, or a group
class SubPathsTableViewController: UITableViewController, PathTransitioning {
    
    /// The contents of the path, unfiltered
    var unfilteredContents: [URL]
    
    /// The contents of the path, filtered by the search or hiding dotfiles
    var filteredSearchContents: [URL] = []
    
    /// The items selected by the user while editing
    var selectedItems: [URL] = []
    
    /// A Boolean representing if the user is currently searching
    var isSearching: Bool = false
    
    /// The contents of the path to show in UI
    var contents: [URL] {
        get {
            return filteredSearchContents.isEmpty && !self.isSearching ? unfilteredContents : filteredSearchContents
        }
    }
    
    /// The method of sorting
    var sortMethod: PathsSortMethods = .userPrefered ?? .alphabetically {
        willSet {
            UserDefaults.standard.set(newValue.rawValue, forKey: "SubPathsSortMode")
            sortContents()
        }
    }
    
    /// is this ViewController being presented as the `Bookmarks` paths?
    let isBookmarksSheet: Bool
    
    /// The current path from which items are presented
    var currentPath: URL? = nil
    
    let showInfoButton: Bool = UserPreferences.showInfoButton
    
    /// Whether or not to display the search suggestions
    var displayingSearchSuggestions: Bool = false
    
    /// the Directory Monitor, used to observe changes
    /// if the path is a directory
    var directoryMonitor: DirectoryMonitor?
    
    /// The Audio Player View Controller to display
    var audioPlayerController: AudioPlayerViewController?
    
    /// The label which displays that the user doesn't have permission to view a directory,
    /// or that the directory / group is empty
    /// (if those conditions apply)
    var permissionDeniedLabel: UILabel!
    
    /// Whether or not to display files beginning with a dot in their names
    var displayHiddenFiles: Bool = UserPreferences.displayHiddenFiles {
        didSet {
            reloadTableData()
            
            UserPreferences.displayHiddenFiles = self.displayHiddenFiles
        }
    }
    
    /// Whether or not the current path contains subpaths that are app UUIDs
    var containsAppUUIDs: Bool?
    
    var searchItem: DispatchWorkItem?
    
    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, SubPathsRowItem>
    typealias DataSource = UITableViewDiffableDataSource<Int, SubPathsRowItem>
    
    lazy var dataSource = DataSource(tableView: tableView) { tableView, indexPath, itemIdentifier in
        switch itemIdentifier {
        case .path(let url):
            return self.pathCellRow(forURL: url, displayFullPathAsSubtitle: self.isSearching || self.isBookmarksSheet)
        case .searchSuggestion(let suggestion):
            return self.searchSuggestionCellRow(suggestion: suggestion)
        }
    }
    
    /// Returns the SubPathsTableViewController for bookmarks paths
    class func bookmarks() -> SubPathsTableViewController {
        return SubPathsTableViewController(
            contents: Array(UserPreferences.bookmarks),
            title: "Bookmarks",
            isBookmarksSheet: true)
    }
    
    /// Initialize with a given path URL
    init(style: UITableView.Style = .userPreferred, path: URL, isBookmarksSheet: Bool = false) {
        self.unfilteredContents = self.sortMethod.sorting(URLs: path.contents, sortOrder: .userPreferred)
        self.currentPath = path
        self.isBookmarksSheet = isBookmarksSheet
        
        super.init(style: style)
        self.title = path.lastPathComponent
    }
    
    /// Initialize with the given specified URLs
    init(style: UITableView.Style = .userPreferred, contents: [URL], title: String, isBookmarksSheet: Bool = false) {
        self.unfilteredContents = self.sortMethod.sorting(URLs: contents, sortOrder: .userPreferred)
        self.isBookmarksSheet = isBookmarksSheet
        
        super.init(style: style)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setRightBarButton()
        if !self.displayHiddenFiles {
            reloadTableData()
        }
        
        self.navigationController?.navigationBar.prefersLargeTitles = UserPreferences.useLargeNavigationTitles
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        self.tableView.keyboardDismissMode = .onDrag
        self.navigationItem.hidesSearchBarWhenScrolling = !UserPreferences.alwaysShowSearchBar
        if let currentPath = currentPath {
            searchController.searchBar.scopeButtonTitles = [currentPath.lastPathComponent, "Subdirectories"]
            self.containsAppUUIDs = currentPath.containsAppUUIDSubpaths
            setupRefreshControl(forPath: currentPath)
        }
        self.navigationItem.searchController = searchController
#if compiler(>=5.7)
        if #available(iOS 16.0, *), UIDevice.isiPad {
            self.navigationItem.style = .browser
            self.navigationItem.renameDelegate = self
        }
#endif
        
        tableView.dragInteractionEnabled = true
        tableView.dropDelegate = self
        tableView.dragDelegate = self
        tableView.dataSource = self.dataSource
        showPaths()
        
        setupPermissionDeniedLabelIfNeeded()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // The code for setting up the directory monitor should stay in viewDidAppear
        // if used in viewDidLoad, it won't be monitoring if the user goes into a different directory
        // then comes back
        if let currentPath = self.currentPath {
            if directoryMonitor == nil {
                directoryMonitor = DirectoryMonitor(url: currentPath)
                directoryMonitor?.delegate = self
            }
            
            directoryMonitor?.startMonitoring()
            // set the last opened path here
            UserPreferences.lastOpenedPath = currentPath.path
        }
    }
    
    // scroll up or down keyboard shortcuts
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(title: "Scroll Up", action: #selector(scrollUpOrDown(sender:)), input: UIKeyCommand.inputUpArrow, modifierFlags: .command),
            UIKeyCommand(title: "Scroll Down", action: #selector(scrollUpOrDown(sender:)), input: UIKeyCommand.inputDownArrow, modifierFlags: .command)
        ]
    }
    
    @objc
    func scrollUpOrDown(sender: UIKeyCommand) {
        switch sender.input {
        case UIKeyCommand.inputDownArrow:
            let snapshot = dataSource.snapshot()
            let indexPathToSrcollTo = IndexPath(row: snapshot.numberOfItems - 1, section: snapshot.numberOfSections - 1)
            tableView.scrollToRow(at: indexPathToSrcollTo, at: .bottom, animated: true)
        case UIKeyCommand.inputUpArrow:
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        default: break
        }
    }
    
    func setupRefreshControl(forPath path: URL) {
        let refreshControl = UIRefreshControl()
        let refreshAction = UIAction { [self] in
            unfilteredContents = sortMethod.sorting(URLs: path.contents, sortOrder: .userPreferred)
            reloadTableData()
            refreshControl.endRefreshing()
        }
        
        refreshControl.addAction(refreshAction, for: .primaryActionTriggered)
        
        tableView.refreshControl = refreshControl
    }
    
    /// Setup the snapshot to show the paths given
    func showPaths(animatingDifferences: Bool = false) {
        self.displayingSearchSuggestions = false
        var snapshot = Snapshot()
        
        snapshot.appendSections([0])
        snapshot.appendItems(SubPathsRowItem.fromPaths(contents))
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }
    
    /// Show the search suggestions
    func switchToSearchSuggestions() {
        displayingSearchSuggestions = true
        var snapshot = Snapshot()
        
        snapshot.appendSections([0, 1, 2])
        
        for indexPath in SearchSuggestion.searchSuggestionSectionAndRows {
            let item = SubPathsRowItem.searchSuggestion(.displaySearchSuggestions(for: indexPath))
            snapshot.appendItems([item], toSection: indexPath.section)
        }
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func path(forIndexPath indexPath: IndexPath) -> URL {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .path(let path):
            return path
        default:
            fatalError("NEVER SUPPOSED TO BE HERE!")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.directoryMonitor?.stopMonitoring()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.isEditing {
            selectedItems.append(path(forIndexPath: indexPath)) // PLACE 1
            setupOrUpdateToolbar()
            setLeftBarSelectionButtonItem()
            return
        }
        
        if displayingSearchSuggestions {
            let searchTextField = self.navigationItem.searchController?.searchBar.searchTextField
            let tokensCount = searchTextField?.tokens.count
            
            if (indexPath.section, indexPath.row) == (0, 0) {
                // The user wants to filter by type,
                // prompt the viewController for doing so
                let vc = TypesSelectionCollectionViewController { types in
                    // Make sure the user selected a type before we insert the search token
                    if !types.isEmpty {
                        var searchSuggestion = SearchSuggestion.displaySearchSuggestions(for: indexPath, typesToCheck: types)
                        // Set the name to the types
                        searchSuggestion.name = types.compactMap(\.localizedDescription).joined(separator: ", ")
                        searchTextField?.insertToken(searchSuggestion.searchToken, at: tokensCount ?? 0)
                    }
                }
                
                let navVC = UINavigationController(rootViewController: vc)
                
                self.present(navVC, animated: true)
                
            } else {
                searchTextField?.insertToken(SearchSuggestion.displaySearchSuggestions(for: indexPath).searchToken, at: tokensCount ?? 0)
            }
            
        } else {
            let selectedItem = path(forIndexPath: indexPath) // PLACE 2
            goToPath(path: selectedItem)
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard self.isEditing else {
            return
        }
        
        let selected = path(forIndexPath: indexPath) // PLACE 3
        selectedItems.removeAll { path in
            path == selected
        }
        
        setupOrUpdateToolbar()
        setLeftBarSelectionButtonItem()
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        guard !displayingSearchSuggestions else {
            return nil
        }
        
        let selectedItem = self.path(forIndexPath: indexPath) // PLACE 4
        let itemAlreadyBookmarked = UserPreferences.bookmarks.contains(selectedItem)
        let favouriteAction = UIContextualAction(style: .normal, title: nil) { _, _, handler in
            self.removeOrAddItemToBookmarks(selectedItem, alreadyBookmarked: itemAlreadyBookmarked)
            handler(true)
        }
        
        favouriteAction.backgroundColor = .systemBlue
        favouriteAction.image = itemAlreadyBookmarked ? UIImage(systemName: "star.fill") : UIImage(systemName: "star")
        
        let deleteAction = UIContextualAction(style: .destructive, title: nil) { _, _, completion in
            self.deleteURL(selectedItem) { didSucceed in
                completion(didSucceed)
            }
        }
        
        deleteAction.image = UIImage(systemName: "trash")
        
        let config = UISwipeActionsConfiguration(actions: [deleteAction, favouriteAction])
        return config
    }
    
    func removeOrAddItemToBookmarks(_ item: URL, alreadyBookmarked: Bool) {
        if alreadyBookmarked {
            UserPreferences.bookmarks.remove(item)
            
            // if we're in the bookmarks sheet, reload the table
            if self.isBookmarksSheet {
                self.unfilteredContents = Array(UserPreferences.bookmarks)
                
                var snapshot = self.dataSource.snapshot()
                snapshot.deleteItems([.path(item)])
                self.dataSource.apply(snapshot)
            }
        } else {
            // otherwise, append it
            UserPreferences.bookmarks.insert(item)
        }
    }
    
    func makeSortMenu() -> UIMenu {
        let actions: [UIMenuElement] = PathsSortMethods.allCases.map { type in
            let typeIsSelected = self.sortMethod == type
            return UIAction(
                title: type.description,
                image: typeIsSelected ? UIImage(systemName: SortOrder.userPreferred.imageSymbolName) : nil,
                state: typeIsSelected ? .on : .off) { _ in
                    // if the user selected the already selected type,
                    // change the sort order
                    if typeIsSelected {
                        UserDefaults.standard.set(SortOrder.userPreferred.toggling().rawValue, forKey: "SortOrder")
                        self.sortContents()
                    } else {
                        // otherwise change the sort method itself
                        self.sortMethod = type
                    }
                    
                    // Reload the right bar button menu after setting the type
                    self.setRightBarButton()
                }
        }
        
        let menu = UIMenu(title: "Sort by..", image: UIImage(systemName: "arrow.up.arrow.down"), children: actions)
        if #available(iOS 15.0, *) {
            menu.subtitle = self.sortMethod.description
        }
        
        return menu
    }
    
    func makeNewItemMenu(forURL url: URL) -> UIMenu {
        let newFile = UIAction(title: "File", image: UIImage(systemName: "doc")) { _ in
            self.presentAlertAndCreate(type: .file, forURL: url)
        }
        
        let newFolder = UIAction(title: "Folder", image: UIImage(systemName: "folder")) { _ in
            self.presentAlertAndCreate(type: .directory, forURL: url)
        }
        
        return UIMenu(title: "New..", image: UIImage(systemName: "plus"), children: [newFile, newFolder])
    }
    
    
    // A UIMenu containing different, common, locations to go to, as well as an option
    // to go to a specified URL
    func makeGoToMenu() -> UIMenu {
        var items: [UIMenuElement] = GoToItem.all.map { item in
            return UIAction(title: item.displayName, image: item.image) { _ in
                self.goToPath(path: item.url)
            }
        }
        
        let otherLocationAction = UIAction(title: "Other..") { _ in
            let alert = UIAlertController(title: "Other Location", message: "Type the URL of the other path you want to go to", preferredStyle: .alert)
            
            alert.addTextField { textfield in
                textfield.placeholder = "url.."
            }
            
            let goAction = UIAlertAction(title: "Go", style: .default) { _ in
                guard let text = alert.textFields?.first?.text, FileManager.default.fileExists(atPath: text) else {
                    self.errorAlert("URL inputted must be valid and must exist", title: "Error")
                    return
                }
                
                let url = URL(fileURLWithPath: text)
                self.goToPath(path: url)
            }
            
            alert.addAction(.cancel())
            alert.addAction(goAction)
            alert.preferredAction = goAction
            self.present(alert, animated: true)
        }
        
        items.append(otherLocationAction)
        
        return UIMenu(title: "Go to..", image: UIImage(systemName: "arrow.right"), children: items)
    }
    
    func decompressPath(path: URL) {
        let alertController = createAlertWithSpinner(title: "Decompressing..")
        present(alertController, animated: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var caughtError: Error? = nil
            do {
                // DON'T CHANGE THIS DESTINATION VAR.
                // why? because without it, you'd have a double directory
                // ie, unzipping Library.zip would create ./CurrentDirectory/Library/Library,
                // rather than the intended ./CurrentDirectory/Library/,
                let destination = path.deletingLastPathComponent()
                try Compression.shared.extract(path: path, to: destination)
            } catch {
                caughtError = error
            }
            
            DispatchQueue.main.async {
                alertController.dismiss(animated: true)
                if let caughtError = caughtError {
                    self.errorAlert(caughtError, title: "Unable to decompress file \(path.lastPathComponent)")
                }
            }
        }
    }
    
    func compressPaths(paths: [URL], destination: URL, format: Compression.FormatType) {
        let alertController = createAlertWithSpinner(title: "Compressing..", heightAnchorConstant: 120)
        present(alertController, animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            var caughtError: Error? = nil
            do {
                try Compression.shared.compress(paths: paths, outputPath: destination, format: format) { pathBeingProcessed in
                    DispatchQueue.main.async { alertController.message = "Compressing \(pathBeingProcessed.lastPathComponent)" }
                }
            } catch {
                caughtError = error
            }
            
            DispatchQueue.main.async {
                alertController.dismiss(animated: true)
                if let caughtError = caughtError {
                    self.errorAlert(caughtError, title: "Unable to compress file(s).")
                }
            }
        }
    }
    
    func makeCompressionMenu(paths: [URL], destination: @escaping (Compression.FormatType) -> URL) -> UIMenu {
        let actions = Compression.FormatType.allCases.map { format in
            UIAction(title: format.description) { _ in
                self.compressPaths(paths: paths, destination: destination(format), format: format)
            }
        }
        
        return UIMenu(title: "Compress", image: UIImage(systemName: "archivebox"), children: actions)
    }
    
    func goToFile(path: URL) {
        if path.contentType?.isOfType(.archive) ?? false {
            decompressPath(path: path)
        } else if let preferred = FileEditor.preferred(forURL: path) {
            preferred.display(senderVC: self)
            
            // if it's the audio viewcontroller & the file URL is different than the current property audio controller
            // set the current audioVC property to it
            if let audioVC = preferred.viewController as? AudioPlayerViewController {
                // if music is already playing, then stop it
                self.audioPlayerController?.player.stop()
                // then set the current audio controller to the file tapped
                self.audioPlayerController = audioVC
                self.setupAudioToolbarIfPossible()
            }
            
        } else {
            openQuickLookPreview(forURL: path)
        }
    }
    
    func openQuickLookPreview(forURL url: URL) {
        let controller = QLPreviewController()
        let shared = FilePreviewDataSource(fileURL: url)
        controller.dataSource = shared
        self.present(controller, animated: true)
    }
    
    /// Opens a path in the UI
    func goToPath(path: URL) {
        // Make sure we're opening a directory,
        // or the parent directory of the file selected (if searching)
        
        // if we're going to a directory, go to the directory path
        if path.isDirectory {
            let parentDirectory = path.deletingLastPathComponent()
            
            // if the parent directory is the current directory or we're in the bookmarks sheet
            // simply push through the navigation controller
            // rather than traversing through each parent path
            if isBookmarksSheet || parentDirectory == self.currentPath {
                let vc = SubPathsTableViewController(path: path, isBookmarksSheet: self.isBookmarksSheet)
                self.navigationController?.pushViewController(vc, animated: true)
            } else {
                traverseThroughPath(path)
            }
        } else {
            self.goToFile(path: path)
        }
    }
    
    func traverseThroughPath(_ path: URL) {
        let vcs = path.fullPathComponents().map {
            SubPathsTableViewController(path: $0, isBookmarksSheet: self.isBookmarksSheet)
        }
        
        self.navigationController?.setViewControllers(vcs, animated: true)
    }
    
    func sortContents() {
        self.unfilteredContents = sortMethod.sorting(URLs: unfilteredContents, sortOrder: .userPreferred)
        reloadTableData(animatingDifferences: true)
    }
    
    /// Opens the information bottom sheet for a specified path
    func openInfoBottomSheet(path: URL) {
        if let app = path.applicationItem {
            // if we can get the app info too,
            // present an action sheet to choose between either
            let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            let pathInfoAction = UIAlertAction(title: "Path Info", style: .default) { _ in
                let navController = UINavigationController(
                    rootViewController: PathInformationTableViewController(style: .insetGrouped, path: path)
                )
                
                if #available(iOS 15.0, *) {
                    navController.sheetPresentationController?.detents = [.medium(), .large()]
                }
                
                self.present(navController, animated: true)
            }
            
            let appInfoAction = UIAlertAction(title: "App Info", style: .default) { _ in
                let navController = UINavigationController(
                    rootViewController: AppInfoViewController(style: .insetGrouped, app: app, subPathsSender: self)
                )
                
                self.present(navController, animated: true)
            }
            
            actionSheet.addAction(appInfoAction)
            actionSheet.addAction(pathInfoAction)
            actionSheet.addAction(.init(title: "Cancel", style: .cancel))
            
            actionSheet.popoverPresentationController?.sourceView = view
            let bounds = view.bounds
            actionSheet.popoverPresentationController?.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
            self.present(actionSheet, animated: true)
        } else {
            let navController = UINavigationController(
                rootViewController: PathInformationTableViewController(style: .insetGrouped, path: path)
            )
            
            if #available(iOS 15.0, *) {
                navController.sheetPresentationController?.detents = [.medium(), .large()]
            }
            
            self.present(navController, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        self.openInfoBottomSheet(path: path(forIndexPath: indexPath)) // PLACE 5
    }
    
    /// Returns the cell row to be used for a search suggestion
    func searchSuggestionCellRow(suggestion: SearchSuggestion) -> UITableViewCell {
        let cell = UITableViewCell()
        var conf = cell.defaultContentConfiguration()
        conf.text = suggestion.name
        conf.image = suggestion.image
        cell.contentConfiguration = conf
        return cell
    }
    
    /// Returns the cell row to be used to display a path
    func pathCellRow(
        forURL fsItem: URL,
        displayFullPathAsSubtitle useSubtitle: Bool = false
    ) -> UITableViewCell {
        let pathName = fsItem.lastPathComponent
        
        let cell = UITableViewCell(style: useSubtitle ? .subtitle : .default, reuseIdentifier: nil)
        var cellConf = cell.defaultContentConfiguration()
        defer {
            cell.contentConfiguration = cellConf
        }
        
        // for performance, we check first for if the current path contains app UUIDs (if the pathExt isn't .app)
        // otherwise, if currentPath is nil, check for if the parent dir of the path contains app UUIDs
        // performance is worse if we *always* do the first,
        // but `containsAppUUIDs` isn't nil as long as `currentPath` isn't nil.
        if (fsItem.pathExtension == "app" || (containsAppUUIDs ?? fsItem.deletingLastPathComponent().containsAppUUIDSubpaths)),
           let app = fsItem.applicationItem {
            cellConf.text = app.localizedName()
            cellConf.image = ApplicationsManager.shared.icon(forApplication: app)
            cellConf.secondaryText = fsItem.lastPathComponent
            cell.accessoryType = .disclosureIndicator
            cellConf.textProperties.color = tableView.tintColor ?? .systemBlue
            return cell
        }
        
        cellConf.text = pathName
        
        // if the item name starts is a dotfile / dotdirectory
        // ie, .conf or .zshrc,
        // display the label as gray
        if pathName.first == "." {
            cellConf.textProperties.color = .gray
            cellConf.secondaryTextProperties.color = .gray
        }
        
        if useSubtitle {
            cellConf.secondaryText = fsItem.path // Display full path as the subtitle text if we should
        }
        
        cellConf.image = fsItem.displayImage
        
        if showInfoButton {
            cell.accessoryType = .detailDisclosureButton
        } else if fsItem.isDirectory {
            cell.accessoryType = .disclosureIndicator
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        
        if displayingSearchSuggestions {
            return nil // No context menu for search suggestions
        }
        
        let item = path(forIndexPath: indexPath) // PLACE 6
        return UIContextMenuConfiguration(identifier: nil) {
            // The following is the preview provider for the item
            // Being the cell row, but manually made for 2 reasons:
            // 1) Display the full path as a subtitle
            // 2) Rounded corners, which we wouldn't have if we returned previewProvider as `nil`
            let vc = UIViewController()
            vc.view = self.pathCellRow(forURL: item, displayFullPathAsSubtitle: true)
            vc.view.backgroundColor = .systemBackground
            let sizeFrame = vc.view.frame
            vc.preferredContentSize = CGSize(width: sizeFrame.width, height: sizeFrame.height)
            return vc
        } actionProvider: { _ in
            
            let movePath = UIAction(title: "Move to..", image: UIImage(systemName: "arrow.right")) { _ in
                self.presentOperationVC(forItems: [item], type: .move)
            }
            
            let copyPath = UIAction(title: "Copy to..", image: UIImage(systemName: "doc.on.doc")) { _ in
                self.presentOperationVC(forItems: [item], type: .copy)
            }
            
            let createSymlink = UIAction(title: "Create symbolic link to..", image: UIImage(systemName: "link")) { _ in
                self.presentOperationVC(forItems: [item], type: .symlink)
            }
            
            let pasteboardOptions = UIMenu(options: .displayInline, children: self.makePasteboardMenuElements(for: item))
            let operationItemsMenu = UIMenu(options: .displayInline, children: [movePath, copyPath, createSymlink])
            let informationAction = UIAction(title: "Info", image: UIImage(systemName: "info.circle")) { _ in
                self.openInfoBottomSheet(path: item)
            }
            
            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.presentActivityVC(forItems: [item])
            }
            
            let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "rectangle.and.pencil.and.ellipsis")) { _ in
                let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
                
                let renameAction = UIAlertAction(title: "Rename", style: .default) { _ in
                    guard let name = alert.textFields?.first?.text else {
                        return
                    }
                    
                    do {
                        let newPath = item.deletingLastPathComponent().appendingPathComponent(name)
                        try FSOperation.perform(.copyItem(items: [item], resultPath: newPath), rootHelperConf: RootConf.shared)
                    } catch {
                        self.errorAlert(error, title: "Unable to rename \(item.lastPathComponent)")
                    }
                }
                
                alert.addTextField { textField in
                    textField.text = item.lastPathComponent
                }
                
                alert.addAction(.cancel())
                alert.addAction(renameAction)
                self.present(alert, animated: true)
            }
            
            var children: [UIMenuElement] = [informationAction, renameAction, shareAction]
            
            let compressOrDecompressAction: UIMenuElement
            if !(item.contentType?.isOfType(.archive) ?? false) {
                compressOrDecompressAction = self.makeCompressionMenu(paths: [item]) { format in
                    return item.deletingPathExtension().appendingPathExtension(format.fileExtension)
                }
            } else {
                compressOrDecompressAction = UIAction(title: "Decompress", image: UIImage(systemName: "archivebox")) { _ in
                    self.decompressPath(path: item)
                }
            }
            
            children.append(compressOrDecompressAction)
            
            // "Open App" option for apps
            if let app = item.applicationItem {
                let openAction = UIAction(title: "Open App") { _ in
                    do {
                        try ApplicationsManager.shared.openApp(app)
                    } catch {
                        self.errorAlert(error, title: "Unable to open app")
                    }
                }
                children.append(openAction)
            }
            
            if !item.isDirectory {
                let allEditors = FileEditor.allEditors(forURL: item)
                var actions = allEditors.map { editor in
                    UIAction(title: editor.type.description) { _ in
                        editor.display(senderVC: self)
                    }
                }
                
                // always have a QuickLook action
                let qlAction = UIAction(title: "QuickLook") { _ in
                    self.openQuickLookPreview(forURL: item)
                }
                
                actions.append(qlAction)
                
                //TODO: - For insanely large files, this results in a crash, find a way around this.
                // maybe use a UIAlertController as an actionSheet?
                children.append(UIMenu(title: "Open in..", children: actions))
            }
            
            if UIDevice.isiPad {
                let addActions = UserPreferences.pathGroups.enumerated().map { (index, group) in
                    return UIAction(title: group.name) { _ in
                        UserPreferences.pathGroups[index].paths.append(item)
                    }
                }
                
                let addToPathGroupsMenu = UIMenu(title: "Add to group..", image: UIImage(systemName: "sidebar.leading"), children: addActions)
                children.append(addToPathGroupsMenu)
            }
            
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.deleteURL(item) { _ in }
            }
            
            let isItemBookmarked = UserPreferences.bookmarks.contains(item)
            let bookmarkAction = UIAction(
                title: isItemBookmarked ? "Remove bookmark" : "Bookmark",
                image: UIImage(systemName: isItemBookmarked ? "bookmark.slash" : "bookmark")
            ) { _ in
                self.removeOrAddItemToBookmarks(item, alreadyBookmarked: isItemBookmarked)
            }
            
            children.append(contentsOf: [operationItemsMenu, pasteboardOptions])
            children.append(UIMenu(options: .displayInline, children: [bookmarkAction, deleteAction]))
            return UIMenu(children: children)
        }
    }
    
    func makePasteboardMenuElements(for url: URL) -> [UIMenuElement] {
        let copyName = UIAction(title: "Copy name") { _ in
            UIPasteboard.general.string = url.lastPathComponent
        }
        
        let copyPath = UIAction(title: "Copy path") { _ in
            UIPasteboard.general.url = url
            UIPasteboard.general.string = url.path
        }
        
        return [copyName, copyPath]
    }
    
    func presentOperationVC(forItems items: [URL], type: PathSelectionOperation) {
        let vc = PathOperationViewController(paths: items, operationType: type)
        present(UINavigationController(rootViewController: vc), animated: true) { [self] in
            if let currentPath = currentPath, currentPath != .root {
                vc.goToPath(path: currentPath)
            }
        }
    }
    
    /// Returns the UIMenu to be used as the (primary) right bar button
    func makeRightBarButton() -> UIMenu {
        let selectAction = UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { _ in
            self.tableView.allowsMultipleSelectionDuringEditing = true
            self.setEditing(true, animated: true)
        }
        
        let selectionMenu = UIMenu(options: .displayInline, children: [selectAction])
        var firstMenuItems = [selectionMenu, makeSortMenu(), makeGoToMenu()]
        
        if let currentPath = currentPath {
            firstMenuItems.append(makeNewItemMenu(forURL: currentPath))
        }
        
        let firstMenu = UIMenu(options: .displayInline, children: firstMenuItems)
        var menuActions: [UIMenuElement] = [firstMenu]
        
        // if we're in the "Bookmarks" sheet, don't display the Bookmarks button
        if !isBookmarksSheet {
            let presentBookmarks = UIAction(title: "Bookmarks", image: UIImage(systemName: "bookmark")) { _ in
                let newVC = UINavigationController(rootViewController: SubPathsTableViewController.bookmarks())
                self.present(newVC, animated: true)
            }
            
            menuActions.append(presentBookmarks)
        }
        
        if let currentPath = currentPath {
            let showInfoAction = UIAction(title: "Info", image: .init(systemName: "info.circle")) { _ in
                self.openInfoBottomSheet(path: currentPath)
            }
            
            menuActions.append(showInfoAction)
            let pasteAction = UIAction(title: "Paste") { _ in
                guard let probableURL = UIPasteboard.general.probableURL else {
                    self.errorAlert(nil, title: "No path to paste.")
                    return
                }
                
                do {
                    try FSOperation.perform(.copyItem(items: [probableURL], resultPath: currentPath), rootHelperConf: RootConf.shared)
                } catch {
                    self.errorAlert(error, title: "Failed to copy item to current directory.")
                }
            }
            
            menuActions.insert(UIMenu(options: .displayInline, children: [pasteAction]), at: 1)
        }
        
        let settingsAction = UIAction(title: "Settings", image: UIImage(systemName: "gear")) { _ in
            self.present(UINavigationController(rootViewController: SettingsTableViewController(style: .insetGrouped)), animated: true)
        }
        menuActions.append(settingsAction)
        
        let showOrHideHiddenFilesAction = UIAction(
            title: "Display hidden files",
            state: displayHiddenFiles ? .on : .off
        ) { _ in
            self.displayHiddenFiles.toggle()
            self.setRightBarButton()
        }
        
        menuActions.append(showOrHideHiddenFilesAction)
        return UIMenu(children: menuActions)
    }
    
    func setRightBarButton() {
        if self.isEditing {
            let editAction = UIAction {
                self.setEditing(false, animated: true)
            }
            
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .done,
                primaryAction: editAction
            )
            
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: .init(systemName: "ellipsis.circle"),
                menu: makeRightBarButton()
            )
        }
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        setRightBarButton()
        setLeftBarSelectionButtonItem()
        if editing {
            setupOrUpdateToolbar()
        } else {
            hideToolbarItems()
            selectedItems = []
        }
    }
    
    /// Shows or hides dotfiles,
    /// this method is the primary way of reloading the view
    func reloadTableData(animatingDifferences: Bool = false) {
        if !displayHiddenFiles {
            let filtered = unfilteredContents.filter { !$0.lastPathComponent.starts(with: ".") }
            setFilteredContents(filtered, animatingDifferences: animatingDifferences)
        } else {
            setFilteredContents([], animatingDifferences: animatingDifferences)
        }
    }
    
    func setFilteredContents(_ newContents: [URL], animatingDifferences: Bool = false) {
        self.filteredSearchContents = newContents
        if !displayingSearchSuggestions {
            self.showPaths(animatingDifferences: animatingDifferences)
        }
    }
    
    func setupPermissionDeniedLabelIfNeeded() {
        guard let currentPath = currentPath, contents.isEmpty, !currentPath.isReadable else {
            return
        }
        
        permissionDeniedLabel = UILabel()
        permissionDeniedLabel.text = "Permission Denied."
        
        permissionDeniedLabel.font = .systemFont(ofSize: 20, weight: .medium)
        permissionDeniedLabel.textColor = .systemGray
        permissionDeniedLabel.textAlignment = .center
        
        view.addSubview(permissionDeniedLabel)
        permissionDeniedLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            permissionDeniedLabel.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
            permissionDeniedLabel.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor)
        ])
    }
}

extension SubPathsTableViewController: DirectoryMonitorDelegate {
    func directoryMonitorDidObserveChange(directoryMonitor: DirectoryMonitor) {
        DispatchQueue.main.async {
            let items = self.sortMethod.sorting(URLs: directoryMonitor.url.contents, sortOrder: .userPreferred)
            self.unfilteredContents = items
            self.reloadTableData(animatingDifferences: true)
            
            if self.isSearching, let searchBar = self.navigationItem.searchController?.searchBar {
                // If we're searching,
                // update the search bar
                self.updateResults(searchBar: searchBar)
            }
        }
    }
}
#if compiler(>=5.7)
extension SubPathsTableViewController: UINavigationItemRenameDelegate {
    func navigationItem(_: UINavigationItem, didEndRenamingWith title: String) {
        guard let currentPath = currentPath else {
            return
        }
        
        let newURL = currentPath.deletingLastPathComponent().appendingPathComponent(title)
        
        // new name is the exact same, don't continue renaming
        guard currentPath != newURL else {
            return
        }
        
        do {
            try FSOperation.perform(.moveItem(items: [currentPath], resultPath: newURL), rootHelperConf: RootConf.shared)
            self.currentPath = newURL
        } catch {
            self.errorAlert(error, title: "Uname to rename \(newURL.lastPathComponent)")
            // renaming automatically changes title
            // so we need to change back the title to the original
            // in case of a failure
            self.title = currentPath.lastPathComponent
        }
    }
    
    func navigationItemShouldBeginRenaming(_: UINavigationItem) -> Bool {
        return currentPath != nil
    }
}
#endif

/// Represents an item which could be displayed in SubPathsTableViewController,
/// being either a search suggestion or a path
enum SubPathsRowItem: Hashable {
    static func == (lhs: SubPathsRowItem, rhs: SubPathsRowItem) -> Bool {
        switch (lhs, rhs) {
        case (.path(let firstURL), .path(let secondURL)):
            return firstURL == secondURL
        case (.searchSuggestion(let firstSuggestion), .searchSuggestion(let secondSuggestion)):
            return firstSuggestion == secondSuggestion
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .searchSuggestion(let searchSuggestion):
            hasher.combine(searchSuggestion)
        case .path(let url):
            hasher.combine(url)
        }
    }
    
    case searchSuggestion(SearchSuggestion)
    case path(URL)
    
    /// Return an array of items from an array of URLs
    static func fromPaths(_ paths: [URL]) -> [SubPathsRowItem] {
        return paths.map { url in
            return .path(url)
        }
    }
}
