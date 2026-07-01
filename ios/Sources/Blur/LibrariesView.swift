// LibrariesView.swift — the curated libraries (the reclaimed word).
//
// A library is a named collection composed from tags (people + subjects) —
// Family, Work, Clients. On the chronological archive you can blur a whole
// library, and stack several to blur at once. Nothing here touches the true
// (chronological) source; libraries are derived and switchable.

import SwiftUI

struct LibrariesView: View {
    @EnvironmentObject private var library: LibraryEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.libraries.isEmpty {
                    ContentUnavailableView {
                        Label("No libraries yet", systemImage: "books.vertical")
                    } description: {
                        Text("A library is a curated collection — Family, Work — built from people and subjects. Blur a whole library, or stack several before you hand over your phone.")
                    } actions: {
                        Button("New Library") { newName = ""; showingNew = true }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Libraries")
            .navigationDestination(for: CuratedLibrary.self) { lib in
                LibraryEditView(libraryID: lib.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Library", isPresented: $showingNew) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { library.createLibrary(name: n) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Family, Work, Clients…") }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(library.libraries) { lib in
                    let count = library.assets(inLibrary: lib).count
                    HStack {
                        NavigationLink(value: lib) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lib.name)
                                Text("\(count) photo\(count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("", isOn: Binding(
                            get: { library.isLibraryBlurred(lib.id) },
                            set: { library.setLibraryBlur(lib.id, $0) }
                        )).labelsHidden()
                    }
                }
                .onDelete { offsets in
                    offsets.map { library.libraries[$0].id }.forEach { library.deleteLibrary($0) }
                }
            } footer: {
                Text("Flip a switch to blur that library across the app. Stack several to hide multiple contexts at once.")
            }
        }
    }
}

/// Compose a library — its name and which people + subjects belong to it.
struct LibraryEditView: View {
    let libraryID: UUID
    @EnvironmentObject private var library: LibraryEngine
    @State private var name = ""

    private var lib: CuratedLibrary? { library.libraries.first { $0.id == libraryID } }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .onSubmit { library.renameLibrary(libraryID, to: name) }
            }
            if !library.personFacets.isEmpty {
                Section("People") {
                    ForEach(library.personFacets, id: \.person.id) { facet in
                        Toggle(isOn: member(person: facet.person.id)) {
                            HStack(spacing: 10) {
                                AssetThumbnail(assetIdentifier: facet.person.cover, side: 30, cornerRadius: 15)
                                Text(facet.person.name ?? "Person")
                                Spacer()
                                Text("\(facet.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !library.subjectFacets.isEmpty {
                Section("Subjects") {
                    ForEach(library.subjectFacets.prefix(30), id: \.label) { facet in
                        Toggle(isOn: member(subject: facet.label)) {
                            HStack {
                                Text(facet.label)
                                Spacer()
                                Text("\(facet.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(lib?.name ?? "Library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = lib?.name ?? "" }
        .onDisappear { if name != lib?.name { library.renameLibrary(libraryID, to: name) } }
    }

    private func member(person id: Int) -> Binding<Bool> {
        Binding(
            get: { lib?.personIDs.contains(id) ?? false },
            set: { library.setMember(libraryID, person: id, $0) }
        )
    }
    private func member(subject label: String) -> Binding<Bool> {
        Binding(
            get: { lib?.subjects.contains(label) ?? false },
            set: { library.setMember(libraryID, subject: label, $0) }
        )
    }
}
