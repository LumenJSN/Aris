//
//  ArisAIDecisionRow.swift
//  Aris
//
//  Under 짧은 명령 빨리 알아듣기's dropdown, for a decision model other than Jev (jv-decision): its key in the
//  shape of TypeSafe's line (add it, see it masked and take it out, or type it), then its model id and, where it has
//  one, its address. Drawn from ArisAIDecisionLine.
//

import SwiftUI

struct ArisAIDecisionRows: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let line: ArisAIDecisionLine
    @ObservedObject var model: ArisAIServicesModel

    private var draft: String { "decision:" + line.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            key
            if case .editing(let error?) = line.key {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red)
            }
            field(line.model, .decisionModel(line.id))
            if let address = line.address { field(address, .decisionAddress(line.id)) }
        }
    }

    private var key: some View {
        HStack(spacing: 8) {
            switch line.key {
            case .off:
                title("\(line.name) 키")
                Text(w(line.keyOptional ? "키 없이도 돼요" : "이 모델에 물어보려면 키가 필요해요")).lineLimit(1).font(.system(size: 12))
                    .foregroundStyle(palette.desc).frame(maxWidth: .infinity, alignment: .leading)
                ArisSettingsButton(title: "API 키 추가", small: true) { model.perform(.openDecisionKey(line.id)) }
            case .on(let masked):
                title("\(line.name) 키")
                (Text(w("켜짐") + " · ").font(.system(size: 12)) + Text(masked).font(.system(size: 12, design: .monospaced)))
                    .foregroundStyle(palette.desc).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ArisSettingsButton(title: "지우기", small: true) { model.perform(.clearDecisionKey(line.id)) }
            case .editing:
                title("\(line.name) 키").padding(.trailing, 4)
                ArisAITextField(placeholder: "\(line.name) API 키", text: model.draft(draft), secure: true, autofocus: true) { save() }
                ArisSettingsButton(title: "저장", kind: .primary, small: true) { save() }
                ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelDecisionKey) }
            }
        }
        .frame(minHeight: 32)
    }

    private func field(_ field: ArisAIDecisionLine.Field, _ kind: ArisAIField) -> some View {
        HStack(spacing: 8) {
            title(field.label).frame(maxWidth: .infinity, alignment: .leading)
            ArisAICommitField(field: kind, stored: field.value, placeholder: field.hint, label: field.label, width: 280, model: model)
        }
        .frame(minHeight: 32)
    }

    private func title(_ text: String) -> some View {
        Text(w(text)).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.title).fixedSize()
    }

    private func save() { model.perform(.saveDecisionKey(id: line.id, key: model.drafts[draft] ?? "")) }
}
