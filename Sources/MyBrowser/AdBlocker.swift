import WebKit

extension Notification.Name {
    static let adBlockerUpdate = Notification.Name("MyBrowserAdBlockerUpdate")
}

/// Blocks ads on websites using WebKit's built-in content blocking: requests to well-known ad
/// networks are stopped before they load, and common empty ad boxes are hidden. Nothing is sent
/// anywhere; the rules are compiled on this Mac. Best effort, not every ad is caught.
enum AdBlocker {
    static let defaultsKey = "blockAds"
    private static let identifier = "MyBrowserAds1"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private(set) static var list: WKContentRuleList?

    /// Third-party ad networks and ad exchanges (ads only, not analytics).
    private static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "2mdn.net", "adnxs.com", "adsrvr.org", "advertising.com", "taboola.com", "outbrain.com",
        "criteo.com", "criteo.net", "pubmatic.com", "rubiconproject.com", "openx.net",
        "casalemedia.com", "indexww.com", "amazon-adsystem.com", "moatads.com",
        "adsafeprotected.com", "doubleverify.com", "media.net", "smartadserver.com", "adform.net",
        "33across.com", "sharethrough.com", "teads.tv", "yieldmo.com", "triplelift.com",
        "bidswitch.net", "contextweb.com", "lijit.com", "sovrn.com", "gumgum.com",
        "spotxchange.com", "springserve.com", "tremorhub.com", "adition.com", "revcontent.com",
        "mgid.com", "zemanta.com", "popads.net", "propellerads.com", "exoclick.com",
        "juicyads.com", "trafficjunky.net", "adcash.com", "clickadu.com", "hilltopads.net",
        "onclickads.net", "adsterra.com", "serving-sys.com", "flashtalking.com", "innovid.com",
        "adroll.com", "ad.gt", "adtelligent.com", "lkqd.net", "undertone.com",
        "conversantmedia.com", "btloader.com", "adthrive.com", "mediavine.com", "adsco.re",
        "ads.pubmatic.com", "pagead2.googlesyndication.com", "tpc.googlesyndication.com",
        "ads-twitter.com", "ads.linkedin.com", "adsymptotic.com", "admixer.net", "adkernel.com",
        "richaudience.com", "smaato.net", "inmobi.com", "unityads.unity3d.com", "applovin.com",
        "mopub.com", "chartboost.com", "vungle.com", "ironsrc.com", "bidr.io", "bidtheatre.com",
        "ad-delivery.net", "adscale.de", "yieldlab.net", "cpmstar.com", "ad4m.at", "adspirit.de",
    ]

    /// Empty ad boxes left behind on pages.
    private static let hiddenSelectors = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^=\"google_ads_\"]", "[id^=\"div-gpt-ad\"]",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication.com\"]",
        "[data-ad-slot]", "[data-google-query-id]", "[aria-label=\"Advertisement\"]",
        ".advertisement", ".ad-banner", ".ad-container", ".ad-slot", ".ad-wrapper",
        ".google-ad", ".sponsored-ad", "#ad-container", "#ad-banner",
        ".taboola", "#taboola-below-article", ".OUTBRAIN", ".ob-widget",
    ]

    private static func rulesJSON() -> String {
        var rules: [[String: Any]] = domains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": ["url-filter": "^https?://([^/:]+\\.)?\(escaped)[:/]",
                            "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")],
        ])
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Compiles the rules (fast, cached by WebKit) and tells open tabs to start using them.
    static func compile() {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier, encodedContentRuleList: rulesJSON()
        ) { list, _ in
            DispatchQueue.main.async {
                Self.list = list
                NotificationCenter.default.post(name: .adBlockerUpdate, object: nil)
            }
        }
    }

    /// Adds or removes the rules for a tab, depending on the setting.
    static func apply(to controller: WKUserContentController) {
        guard let list else { return }
        controller.remove(list)
        if enabled { controller.add(list) }
    }
}
