// FastPhotoGrid.swift — the Photos-grade grid.
//
// A UICollectionView (wrapped for SwiftUI) with the four things that make Photos
// fast: cell reuse, a PHCachingImageManager that prefetches the scroll window,
// thumbnails requested at the CELL's pixel size (not oversized), and lazy
// per-cell asset resolution (no 79k array materialized for images). Renders the
// same GridUnits (singles + stacks) with blur, and reports taps / long-press
// back to the SwiftUI PhotoGrid that hosts it.

import SwiftUI
import Photos
import UIKit

struct FastPhotoGrid: UIViewRepresentable {
    let units: [GridUnit]
    @Binding var columns: Int
    let spacing: CGFloat
    let reveal: Bool                          // viewMode == .reveal → don't blur
    let isBlurred: (String) -> Bool
    let selecting: Bool
    let isSelected: (GridUnit) -> Bool
    let onTap: (GridUnit) -> Void
    let onBlur: (GridUnit) -> Void
    let onSelectFromMenu: (GridUnit) -> Void
    // Drill pivots (the find grammar), for single photos.
    let subjectsFor: (String) -> [String]
    let dateFor: (String) -> Date?
    let onPivotSubject: (String) -> Void
    let onPivotDay: (Date) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.prefetchDataSource = context.coordinator
        cv.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        cv.addGestureRecognizer(pinch)
        context.coordinator.collectionView = cv
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let coord = context.coordinator
        let unitsChanged = coord.parent.units.map(\.id) != units.map(\.id)
        coord.parent = self
        coord.applyItemSize()
        if unitsChanged {
            cv.reloadData()
        } else {
            // Blur / selection state may have changed — refresh visible cells cheaply.
            for cell in cv.visibleCells {
                if let ip = cv.indexPath(for: cell), let photo = cell as? PhotoCell {
                    coord.decorate(photo, at: ip)
                }
            }
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                             UICollectionViewDataSourcePrefetching {
        var parent: FastPhotoGrid
        weak var collectionView: UICollectionView?
        let manager = PHCachingImageManager()
        private var assetCache: [String: PHAsset] = [:]
        private var pinchStart = 3

        init(_ parent: FastPhotoGrid) { self.parent = parent }

        func side() -> CGFloat {
            guard let cv = collectionView, cv.bounds.width > 0 else { return 100 }
            let cols = CGFloat(max(parent.columns, 1))
            return floor((cv.bounds.width - parent.spacing * (cols - 1)) / cols)
        }

        func applyItemSize() {
            guard let layout = collectionView?.collectionViewLayout as? UICollectionViewFlowLayout else { return }
            let s = side()
            if layout.itemSize.width != s { layout.itemSize = CGSize(width: s, height: s); layout.invalidateLayout() }
        }

        /// Resolve a PHAsset for an id, caching to avoid refetching.
        func asset(_ id: String) -> PHAsset? {
            if let a = assetCache[id] { return a }
            let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
            if let a { assetCache[id] = a }
            return a
        }

        // Data source
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.units.count }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as! PhotoCell
            let unit = parent.units[ip.item]
            let id = unit.assetIDs.first ?? ""
            let px = side() * cv.traitCollection.displayScale
            cell.load(assetID: id, asset: asset(id), targetPx: px, manager: manager)
            decorate(cell, at: ip)
            return cell
        }

        /// Blur + stack badge + selection — cheap, can run on visible cells to refresh state.
        func decorate(_ cell: PhotoCell, at ip: IndexPath) {
            guard ip.item < parent.units.count else { return }
            let unit = parent.units[ip.item]
            let id = unit.assetIDs.first ?? ""
            cell.setBlurred(!parent.reveal && parent.isBlurred(id))
            cell.setStack(unit.isStack ? unit.assetIDs.count : nil, side: side())
            cell.setSelection(parent.selecting, selected: parent.isSelected(unit))
        }

        func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
            cv.deselectItem(at: ip, animated: false)
            parent.onTap(parent.units[ip.item])
        }

        func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                            sizeForItemAt ip: IndexPath) -> CGSize {
            let s = side(); return CGSize(width: s, height: s)
        }

        // Prefetch — the smoothness win
        func collectionView(_ cv: UICollectionView, prefetchItemsAt ips: [IndexPath]) {
            let px = side() * cv.traitCollection.displayScale
            let assets = ips.compactMap { $0.item < parent.units.count ? asset(parent.units[$0.item].assetIDs.first ?? "") : nil }
            manager.startCachingImages(for: assets, targetSize: CGSize(width: px, height: px),
                                       contentMode: .aspectFill, options: nil)
        }
        func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt ips: [IndexPath]) {
            let px = side() * cv.traitCollection.displayScale
            let assets = ips.compactMap { $0.item < parent.units.count ? asset(parent.units[$0.item].assetIDs.first ?? "") : nil }
            manager.stopCachingImages(for: assets, targetSize: CGSize(width: px, height: px),
                                      contentMode: .aspectFill, options: nil)
        }

        // Pinch → column count (UIKit animates the relayout smoothly)
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let cv = collectionView else { return }
            switch g.state {
            case .began: pinchStart = parent.columns
            case .changed, .ended:
                let target = Int((Double(pinchStart) / max(g.scale, 0.05)).rounded())
                let clamped = min(max(target, 1), 14)
                if clamped != parent.columns {
                    parent.columns = clamped
                    let s = side()
                    if let layout = cv.collectionViewLayout as? UICollectionViewFlowLayout {
                        cv.performBatchUpdates { layout.itemSize = CGSize(width: s, height: s) }
                    }
                }
            default: break
            }
        }

        // Long-press "right click"
        func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemAt ip: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            let unit = parent.units[ip.item]
            let id = unit.assetIDs.first ?? ""
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let blur = UIAction(title: "Blur", image: UIImage(systemName: "eye.slash")) { _ in self.parent.onBlur(unit) }
                let select = UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { _ in self.parent.onSelectFromMenu(unit) }
                var children: [UIMenuElement] = [blur, select]
                if !unit.isStack {
                    var pivots: [UIMenuElement] = []
                    if let date = self.parent.dateFor(id) {
                        pivots.append(UIAction(title: "More from this day", image: UIImage(systemName: "calendar")) { _ in self.parent.onPivotDay(date) })
                    }
                    for subject in self.parent.subjectsFor(id).prefix(6) {
                        pivots.append(UIAction(title: "More: \(subject)", image: UIImage(systemName: "sparkle")) { _ in self.parent.onPivotSubject(subject) })
                    }
                    if !pivots.isEmpty {
                        children.append(UIMenu(title: "Find related", options: .displayInline, children: pivots))
                    }
                }
                return UIMenu(children: children)
            }
        }
    }
}

// MARK: - Cell

final class PhotoCell: UICollectionViewCell {
    static let reuseID = "PhotoCell"

    private let imageView = UIImageView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let badge = UIImageView(image: UIImage(systemName: "square.stack.3d.up.fill"))
    private let check = UIImageView()
    private var requestID: PHImageRequestID?
    private weak var manager: PHImageManager?
    private var loadedID = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.secondarySystemFill
        contentView.addSubview(imageView)
        blur.isHidden = true
        contentView.addSubview(blur)
        badge.tintColor = .white
        badge.isHidden = true
        badge.layer.shadowColor = UIColor.black.cgColor
        badge.layer.shadowOpacity = 0.55
        badge.layer.shadowRadius = 1.5
        badge.layer.shadowOffset = .zero
        contentView.addSubview(badge)
        check.tintColor = .white
        check.isHidden = true
        contentView.addSubview(check)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        blur.frame = contentView.bounds
        let s = min(bounds.width * 0.24, 26)
        badge.frame = CGRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        let cs: CGFloat = 22
        check.frame = CGRect(x: bounds.width - cs - 4, y: bounds.height - cs - 4, width: cs, height: cs)
    }

    func load(assetID: String, asset: PHAsset?, targetPx: CGFloat, manager: PHImageManager) {
        self.manager = manager
        loadedID = assetID
        imageView.image = nil
        guard let asset else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic     // fast placeholder → sharp; multi-fire OK for UIImageView
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let target = CGSize(width: targetPx, height: targetPx)
        let want = assetID
        requestID = manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill,
                                         options: opts) { [weak self] img, _ in
            guard let self, self.loadedID == want, let img else { return }
            self.imageView.image = img
        }
    }

    func setBlurred(_ on: Bool) { blur.isHidden = !on }

    func setStack(_ count: Int?, side: CGFloat) {
        badge.isHidden = (count == nil)
    }

    func setSelection(_ selecting: Bool, selected: Bool) {
        check.isHidden = !selecting
        check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        contentView.layer.borderWidth = (selecting && selected) ? 3 : 0
        contentView.layer.borderColor = UIColor.tintColor.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let requestID { manager?.cancelImageRequest(requestID) }
        imageView.image = nil
        loadedID = ""
    }
}
