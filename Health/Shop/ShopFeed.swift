import Foundation

struct ShopCategory: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct ShopProduct: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let categoryId: String
    let name: String
    let summary: String
    let price: String?
    var imageURL: URL?
    let coupangURL: URL
}

struct ShopFeed: Equatable, Sendable {
    let version: Int?
    let updatedAt: String?
    let categories: [ShopCategory]
    var products: [ShopProduct]
    /// 디코딩에서 제외된 상품 수(필수 필드 누락, 잘못된 coupangURL, 중복 id). 로깅용.
    let droppedCount: Int

    /// `nil`이면 전체. 카테고리에 없는 categoryId를 가진 상품은 전체에서만 보여요.
    func products(in categoryId: String?) -> [ShopProduct] {
        guard let categoryId else { return products }
        return products.filter { $0.categoryId == categoryId }
    }
}

/// 원격 피드 디코더. 순수 함수: 네트워크·DEBUG 분기 없음.
/// 모르는 필드는 무시하고, 깨진 원소만 버려요. `products` 키가 없거나 JSON이 깨지면 throw.
enum ShopFeedDecoder {
    static func decode(_ data: Data) throws -> ShopFeed {
        let raw = try JSONDecoder().decode(RawFeed.self, from: data)

        var categories: [ShopCategory] = []
        var categoryIds = Set<String>()
        for case let category? in (raw.categories ?? []).map(\.value)
        where !category.id.isEmpty && categoryIds.insert(category.id).inserted {
            categories.append(ShopCategory(id: category.id, name: category.name))
        }

        var products: [ShopProduct] = []
        var productIds = Set<String>()
        for element in raw.products {
            guard let item = element.value,
                  !item.id.isEmpty,
                  let coupangURL = httpsURL(item.coupangURL),
                  productIds.insert(item.id).inserted else { continue }
            products.append(ShopProduct(
                id: item.id,
                categoryId: item.categoryId,
                name: item.name,
                summary: item.summary,
                price: item.price,
                imageURL: item.imageURL.flatMap(httpsURL),
                coupangURL: coupangURL
            ))
        }

        return ShopFeed(
            version: raw.version,
            updatedAt: raw.updatedAt,
            categories: categories,
            products: products,
            droppedCount: raw.products.count - products.count
        )
    }

    /// scheme이 https이고 host가 비어 있지 않은 URL만 통과.
    static func httpsURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private struct RawFeed: Decodable {
        let version: Int?
        let updatedAt: String?
        let categories: [Lossy<RawCategory>]?
        let products: [Lossy<RawProduct>]

        enum CodingKeys: String, CodingKey { case version, updatedAt, categories, products }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
            categories = try? c.decodeIfPresent([Lossy<RawCategory>].self, forKey: .categories)
            products = try c.decode([Lossy<RawProduct>].self, forKey: .products)
        }
    }

    private struct RawCategory: Decodable {
        let id: String
        let name: String
    }

    private struct RawProduct: Decodable {
        let id: String
        let categoryId: String
        let name: String
        let summary: String
        let price: String?
        let imageURL: String?
        let coupangURL: String

        enum CodingKeys: String, CodingKey { case id, categoryId, name, summary, price, imageURL, coupangURL }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            categoryId = try c.decode(String.self, forKey: .categoryId)
            name = try c.decode(String.self, forKey: .name)
            summary = try c.decode(String.self, forKey: .summary)
            coupangURL = try c.decode(String.self, forKey: .coupangURL)
            // 선택 필드는 타입이 틀려도 상품을 버리지 않고 비워요.
            price = try? c.decodeIfPresent(String.self, forKey: .price)
            imageURL = try? c.decodeIfPresent(String.self, forKey: .imageURL)
        }
    }

    /// 원소 하나가 깨져도 배열 전체 디코딩은 계속돼요.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}
