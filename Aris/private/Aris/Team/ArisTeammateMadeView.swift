//
//  ArisTeammateMadeView.swift
//  Aris
//
//  The notch's card after "…팀원 하나 만들어줘": the teammate it would make (its face, name, 언제 부를까요, brain and what
//  it may use), unsaved until 확인; 수정 saves it and opens Settings › 팀원 on it; 취소 drops it. Drawn like the skill flow's cards: dark glass, nothing blinks.
//

import SwiftUI

struct ArisTeammateMadeView: View {
    let mate: ArisTeammate
    var face: AnyView
    var edit: () -> Void = {}
    var confirm: () -> Void = {}
    var cancel: () -> Void = {}

    private static let card = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                face.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ArisTeamCopy.madeTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                    Text(ArisTeammateName.display(mate.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                }
                Spacer(minLength: 0)
            }
            if !mate.routing.isEmpty {
                Text(mate.routing).font(.system(size: 13)).lineSpacing(3).foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            chips
            HStack(spacing: 8) {
                button(ArisTeamCopy.cancel, bright: false, action: cancel)
                Spacer()
                button(ArisTeamCopy.edit, bright: false, action: edit)
                button(ArisTeamCopy.done, bright: true, action: confirm)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.card))
    }

    private var chips: some View {
        let scopes = ArisTeammateScope.allCases.filter(mate.scopeSet.contains)
        return HStack(spacing: 6) {
            chip(ArisBrain.named(mate.brain).shortTitle(english: ArisUIWords.english), symbol: "brain")
            ForEach(scopes, id: \.self) { scope in chip(ArisTeamCopy.scopeTitle(scope), symbol: ArisTeamSymbols.scope(scope)) }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            Text(text).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 9).frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func button(_ title: String, bright: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(bright ? .white.opacity(0.95) : .white.opacity(0.6))
                .padding(.horizontal, 14).frame(height: 30)
                .overlay(Capsule().strokeBorder(bright ? .white.opacity(0.5) : .white.opacity(0.12), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

