//
//  ResizingTokenField.swift
//  ResizingTokenField
//
//  Created by Tadej Razborsek on 19/06/2019.
//  Copyright © 2019 Tadej Razborsek. All rights reserved.
//

import UIKit

class ResizingTokenField: UIView, UICollectionViewDataSource, UICollectionViewDelegate, ResizingTokenFieldFlowLayoutDelegate {
    
    // MARK: - Configuration
    
    weak var delegate: ResizingTokenFieldDelegate?
    weak var customCellDelegate: ResizingTokenFieldCustomCellDelegate? {
        didSet { registerCells() }
    }
    
    weak var textFieldDelegate: UITextFieldDelegate? {
        didSet { textField?.delegate = textFieldDelegate }
    }
    
    var itemHeight: CGFloat {
        get { return viewModel.itemHeight }
        set {
            viewModel.customItemHeight = newValue
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }
    
    private var cachedText: String? // If text is set before text field cell is loaded.
    var text: String? {
        get { return cachedText ?? textField?.text }
        set {
            if let textField = self.textField {
                textField.text = newValue
                textField.sendActions(for: .editingChanged)
            } else {
                cachedText = newValue
            }
        }
    }
    
    var preferredReturnKeyType: UIReturnKeyType = .default {
        didSet { textField?.returnKeyType = preferredReturnKeyType }
    }
    
    var placeholder: String? {
        didSet { textField?.placeholder = placeholder }
    }
    
    /// Font used for labels and text field.
    var font: UIFont {
        get { return viewModel.font }
        set { viewModel.font = newValue }
    }
    
    var contentInsets: UIEdgeInsets = Constants.Content.defaultInsets {
        didSet {
            (collectionView.collectionViewLayout as? ResizingTokenFieldFlowLayout)?.sectionInset = contentInsets
        }
    }
    
    var textFieldMinWidth: CGFloat {
        get { return viewModel.textFieldCellMinWidth }
        set { viewModel.textFieldCellMinWidth = newValue }
    }
    
    var isShowingLabel: Bool { return viewModel.isShowingLabelCell }
    var labelText: String? {
        get { return viewModel.labelCellText }
        set { viewModel.labelCellText = newValue }
    }
    
    var tokens: [ResizingTokenFieldToken] { return viewModel.tokens }
    
    /// Reference to the current text field instance, or nil if no text field is loaded.
    var textField: UITextField? { return (collectionView.cellForItem(at: viewModel.textFieldCellIndexPath) as? TextFieldCell)?.textField }
    
    /// Set this to true to make text field first responder immediately after it loads.
    /// If `textField` returns a non-nil value it should be used instead of this flag.
    var makeTextFieldFirstResponderImmediately: Bool = false
    
    private var viewModel: ResizingTokenFieldViewModel = ResizingTokenFieldViewModel()
    private let collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: ResizingTokenFieldFlowLayout())
    
    /// Tracks when the initial collection view load is performed.
    /// This flag is used to prevent crashes from trying to insert/delete items before the initial load.
    private var isCollectionViewLoaded: Bool = false
    
    /// Height constraint of the collection view. This constraint's constant is updated as collection view resizes.
    private var heightConstraint: NSLayoutConstraint?
    
    
    // MARK: - Lifecycle
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    private func initialize() {
        setUpCollectionView()
        registerCells()
    }
    
    private func setUpCollectionView() {
        (collectionView.collectionViewLayout as? ResizingTokenFieldFlowLayout)?.sectionInset = contentInsets
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0).isActive = true
        collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true
        collectionView.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0).isActive = true
        
        heightConstraint = NSLayoutConstraint(item: collectionView,
                                              attribute: .height,
                                              relatedBy: .equal,
                                              toItem: nil,
                                              attribute: .notAnAttribute,
                                              multiplier: 1,
                                              constant: 40)
        heightConstraint!.priority = UILayoutPriority(rawValue: 999) // To avoid constraint issues when used in a UIStackView
        addConstraint(heightConstraint!)
    }
    
    private func registerCells() {
        collectionView.register(LabelCell.self, forCellWithReuseIdentifier: Constants.Identifier.labelCell)
        collectionView.register(TextFieldCell.self, forCellWithReuseIdentifier: Constants.Identifier.textFieldCell)
        
        if let customClass = customCellDelegate?.resizingTokenFieldCustomTokenCellClass(self) {
            collectionView.register(customClass, forCellWithReuseIdentifier: Constants.Identifier.tokenCell)
        } else if let customNib = customCellDelegate?.resizingTokenFieldCustomTokenCellNib(self) {
            collectionView.register(customNib, forCellWithReuseIdentifier: Constants.Identifier.tokenCell)
        } else {
            collectionView.register(DefaultTokenCell.self, forCellWithReuseIdentifier: Constants.Identifier.tokenCell)
        }
    }
    
    // MARK: - Rotation
    
    func handleOrientationChange() {
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // MARK: - Toggle label
    
    func showLabel(animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        toggleLabelThenResizeTextFieldCell(visible: true, animated: animated, completion: completion)
    }
    
    func hideLabel(animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        toggleLabelThenResizeTextFieldCell(visible: false, animated: animated, completion: completion)
    }
    
    /// Shows/hides the label cell.
    /// This is done by:
    /// - setting text field cell size to minimum
    /// - toggling the label; since text field cell width is set to minimum it will stay in the same row only if there is enough room
    /// - re-invalidates collectionView layout, causing the cell's size to be recalculated to correct width
    private func toggleLabelThenResizeTextFieldCell(visible: Bool, animated: Bool, completion: ((_ finished: Bool) -> Void)?) {
        guard viewModel.isShowingLabelCell != visible else {
            completion?(true)
            return
        }
        
        viewModel.isShowingLabelCell = visible
        
        guard isCollectionViewLoaded else {
            // Collection view initial load was not performed yet, items will be correctly configured there.
            completion?(true)
            return
        }
        
        if animated {
            UIView.animate(withDuration: Constants.Duration.animationDefault, animations: {
                visible ? self.collectionView.insertItems(at: [self.viewModel.labelCellIndexPath]) : self.collectionView.deleteItems(at: [self.viewModel.labelCellIndexPath])
            }, completion: completion)
        } else {
            UIView.performWithoutAnimation {
                visible ? self.collectionView.insertItems(at: [self.viewModel.labelCellIndexPath]) : self.collectionView.deleteItems(at: [self.viewModel.labelCellIndexPath])
            }
        }
    }
    
    // MARK: - Add/remove tokens
    
    func append(tokens: [ResizingTokenFieldToken], animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        let newIndexPaths = viewModel.append(tokens: tokens)
        insertItems(atIndexPaths: newIndexPaths, animated: animated, completion: completion)
    }
    
    /// Remove provided tokens, if they are in the token field.
    func remove(tokens: [ResizingTokenFieldToken], animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        let removedIndexPaths = viewModel.remove(tokens: tokens)
        removeItems(atIndexPaths: removedIndexPaths, animated: animated, completion: completion)
    }
    
    /// Remove tokens at provided indexes, if they are in the token field.
    /// This function is the faster than `remove(tokens:)`.
    func remove(tokensAtIndexes indexes: IndexSet, animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        let removedIndexPaths = viewModel.remove(tokensAtIndexes: indexes)
        removeItems(atIndexPaths: removedIndexPaths, animated: animated, completion: completion)
    }
    
    
    private func remove(tokensAtIndexPaths indexPaths: [IndexPath], animated: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        let removedIndexPaths = viewModel.remove(tokensAtIndexPaths: indexPaths)
        removeItems(atIndexPaths: removedIndexPaths, animated: animated, completion: completion)
    }
    
    private func insertItems(atIndexPaths indexPaths: [IndexPath], animated: Bool, completion: ((_ finished: Bool) -> Void)?) {
        guard isCollectionViewLoaded else {
            // Collection view initial load was not performed yet, items will be correctly configured there.
            completion?(true)
            return
        }
        
        if animated {
            UIView.animate(withDuration: Constants.Duration.animationDefault, animations: {
                self.collectionView.insertItems(at: indexPaths)
            }, completion: completion)
        } else {
            UIView.performWithoutAnimation {
                collectionView.insertItems(at: indexPaths)
            }
        }
    }
    
    private func removeItems(atIndexPaths indexPaths: [IndexPath], animated: Bool, completion: ((_ finished: Bool) -> Void)?) {
        guard isCollectionViewLoaded else {
            // Collection view initial load was not performed yet, items will be correctly configured there.
            completion?(true)
            return
        }
        
        if animated {
            UIView.animate(withDuration: Constants.Duration.animationDefault, animations: {
                self.collectionView.deleteItems(at: indexPaths)
            }, completion: completion)
        } else {
            UIView.performWithoutAnimation {
                collectionView.deleteItems(at: indexPaths)
            }
        }
    }
    
    // MARK: - Selecting tokens
    
    private func selectLastToken() {
        if let indexPath = viewModel.lastTokenCellIndexPath, let cell = collectionView.cellForItem(at: indexPath) as? ResizingTokenFieldTokenCell {
            _ = cell.becomeFirstResponder()
        }
    }
    
    // MARK: - UICollectionViewDataSource
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        isCollectionViewLoaded = true
        return viewModel.numberOfItems
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: viewModel.identifierForCell(atIndexPath: indexPath),
                                                      for: indexPath)
        switch cell {
        case let tokenCell as ResizingTokenFieldTokenCell:
            populate(tokenCell: tokenCell, atIndexPath: indexPath)
        case let labelCell as LabelCell:
            populate(labelCell: labelCell, atIndexPath: indexPath)
        case let textFieldCell as TextFieldCell:
            populate(textFieldCell: textFieldCell, atIndexPath: indexPath)
        default:
            // Should never reach.
            break
        }
        
        return cell
    }
    
    private func populate(tokenCell: ResizingTokenFieldTokenCell, atIndexPath indexPath: IndexPath) {
        guard let token = viewModel.token(atIndexPath: indexPath) else {
            tokenCell.onRemove = nil
            return
        }
        
        if let defaultTokenCell = tokenCell as? DefaultTokenCell {
            defaultTokenCell.titleLabel.font = viewModel.font
        }
        
        tokenCell.populate(withToken: token)
        tokenCell.onRemove = { [weak self] (text) in
            guard let self = self else { return }
            self.remove(tokens: [token], animated: true)
            self.text = text
            _ = self.textField?.becomeFirstResponder()
        }
    }
    
    private func populate(labelCell: LabelCell, atIndexPath indexPath: IndexPath) {
        labelCell.label.font = viewModel.font
        labelCell.label.text = viewModel.labelCellText
    }
    
    private func populate(textFieldCell: TextFieldCell, atIndexPath indexPath: IndexPath) {
        if let text = cachedText {
            cachedText = nil
            textFieldCell.textField.text = text
        }
        
        textFieldCell.textField.placeholder = placeholder
        textFieldCell.textField.font = viewModel.font
        textFieldCell.textField.returnKeyType = preferredReturnKeyType
        textFieldCell.textField.delegate = textFieldDelegate
        textFieldCell.textField.addTarget(self, action: #selector(textFieldEditingChanged(_:)), for: .editingChanged)
        textFieldCell.onDeleteBackwardWhenEmpty = { [weak self] in self?.selectLastToken() }
        
        if makeTextFieldFirstResponderImmediately {
            makeTextFieldFirstResponderImmediately = false
            textFieldCell.textField.becomeFirstResponder()
        }
    }
    
    @objc private func textFieldEditingChanged(_ textField: UITextField) {
        delegate?.resizingTokenField(self, didEditText: textField.text)
    }
    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? ResizingTokenFieldTokenCell {
            _ = cell.becomeFirstResponder()
        }
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let identifier = viewModel.identifierForCell(atIndexPath: indexPath)
        switch identifier {
        case Constants.Identifier.labelCell:
            return viewModel.labelCellSize
        case Constants.Identifier.textFieldCell:
            return viewModel.textFieldCellMinSize   // Will be stretched by layout if needed
        case Constants.Identifier.tokenCell:
            if let token = viewModel.token(atIndexPath: indexPath) {
                if let delegate = customCellDelegate {
                    return CGSize(width: delegate.resizingTokenField(self, tokenCellWidthForToken: token),
                                  height: itemHeight)
                }
                
                return viewModel.defaultTokenCellSize(forToken: token)
            }
        default:
            break
        }
        
        // Should never reach
        return CGSize.zero
    }
    
    // MARK: - ResizingTokenFieldFlowLayoutDelegate
    
    func collectionView(_ collectionView: UICollectionView, layout: ResizingTokenFieldFlowLayout, heightDidChange newHeight: CGFloat) {
        heightConstraint?.constant = newHeight
    }
    
    func lastCellIndexPath(in collectionView: UICollectionView, layout: ResizingTokenFieldFlowLayout) -> IndexPath {
        return viewModel.textFieldCellIndexPath
    }

}
