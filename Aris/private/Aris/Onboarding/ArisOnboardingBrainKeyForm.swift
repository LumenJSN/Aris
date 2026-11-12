//
//  ArisOnboardingBrainKeyForm.swift
//  Aris
//
//  The API key's form on the guide's AI page: the provider, the key, where that provider's keys come from and that the
//  key stays in this Mac's Keychain, and 저장 (the glass button). Open at the top of the page on a Mac with no AI
//  (the owner's pick 3-A), under the API row otherwise. What it says under the field is, in turn: what is wrong with what
//  was pasted, what the helper's check of a saved key found (ArisOnboardingGuide.brainKeyTrouble), or where keys come
//  from. Saving is the guide's (ArisOnboardingGuide+Brain).
//

import SwiftUI

struct ArisBrainKeyForm: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let palette: ArisSetupPalette
    /// The field takes the keyboard as it appears, so a paste lands in it (the page that opens on this form).
    var takesKeyboard = false
    @State private var providers: [ArisAPIPresetRow] = []
    @State private var provider = ""
    @State private var key = ""
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var focused: Bool
    @Environment(\.arisOnboardingStill) private var still

    private typealias Rows = ArisOnboardingBrainRows
    /// The mockup's `.kf`: the provider menu 150 wide, both controls 32 high with radius 10.
    private static let providerWidth: CGFloat = 150
    private static let fieldHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The offscreen renders draw the two AppKit controls as their words (ImageRenderer can't draw them).
                if still {
                    Text(providers.first?.title ?? ArisOnboardingCopy.brainProvider).font(.system(size: 13)).foregroundStyle(palette.t1)
                        .frame(width: Self.providerWidth, alignment: .leading)
                } else {
                    Picker(ArisOnboardingCopy.brainProvider, selection: $provider) {
                        ForEach(providers) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: Self.providerWidth)
                }
                Group {
                    if still {
                        Text(ArisOnboardingCopy.brainKeyPlaceholder).foregroundStyle(palette.t2).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SecureField(ArisOnboardingCopy.brainKeyPlaceholder, text: $key)
                            .textFieldStyle(.plain)
                            .foregroundStyle(palette.t1)
                            .focused($focused)
                            .onSubmit { save() }
                            .accessibilityLabel(ArisOnboardingCopy.brainKeyPlaceholder)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: Self.fieldHeight)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.well))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.wellLine, lineWidth: 1))
            }
            HStack(alignment: .center, spacing: 12) {
                Text(problem ?? guide.brainKeyTrouble ?? keyHint)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(problem == nil && guide.brainKeyTrouble == nil ? palette.t2 : palette.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ArisGlassRect(title: saving ? ArisOnboardingCopy.brainKeySaving : ArisOnboardingCopy.brainKeySave) { save() }
                    .disabled(saving)
            }
        }
        .task {
            if providers.isEmpty, !still { await loadProviders() }
            if takesKeyboard, !still { focused = true }
        }
    }

    /// Where the chosen provider's keys come from; before the providers are in, only where the key is kept.
    private var keyHint: String {
        guard let source = providers.first(where: { $0.id == provider })?.keySource, !source.isEmpty else { return ArisOnboardingCopy.brainKeyKept }
        return ArisOnboardingCopy.brainKeyWhere(source)
    }

    /// The providers that take a key (a local server is set up in Settings › AI 서비스).
    private func loadProviders() async {
        providers = (await ArisAgentClient.apiBrains())?.presets.filter(\.needsKey) ?? []
        if provider.isEmpty { provider = providers.first?.id ?? "" }
        if providers.isEmpty { problem = ArisOnboardingCopy.brainHeading(.unknown) }
    }

    private func save() {
        guard !saving, !provider.isEmpty else { return }
        guard Rows.keyProblem(key) == nil else {
            problem = ArisOnboardingCopy.brainKeyEmpty
            return
        }
        saving = true
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines), id = provider
        Task {
            let refused = await guide.saveBrainKey(provider: id, key: typed)
            saving = false
            problem = refused
            if refused == nil { key = "" }
        }
    }
}
