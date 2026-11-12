//
//  ArisShareTile.swift
//  Aris
//
//  The share tile beside the shelf strip: drop files on it, or click it and pick some, and they go out through the
//  chosen provider (AirDrop by default). A spinner covers it while the share is being prepared or the picker is up.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct ArisShareTile: View {
    let dropInteraction: DropInteractionState
    @ObservedObject private var service = QuickShareService.shared
    @Default(.quickShareProvider) private var providerID
    @State private var busy = false
    @State private var anchor: NSView?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous) }
    private var lit: Bool { dropInteraction.dropZoneTargeting }

    var body: some View {
        ZStack {
            ArisShelfSurface(lit: lit)
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.white.opacity(lit ? 0.14 : 0.08)).frame(width: 40, height: 40)
                    glyph
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.white.opacity(lit ? 1 : 0.8))
                        .scaleEffect(lit ? 1.06 : 1)
                        .animation(.easeOut(duration: 0.15), value: lit)
                }
                Text(providerID)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            if busy {
                shape.fill(Color.black.opacity(0.3))
                ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.8)
            }
        }
        .background(ArisViewAnchor(view: $anchor))
        .contentShape(shape)
        .onTapGesture(perform: pickFiles)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image],
                isTargeted: Binding(get: { dropInteraction.dropZoneTargeting }, set: { dropInteraction.dropZoneTargeting = $0 })) { providers in
            dropInteraction.dropZoneTargeting = false
            share(providers)
            return true
        }
    }

    @ViewBuilder private var glyph: some View {
        if providerID == ArisQuickShareDefault.airDrop {
            ZStack {
                ArisAirDropGlyph().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                Circle().frame(width: 3.4, height: 3.4).offset(y: 5.4)
            }
        } else if let icon = service.availableProviders.first(where: { $0.id == providerID })?.image {
            Image(nsImage: Self.sized(icon, 34)).resizable().scaledToFit().saturation(0)
        } else {
            Image(systemName: "square.and.arrow.up").resizable().scaledToFit()
        }
    }

    private static func sized(_ image: NSImage, _ side: CGFloat) -> NSImage {
        guard let copy = image.copy() as? NSImage else { return image }
        copy.size = NSSize(width: side, height: side)
        return copy
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        busy = true
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { busy = false; return }
            send(panel.urls)
        }
    }

    private func share(_ providers: [NSItemProvider]) {
        busy = true
        Task {
            var objects: [Any] = []
            for provider in providers {
                if let url = await provider.extractFileURL() { objects.append(url) }
                else if let url = await provider.extractURL() { objects.append(url) }
                else if let text = await provider.extractText() { objects.append(text) }
                else if let data = await provider.loadData(),
                        let file = ArisShelfTempFiles().data(data, named: provider.suggestedName) {
                    ArisShelfTempFiles.markScratch(file)
                    objects.append(file)
                }
            }
            guard !objects.isEmpty else { busy = false; return }
            send(objects)
        }
    }

    private func send(_ objects: [Any]) {
        guard let anchor else {
            busy = false
            ArisShelfTempFiles.removeScratch(objects.compactMap { $0 as? URL })
            return
        }
        let files = objects.compactMap { $0 as? URL }
        QuickShareService.shared.share(objects, from: anchor) {
            busy = false
            ArisShelfTempFiles.removeScratch(files)
        }
    }
}

/// Hands the hosting NSView back to SwiftUI (share pickers are anchored on it).
struct ArisViewAnchor: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.view = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
