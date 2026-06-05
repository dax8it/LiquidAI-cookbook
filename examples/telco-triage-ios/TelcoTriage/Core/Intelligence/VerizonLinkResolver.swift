import Foundation

/// Resolves Verizon RAG page identifiers to in-app deep links.
///
/// The Verizon Home app exposes a `vzhome://` URI scheme; each RAG page
/// (numbered XX.NN) maps to at most one deep link. Pages can share a
/// deep link when they live under the same Level-1 destination — e.g.,
/// the Wi-Fi password and Wi-Fi name pages both deep-link to
/// `vzhome://network?launchPoint=verizonAssistant` because the
/// in-app navigation continues from Network → Wi-Fi Management.
///
/// The full 61-page table will be populated from the canonical RAG
/// corpus by a generated artifact (see `scripts/vz/build_link_table.py`,
/// landing in a follow-up PR). This file ships the deep-link skeleton
/// needed by the deterministic router for v0 routing tests and the
/// most-trafficked pages observed in the 50-conversation probe set
/// (Network ~40%, Equipment ~33% — ADR-021 §1.2).
public enum VerizonLinkResolver {
    /// Looks up the canonical deep link for a RAG page identifier.
    ///
    /// - Parameter pageID: a string of the form `"NN.NN"` matching the
    ///   RAG corpus, e.g. `"03.04"` for "Change Wi-Fi Password".
    /// - Returns: the `vzhome://...` URI string, or `nil` if the page
    ///   has no deep link registered. A `nil` result is a routing-side
    ///   error to be logged but recoverable: callers should fall back
    ///   to the Level-1 deep link for the page's category, or to
    ///   `unknownFeature` lane handling.
    public static func deepLink(forPageID pageID: String) -> String? {
        pageToDeepLink[pageID]
    }

    /// Returns the Level-1 fallback deep link for a macro intent.
    ///
    /// Used when:
    /// 1. ColBERT retrieval is below confidence and we want to send the
    ///    user to the right tab without claiming a specific page;
    /// 2. The `navOnlyDeeplink` lane needs an Account / Billing target.
    public static func levelOneFallback(for intent: VerizonMacroIntent) -> String {
        switch intent {
        case .network: return "vzhome://network?launchPoint=verizonAssistant"
        case .equipment: return "vzhome://equipment"
        case .devices: return "vzhome://tab-devices?launchPoint=verizonAssistant"
        case .homePage: return "vzhome://tab-home"
        case .parental: return "vzhome://home?launchPoint=verizonAssistant"
        case .digitalSecureHome: return "vzhome://home?launchPoint=verizonAssistant"
        case .discover: return "vzhome://tab-discover"
        case .accountOOS: return "vzhome://tab-more?launchPoint=verizonAssistant"
        case .billingOOS: return "vzhome://tab-more?launchPoint=verizonAssistant"
        case .liveAgent: return "vzhome://tab-more?launchPoint=verizonAssistant"
        }
    }

    /// True when the resolver knows a deep link for the given page.
    public static func contains(_ pageID: String) -> Bool {
        pageToDeepLink[pageID] != nil
    }

    /// Diagnostics: number of pages currently registered. Used by tests
    /// to detect accidental table shrinkage during code refactors.
    public static var registeredPageCount: Int {
        pageToDeepLink.count
    }

    /// All valid `vzhome://` URI prefixes the iOS app knows how to open.
    /// Stage B generations whose extracted URL doesn't start with one
    /// of these are considered invalid and trigger the KeywordKBExtractor
    /// fallback. Kept narrow on purpose — Stage B occasionally invents
    /// plausible-looking URLs (vzhome://wifi-password) that aren't real
    /// app routes; we'd rather drop those than ship a dead link.
    public static var knownDeepLinkPrefixes: Set<String> {
        Set(pageToDeepLink.values.map(canonicalPrefix))
            .union(Set(VerizonMacroIntent.allCases.map { canonicalPrefix(levelOneFallback(for: $0)) }))
    }

    /// Strip query string + trailing slash for prefix comparison.
    private static func canonicalPrefix(_ url: String) -> String {
        if let q = url.firstIndex(of: "?") {
            return String(url[url.startIndex..<q])
        }
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    /// Pulls the first `vzhome://...` URL out of a Markdown-link response
    /// (the Stage B output contract is one `[Name](vzhome://path)` per
    /// answer). Returns nil if no URL is found.
    public static func extractFirstDeepLink(in text: String) -> String? {
        // Regex: vzhome:// followed by anything that isn't a closing
        // paren, whitespace, or angle bracket. Matches the canonical
        // Markdown-link inner URL without dragging in trailing chars.
        guard let regex = try? NSRegularExpression(
            pattern: #"vzhome://[^\s)<>"']+"#,
            options: []
        ) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range)
        else { return nil }
        return nsText.substring(with: match.range)
    }

    /// True when the extracted URL starts with one of the prefixes the
    /// app knows how to open. Used by `StageBGenerator` to decide
    /// whether to ship the answer or fall back to KeywordKBExtractor.
    public static func isKnownDeepLink(_ url: String) -> Bool {
        let prefix = canonicalPrefix(url)
        for known in knownDeepLinkPrefixes {
            if prefix == known || prefix.hasPrefix(known) {
                return true
            }
        }
        return false
    }

    // MARK: - Page table
    //
    // ADR-021 §11.4.6: auto-generated from rag_pages.json at corpus
    // build time. Loaded from Resources/page-link-table-v1.json at
    // first use, cached as a static let via a closure.
    //
    // Falls back to a hand-curated subset (the Level-1 destinations
    // + most-trafficked pages from the original probe set) if the
    // generated artifact is missing — keeps the resolver functional
    // on fresh clones without bootstrap-models.sh.

    private static let pageToDeepLink: [String: String] = loadPageTable()

    /// Loads page → vzhome:// table from the bundled
    /// `page-link-table-v1.json` (generated by
    /// `scripts/vz/build_rag_index.py`). On any failure to load, falls
    /// back to the hand-curated subset below.
    private static func loadPageTable() -> [String: String] {
        if let url = Bundle.main.url(
            forResource: "page-link-table-v1",
            withExtension: "json"
        ),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pages = root["pages"] as? [String: String]
        {
            // Strip nulls / empties just in case the generator emits
            // any (it shouldn't — null deep links are omitted by the
            // Python side).
            let filtered = pages.filter { !$0.value.isEmpty }
            return filtered.isEmpty ? fallbackPageToDeepLink : filtered
        }
        return fallbackPageToDeepLink
    }

    /// Hand-curated fallback. Subset of the full corpus, used only
    /// when `page-link-table-v1.json` is missing or unparseable. The
    /// generated table covers all 47 corpus pages; this fallback
    /// covers ~14 of the most-trafficked.
    private static let fallbackPageToDeepLink: [String: String] = [
        // Level 1 — top-of-app destinations
        "01.00": "vzhome://tab-home",
        "01.01": "vzhome://tab-troubleshoot?launchPoint=verizonAssistant",
        "01.02": "vzhome://speed-test?launchPoint=verizonAssistant",
        "02.00": "vzhome://equipment",
        "03.00": "vzhome://network?launchPoint=verizonAssistant",
        "04.00": "vzhome://tab-devices?launchPoint=verizonAssistant",
        "05.00": "vzhome://tab-discover",
        "06.00": "vzhome://tab-more?launchPoint=verizonAssistant",
        "03.04": "vzhome://network?launchPoint=verizonAssistant",
        "03.05": "vzhome://network?launchPoint=verizonAssistant",
        "03.06": "vzhome://share-wifi",
        "03.08": "vzhome://tab-devices?launchPoint=verizonAssistant",
        "02.07": "vzhome://restart-router",
        "02.09": "vzhome://equipment-wps",
        "04.02": "vzhome://device-network-map",
        "01.04": "vzhome://report-bug",
    ]
}
