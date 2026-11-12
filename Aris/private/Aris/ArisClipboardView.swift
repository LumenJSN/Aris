//
//  ArisClipboardView.swift
//  Aris
//
//  The 클립보드 list, Maccy's way: type to search, ↑↓ to choose, ↩ to copy, ⌥↩ to paste into the app in front,
//  ⌥⇧↩ to paste without formatting, ⌘1–9 for the first nine, ⌥P to pin, ⌥⌫ to delete. Clicks do the same (⌥-click
//  pastes); the right-click menu has everything. Pinned items stay on top. Keys work while the pointer is on the list
//  or after ⌃⌥V (it lives in the left side panel).
//

import AppKit
import SwiftUI

struct ArisClipboardView: View {
    @ObservedObject private var model = ArisClipboardModel.shared
    /// Called once an item is copied or pasted: the panel showing the list puts itself away.
    var onDone: () -> Void = {}
    @State private var query = ""
    @State private var selected = 0
    @State private var copied: UUID?
    @State private var keys: Any?
    @FocusState private var searching: Bool

    private var shown: [ArisClipboard.Item] { ArisClipboard.search(query, in: model.items) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if shown.isEmpty {
                ArisSideStyle.empty(model.items.isEmpty ? ArisUIWords.text("복사한 것들이 여기 쌓여요", "What you copy collects here") : ArisUIWords.text("찾는 게 없어요", "Nothing found"))
            }
            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index).id(item.id)
                        }
                    }
                }
                .onChange(of: selected) { _, index in
                    if shown.indices.contains(index) { scroller.scrollTo(shown[index].id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: query) { _, _ in selected = 0 }
        .onAppear { startKeys() }
        .onDisappear { stopKeys(); KeyboardFocus.arm(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // The search field: the glyph in the placeholder's colour, the words 15 at white .95, the
            // placeholder rgba(236, 239, 247, .62) at medium weight, tracked 0.2.
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ArisSideStyle.placeholder)
            TextField(text: $query) {
                Text(ArisUIWords.text("검색", "Search")).font(.system(size: ArisSideLook.searchSize, weight: .medium))
                    .tracking(ArisSideLook.searchPlaceholderTracking).foregroundStyle(ArisSideStyle.placeholder)
            }
                .textFieldStyle(.plain)
                .font(.system(size: ArisSideLook.searchSize))
                .foregroundStyle(.white.opacity(ArisSideLook.searchAlpha))
                .focused($searching)
            Spacer()
            Button { model.paused.toggle() } label: {
                Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 10))
                    .foregroundStyle(model.paused ? Color.orange : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(model.paused ? ArisUIWords.text("기록 다시 시작", "Start recording again") : ArisUIWords.text("기록 잠시 멈추기", "Pause recording"))
            Menu {
                Button(ArisUIWords.text("다음 복사 하나만 건너뛰기", "Skip the next copy only")) { model.skipNext = true }
                Button(ArisUIWords.text("고정 안 한 것 지우기", "Clear what isn't pinned")) { model.clear() }
                Button(ArisUIWords.text("전부 지우기 (고정 포함)", "Clear everything (pinned too)"), role: .destructive) { model.clear(includingPinned: true) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 24)
    }

    private func row(_ item: ArisClipboard.Item, index: Int) -> some View {
        HStack(spacing: 9) {
            icon(item)
            if item.isImage, let image = thumbnail(item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 20).clipShape(RoundedRectangle(cornerRadius: 3, style: .circular))
                Text(ArisUIWords.text("이미지", "Image")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            } else {
                Text(item.title.replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(.system(size: 13)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(ArisOrb.glow) }
            Text(copied == item.id ? ArisUIWords.text("복사됨", "Copied") : index < 9 ? "⌘\(index + 1)" : "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(copied == item.id ? ArisOrb.glow : .white.opacity(0.3))
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .circular).fill(index == selected ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
        .help(item.title.isEmpty ? ArisUIWords.text("이미지", "Image") : String(item.title.prefix(800)))
        .onTapGesture {
            selected = index
            let flags = NSEvent.modifierFlags
            if flags.contains(.option) { paste(item, plain: flags.contains(.shift)) } else { copy(item) }
        }
        .contextMenu {
            Button(ArisUIWords.text("복사", "Copy")) { copy(item) }
            Button(ArisUIWords.text("붙여넣기", "Paste")) { paste(item, plain: false) }
            Button(ArisUIWords.text("서식 없이 붙여넣기", "Paste without formatting")) { paste(item, plain: true) }
            Button(item.pinned ? ArisUIWords.text("고정 해제", "Unpin") : ArisUIWords.text("고정", "Pin")) { model.togglePin(item) }
            Button(ArisUIWords.text("삭제", "Delete"), role: .destructive) { model.delete(item) }
        }
    }

    private func icon(_ item: ArisClipboard.Item) -> some View {
        Group {
            if let bundle = item.appBundle, let icon = ArisFileIcons.icon(forApp: bundle) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 16, height: 16)
    }

    private func thumbnail(_ item: ArisClipboard.Item) -> NSImage? {
        item.contents.first { ArisClipboard.imageTypes.contains($0.type) }.flatMap { NSImage(data: $0.data) }
    }

    /// Like Maccy's popup: choosing an item puts the notch away and gives the keyboard back.
    private func copy(_ item: ArisClipboard.Item) {
        model.copy(item)
        copied = item.id
        done()
    }

    private func paste(_ item: ArisClipboard.Item, plain: Bool) {
        Task {
            await model.paste(item, plain: plain)
            done()
        }
    }

    private func done() {
        query = ""
        KeyboardFocus.arm(false)
        onDone()
    }

    // MARK: - Keys (only while this tab has the keyboard)

    private enum Key {
        static let returnKey: UInt16 = 36, escape: UInt16 = 53, up: UInt16 = 126, down: UInt16 = 125
        static let delete: UInt16 = 51, p: UInt16 = 35
        /// ⌘1 … ⌘9.
        static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    private func startKeys() {
        stopKeys()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func stopKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    /// True when the key was ours.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let items = shown
        let current = items.indices.contains(selected) ? items[selected] : nil
        switch event.keyCode {
        case Key.down: selected = min(selected + 1, max(items.count - 1, 0)); return true
        case Key.up: selected = max(selected - 1, 0); return true
        case Key.returnKey:
            guard let current else { return false }
            if flags.contains(.option) { paste(current, plain: flags.contains(.shift)) } else { copy(current) }
            return true
        case Key.p where flags == .option:
            if let current { model.togglePin(current) }
            return true
        case Key.delete where flags == .option:
            if let current { model.delete(current) }
            return true
        case Key.escape:
            if query.isEmpty { done() } else { query = "" }
            return true
        default:
            if flags.contains(.command), let digit = Key.digits.firstIndex(of: event.keyCode), items.indices.contains(digit) {
                selected = digit
                if flags.contains(.option) { paste(items[digit], plain: flags.contains(.shift)) } else { copy(items[digit]) }
                return true
            }
            // Typing anywhere on the tab searches.
            if flags.isEmpty || flags == .shift, !searching, event.characters?.unicodeScalars.first.map(CharacterSet.alphanumerics.contains) == true {
                searching = true
                query += event.characters ?? ""
                return true
            }
            return false
        }
    }
}
