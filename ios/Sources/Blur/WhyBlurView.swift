// WhyBlurView.swift — "Why is this (not) blurred?"
//
// The trust surface. Every blur has provenance; this opens the collapsed
// isHidden() bool into the exact reason(s), and for a SKIPPED photo shows what
// the system knows (its Vision tags, whether it's even been read) — so you can
// see why a rule missed it (usually a label mismatch: tagged "Wheel", not
// "Vehicle") instead of distrusting the whole system.

import SwiftUI

struct WhyBlurView: View {
    let assetID: String
    @EnvironmentObject private var library: LibraryEngine
    @Environment(\.dismiss) private var dismiss

    private var e: BlurExplanation { library.explain(assetID) }

    var body: some View {
        NavigationStack {
            List {
                header
                if e.isBlurred { reasonsSection } else { skipSection }
                if !e.subjects.isEmpty || !e.peopleNames.isEmpty { knowsSection }
                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(e.isBlurred ? "Why blurred" : "Why not blurred")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AssetThumbnail(assetIdentifier: assetID, side: 64, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 4) {
                Label(e.isBlurred ? "Blurred" : "Visible",
                      systemImage: e.isBlurred ? "eye.slash.fill" : "eye")
                    .font(.headline)
                    .foregroundStyle(e.isBlurred ? .indigo : .primary)
                if !e.indexed {
                    Text("Not read by Vision yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    // Blurred → the reasons, each a real cause you can act on.
    private var reasonsSection: some View {
        Section("Because") {
            ForEach(e.reasons) { reason in
                HStack(spacing: 10) {
                    Image(systemName: reason.systemImage).foregroundStyle(.indigo).frame(width: 22)
                    Text(reason.label)
                }
            }
        }
    }

    // Not blurred → why a rule may have missed it. The honest, distrust-killing part.
    @ViewBuilder
    private var skipSection: some View {
        Section {
            if !e.indexed {
                Label("Vision hasn't read this photo yet — blur rules based on what's IN a photo can't apply until it's read.",
                      systemImage: "hourglass")
                    .font(.subheadline)
            } else if e.subjects.isEmpty {
                Label("Vision read it but found no subjects to match a rule.",
                      systemImage: "questionmark.circle")
                    .font(.subheadline)
            } else {
                Label("It's read, but none of its tags match a blur rule you've set. Check the tags below — a rule might be looking for a different word (e.g. “Vehicle” when this is tagged “Wheel”).",
                      systemImage: "text.magnifyingglass")
                    .font(.subheadline)
            }
        } header: { Text("Why it's skipped") }
    }

    // What the system actually knows — tap a subject to blur every photo like it.
    private var knowsSection: some View {
        Section {
            if !e.peopleNames.isEmpty {
                HStack {
                    Label("People", systemImage: "person.2").foregroundStyle(.secondary)
                    Spacer()
                    Text(e.peopleNames.joined(separator: ", ")).multilineTextAlignment(.trailing)
                }
            }
            ForEach(e.subjects, id: \.self) { subject in
                let on = library.isSubjectBlurred(subject)
                Button {
                    library.setSubjectBlur(subject, !on)
                    Haptics.success()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle").foregroundStyle(.secondary).frame(width: 22)
                        Text(subject)
                        Spacer()
                        Label(on ? "Blurring" : "Blur these",
                              systemImage: on ? "eye.slash.fill" : "eye.slash")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(on ? .indigo : .accentColor)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("What Vision saw")
        } footer: {
            Text("Tap a tag to blur every photo Vision gave that tag — the fix when a rule was looking for a different word than the one on this photo.")
        }
    }

    private var actionsSection: some View {
        Section {
            let manual = e.reasons.contains(.manual)
            Button {
                library.toggleHidden(assetID)
                Haptics.impact()
                dismiss()
            } label: {
                Label(library.isHidden(assetID) ? "Reveal this photo" : "Blur this photo by hand",
                      systemImage: library.isHidden(assetID) ? "eye" : "eye.slash")
            }
            if manual && e.reasons.count > 1 {
                Text("Note: even revealed by hand, this stays blurred by the other reasons above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
