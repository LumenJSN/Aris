// The open Claude tab around a card, as ArisNotchRoot and ClaudeTabView lay it out: the notch grows with its content
// (GrowDownFrame) from 190 up to `maxHeight`, 8 more under it; under the 38-point band, the session column (150 wide) and, 12 to its
// right, the session chips (20 tall) and the panel (14 in) the card sits in, 540 wide in all. Hosted in an NSHostingView
// in a window that is never ordered on screen; the card's ClaudeCardFit tells the probe where its footer is and whether
// its body scrolls. Shared by the suite (cctab-tests.swift) and the offscreen render (cctab-render/main.swift).
import AppKit
import SwiftUI

enum CCTabScene {
    static let band: CGFloat = 38
    static let width: CGFloat = 540
    static let minHeight: CGFloat = 190

    /// The card's frame in the notch, drawn as the tab draws it (the column and chips are stand-ins of their size).
    struct Frame<Card: View>: View {
        let maxHeight: CGFloat
        let card: Card

        var body: some View {
            GrowDownFrame(active: true, minHeight: CCTabScene.minHeight, maxHeight: maxHeight) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: CCTabScene.band)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("jdoe").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            Text("Context 49%").font(.system(size: 10.5)).foregroundStyle(.gray)
                            Label("Open terminal", systemImage: "arrow.up.forward.app").font(.system(size: 10.5)).foregroundStyle(.gray)
                        }
                        .frame(width: 150, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                chip("jdoe", .yellow, on: true)
                                chip("boring.notch", .gray, on: false)
                            }
                            .frame(height: 20)
                            card
                                .padding(14)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.06).opacity(0.8))
                                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(width: CCTabScene.width)
                    .frame(maxHeight: .infinity)
                }
            }
            // ArisNotchRoot's surface: the open radius and ArisGlass.inset at the sides, ArisGlass.bottomInset under it.
            .padding(.horizontal, 31 + 12)
            .padding(.bottom, 8)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 31, bottomTrailingRadius: 31, style: .continuous).fill(.black))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 31, bottomTrailingRadius: 31, style: .continuous))
        }

        private func chip(_ name: String, _ dot: Color, on: Bool) -> some View {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(name).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 3).foregroundStyle(.white)
            .background(Capsule().fill(Color.white.opacity(on ? 0.22 : 0.08)))
        }
    }

    /// What one layout of a card came to.
    struct Measure {
        /// The notch's height (the hosting view's, as GrowDownFrame sized it).
        var height: CGFloat = 0
        var footer: CGRect = .null
        var scrolls: Bool?
        var bodyHeight: CGFloat = 0
        var host: NSHostingView<AnyView>?
    }

    final class MeasureBox: @unchecked Sendable { var measure = Measure() }

    /// Lays `card` out in the tab at `maxHeight` and reads its probe.
    @MainActor
    static func measure(_ card: some View, maxHeight: CGFloat) -> Measure {
        let box = MeasureBox()
        let view = Frame(maxHeight: maxHeight, card: card)
            .environment(\.claudeCardFitProbe) { report in
                switch report {
                case .footer(let frame): box.measure.footer = frame
                case .body(let scrolls, let height): box.measure.scrolls = scrolls; box.measure.bodyHeight = height
                }
            }
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: host.frame.width, height: host.frame.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
        }
        box.measure.height = host.frame.height
        box.measure.host = host
        return box.measure
    }

    /// The question the user's screenshot cut ("…"), whole: 300 characters.
    static let longQuestion = String(("월 예산을 9~10월 실제 지출 기준으로 제안할게요 (CAD). 음식 $300(실제 $350, $287), 장보기 $80, 쇼핑 $150($104, $228), "
        + "교통 $100($89, $100), 통신비 $45, 구독 $38, 여가 $120, 선물 $60, 기타 $50으로 잡으면 한 달 $943이고, 지난 두 달 평균보다 $112 적어요. "
        + "도박 예산은 따로 두고, 현금은 봉투로 나눠요. 트래블로그 카드는 해외 결제만 쓰는 걸로 하고, 남는 돈은 다음 달로 넘겨요. 매달 1일에 지난달 결과를 같이 보고, 필요하면 금액을 다시 조정해요. 이대로 갈까요?").prefix(300))

    /// Four options with two-line descriptions, as the screenshot's first question.
    static let options: [ClaudeOption] = [
        ClaudeOption(label: "제안대로 $760 (Recommended)", detail: "지금 쓰는 만큼을 기준으로 잡아서, 넘치는 달이 바로 보이게 해요. 두 달 평균에서 크게 벗어나지 않아요"),
        ClaudeOption(label: "빡세게 $600", detail: "음식과 쇼핑을 주로 줄여서 절약 목표로 잡아요 (음식 $230, 쇼핑 $100 등). 첫 달은 빠듯할 수 있어요"),
        ClaudeOption(label: "느슨하게 $900", detail: "여유를 두고 잡아서 넘치는 달이 거의 없게 해요. 대신 모이는 돈이 적고 줄일 곳이 잘 안 보여요"),
        ClaudeOption(label: "예산은 아직 만들지 마", detail: "한두 달 기록만 보고 나중에 정해요. 그동안은 지출만 카테고리별로 모아서 보여줘요"),
    ]

    /// A multi-select question whose plain options are too long to sit in one row of pills.
    static let pillsQuestion = ClaudeQuestion(header: "범위", question: "이번 정리에 어디까지 넣을까요? 여러 개 골라도 돼요.",
        options: ["카드 높이와 스크롤", "터미널로 바로 가기", "주황 점이 남는 이유", "세션 목록 정리", "설정 문구"].map { ClaudeOption(label: $0, detail: "") },
        multiSelect: true)

    /// The user's card: four questions (월 예산 / 도박 예산 / 현금 / 트래블로그), the first the long one.
    static let questions: [ClaudeQuestion] = [
        ClaudeQuestion(header: "월 예산", question: longQuestion, options: options, multiSelect: false),
        ClaudeQuestion(header: "도박 예산", question: "도박 예산은 한 달에 얼마로 둘까요?",
                       options: [ClaudeOption(label: "$0", detail: "아예 안 해요"), ClaudeOption(label: "$50", detail: "한 달에 한 번 정도")], multiSelect: false),
        ClaudeQuestion(header: "현금", question: "현금은 어떻게 나눌까요?",
                       options: [ClaudeOption(label: "봉투", detail: "카테고리별 봉투"), ClaudeOption(label: "한 곳에", detail: "지갑 하나")], multiSelect: false),
        ClaudeQuestion(header: "트래블로그", question: "트래블로그 카드는 어디에 쓸까요?",
                       options: [ClaudeOption(label: "해외 결제만", detail: ""), ClaudeOption(label: "전부", detail: ""), ClaudeOption(label: "안 써요", detail: "")],
                       multiSelect: true),
    ]
}
