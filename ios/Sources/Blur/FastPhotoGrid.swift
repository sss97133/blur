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

    /// Cheap content fingerprint — count + a strided id sample — so a real change
    /// is detected without allocating two full id arrays on every SwiftUI pass.
    static func unitsSignature(_ units: [GridUnit]) -> Int {
        var h = Hasher()
        h.combine(units.count)
        let stride = max(1, units.count / 32)
        var i = 0
        while i < units.count { h.combine(units[i].id); i += stride }
        if let last = units.last { h.combine(last.id) }
        return h.finalize()
    }

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
        let sig = Self.unitsSignature(units)
        let unitsChanged = coord.unitsSig != sig
        coord.parent = self
        coord.unitsSig = sig
        coord.applyItemSize()
        if unitsChanged {
            coord.resolveAndReload()   // batched off-main asset fetch, then reload
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
        /// A cheap fingerprint of the current units — so updateUIView detects a
        /// real content change without allocating two 79k string arrays per pass.
        var unitsSig = 0
        /// True while a batched PHAsset resolve is in flight (first load / new set).
        private var resolving = false
        private var resolveToken = 0

        init(_ parent: FastPhotoGrid) { self.parent = parent }

        /// Resolve EVERY unit's cover asset in ONE batched PhotoKit fetch, off the
        /// main thread, then reload — instead of a per-cell one-id query on the
        /// main thread (the thing that made this not Photos-smooth). After this,
        /// cellForItem/prefetch are pure dictionary hits.
        func resolveAndReload() {
            guard let cv = collectionView else { return }
            let ids = Array(Set(parent.units.compactMap { $0.assetIDs.first }))
            let missing = ids.filter { assetCache[$0] == nil }
            guard !missing.isEmpty else { cv.reloadData(); return }
            resolving = true
            resolveToken &+= 1
            let token = resolveToken
            Task.detached(priority: .userInitiated) {
                var found: [String: PHAsset] = [:]
                found.reserveCapacity(missing.count)
                let res = PHAsset.fetchAssets(withLocalIdentifiers: missing, options: nil)
                res.enumerateObjects { a, _, _ in found[a.localIdentifier] = a }
                let resolved = found
                await MainActor.run {
                    guard self.resolveToken == token else { return }   // superseded
                    for (k, v) in resolved { self.assetCache[k] = v }
                    self.resolving = false
                    cv.reloadData()
                }
            }
        }

        /// Fallback for a lone cache miss after the bulk resolve (rare — e.g. an
        /// incrementally-appended id). Async, off the main thread, patches the one
        /// cell when it lands. Suppressed while the bulk resolve is running.
        private func resolveOne(_ id: String, for cell: PhotoCell, px: CGFloat) {
            guard !resolving, !id.isEmpty else { return }
            Task.detached(priority: .userInitiated) {
                let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
                guard let a else { return }
                await MainActor.run {
                    self.assetCache[id] = a
                    guard let cv = self.collectionView, let ip = cv.indexPath(for: cell),
                          ip.item < self.parent.units.count,
                          self.parent.units[ip.item].assetIDs.first == id else { return }
                    cell.load(assetID: id, asset: a, targetPx: px, manager: self.manager)
                }
            }
        }

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

        /// Cache-only asset lookup — NEVER a synchronous fetch on the main thread.
        /// The cache is filled in bulk by resolveAndReload(); misses fall back to
        /// an async resolveOne (see cellForItem).
        func asset(_ id: String) -> PHAsset? { assetCache[id] }

        // Data source
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.units.count }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as! PhotoCell
            let unit = parent.units[ip.item]
            let id = unit.assetIDs.first ?? ""
            let px = side() * cv.traitCollection.displayScale
            let a = assetCache[id]
            cell.load(assetID: id, asset: a, targetPx: px, manager: manager)
            if a == nil { resolveOne(id, for: cell, px: px) }   // async fill, off-main
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
            if case .stack(let s) = unit { cell.setCaption(s.label) } else { cell.setCaption(nil) }
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
    private let caption = UILabel()
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
        caption.textColor = .white
        caption.font = .systemFont(ofSize: 13, weight: .semibold)
        caption.isHidden = true
        caption.layer.shadowColor = UIColor.black.cgColor
        caption.layer.shadowOpacity = 0.7
        caption.layer.shadowRadius = 2
        caption.layer.shadowOffset = .zero
        contentView.addSubview(caption)
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
        caption.frame = CGRect(x: 6, y: bounds.height - 24, width: bounds.width - 12, height: 18)
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

    /// A time-bucket caption ("March 2024") drawn bottom-left; nil for burst
    /// stacks and singles. Hides the center stack icon when captioned.
    func setCaption(_ text: String?) {
        caption.text = text
        caption.isHidden = (text == nil)
        if text != nil { badge.isHidden = true }   // date reads better than the icon
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
        caption.isHidden = true
        badge.isHidden = true
    }
}
