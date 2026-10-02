import SwiftUI

struct ShopView: View {
    @StateObject private var store = ShopService(environment: .current)
    @Environment(\.openURL) private var openURL
    @ObservedObject private var theme = ThemeStore.shared
    @State private var selectedCategory: String?
    @State private var lastOpened: URL?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("쇼핑")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .tracking(-0.4)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)

                ShopBanner()
                    .padding(.horizontal, 24)

                ShopChipRow(categories: categories, selected: $selectedCategory)

                content
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topLeading) {
            if store.environment.interceptsOpenURL {
                Text(lastOpened?.absoluteString ?? "")
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityLabel(lastOpened?.absoluteString ?? "")
                    .accessibilityIdentifier("shop-last-opened")
                    .accessibilityHidden(false)
            }
        }
        .background(Gym.bg.ignoresSafeArea())
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: store.state) { _, _ in
            if let id = selectedCategory, !categories.contains(where: { $0.id == id }) {
                selectedCategory = nil
            }
        }
    }

    private var categories: [ShopCategory] {
        if case .loaded(let feed) = store.state { return feed.categories }
        return []
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed:
            VStack(spacing: 16) {
                Text("상품을 불러올 수 없어요")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Gym.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                GymCTA(title: "다시 시도") {
                    Task { await store.refresh() }
                }
                .accessibilityIdentifier("shop-retry")
            }
            .padding(.top, 40)
        case .loaded(let feed):
            let products = feed.products(in: selectedCategory)
            if products.isEmpty {
                Text(selectedCategory == nil ? "아직 상품이 없어요" : "이 카테고리에 상품이 없어요")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Gym.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                    .accessibilityIdentifier("shop-empty")
            } else {
                ForEach(products) { product in
                    ShopProductCard(product: product) { open(product.coupangURL) }
                }
            }
        }
    }

    private func open(_ url: URL) {
        if store.environment.interceptsOpenURL {
            lastOpened = url
        } else {
            openURL(url)
        }
    }
}

private struct ShopBanner: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Text("이 앱은 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다. 가격은 변동될 수 있어요.")
            .font(.system(size: 12))
            .foregroundStyle(Gym.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("shop-banner")
    }
}

private struct ShopChipRow: View {
    @ObservedObject private var theme = ThemeStore.shared
    var categories: [ShopCategory]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "전체", id: nil, identifier: "shop-chip-all")
                ForEach(categories, id: \.id) { category in
                    chip(title: category.name, id: category.id, identifier: "shop-chip-\(category.id)")
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func chip(title: String, id: String?, identifier: String) -> some View {
        let on = selected == id
        return Button {
            selected = id
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Gym.bg : Gym.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Gym.text : Gym.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct ShopProductCard: View {
    @ObservedObject private var theme = ThemeStore.shared
    var product: ShopProduct
    var action: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            GymCard(padding: 14) {
                HStack(alignment: .top, spacing: 14) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Gym.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(product.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Gym.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let price = product.price {
                            Text(price)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Gym.text)
                        }
                        Text("쿠팡에서 보기")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Gym.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Gym.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("shop-card-\(product.id)")
        .task(id: product.imageURL) {
            image = nil
            guard let url = product.imageURL else { return }
            image = await ShopImageLoader.shared.image(for: url)
        }
    }

    private var thumbnail: some View {
        ZStack {
            Gym.elevated
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "bag")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Gym.faint)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var accessibilityText: String {
        [product.name, product.summary, product.price, "쿠팡에서 보기"]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
