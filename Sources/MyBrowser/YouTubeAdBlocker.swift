import WebKit

/// Experimental, best-effort YouTube ad blocking. Runs a small script inside YouTube pages that
/// (1) removes ad data from YouTube's player responses, (2) hides ad boxes, and (3) mutes, speeds up
/// and skips any ad that still starts. YouTube changes its pages often and fights blockers, so this
/// can stop working at any time.
enum YouTubeAdBlocker {
    static let defaultsKey = "blockYouTubeAds"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func install(in controller: WKUserContentController) {
        guard isEnabled else { return }
        controller.addUserScript(WKUserScript(source: source,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
    }

    static let source = #"""
    (function () {
      if (!/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) return;
      if (window.__mbYTAdBlock) return;
      window.__mbYTAdBlock = true;

      // 1. Remove ad fields from YouTube's data before the player sees them.
      var AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];
      function clean(o) {
        if (o && typeof o === 'object') {
          for (var i = 0; i < AD_KEYS.length; i++) {
            if (AD_KEYS[i] in o) { try { delete o[AD_KEYS[i]]; } catch (e) {} }
          }
          if (o.playerResponse && typeof o.playerResponse === 'object') clean(o.playerResponse);
        }
        return o;
      }

      var origParse = JSON.parse;
      JSON.parse = function () {
        var result = origParse.apply(this, arguments);
        try { clean(result); } catch (e) {}
        return result;
      };

      try {
        var initial;
        Object.defineProperty(window, 'ytInitialPlayerResponse', {
          configurable: true,
          get: function () { return initial; },
          set: function (v) { initial = clean(v); }
        });
      } catch (e) {}

      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function () {
          var args = arguments;
          var promise = origFetch.apply(this, args);
          try {
            var first = args[0];
            var url = (typeof first === 'string' ? first : (first && first.url)) || '';
            if (/\/youtubei\/v1\/(player|reel\/reel_item_watch)/.test(url)) {
              return promise.then(function (res) {
                return res.clone().json().then(function (json) {
                  clean(json);
                  return new Response(JSON.stringify(json), {
                    status: res.status, statusText: res.statusText, headers: res.headers
                  });
                }).catch(function () { return res; });
              });
            }
          } catch (e) {}
          return promise;
        };
      }

      // 2. Hide ad boxes and banners.
      var css = [
        '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container', '#player-ads', '#masthead-ad',
        'ytd-ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer', 'ytd-promoted-sparkles-web-renderer',
        'ytd-display-ad-renderer', 'ytd-banner-promo-renderer', 'ytd-statement-banner-renderer',
        'ytd-companion-slot-renderer', 'ytd-action-companion-ad-renderer',
        '#related ytd-promoted-video-renderer', 'ytd-ads-engagement-panel-content-renderer',
        'ytm-promoted-sparkles-web-renderer'
      ].join(',') + '{display:none !important;}';
      var style = document.createElement('style');
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);

      // 3. If an ad still starts: mute it, speed it up, jump to its end, press Skip.
      var saved = null;
      function tick() {
        var player = document.querySelector('.html5-video-player');
        var video = document.querySelector('video.html5-main-video') || document.querySelector('video');
        var adShowing = !!(player && player.classList.contains('ad-showing'));

        if (video) {
          if (adShowing) {
            if (!saved) saved = { muted: video.muted, rate: video.playbackRate };
            video.muted = true;
            video.playbackRate = 16;
            if (isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.2) {
              try { video.currentTime = video.duration; } catch (e) {}
            }
          } else if (saved) {
            video.muted = saved.muted;
            video.playbackRate = saved.rate;
            saved = null;
          }
        }

        var skips = document.querySelectorAll(
          '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button');
        for (var i = 0; i < skips.length; i++) { try { skips[i].click(); } catch (e) {} }
        var close = document.querySelector('.ytp-ad-overlay-close-button');
        if (close) { try { close.click(); } catch (e) {} }

        // Remove an "ad blockers are not allowed" popup and resume the video.
        var warning = document.querySelector('ytd-enforcement-message-view-model');
        if (warning) {
          warning.remove();
          var backdrops = document.querySelectorAll('tp-yt-iron-overlay-backdrop');
          for (var j = 0; j < backdrops.length; j++) backdrops[j].remove();
          if (document.body) document.body.style.overflow = 'auto';
          if (video && video.paused) { try { video.play(); } catch (e) {} }
        }
      }
      setInterval(tick, 250);
    })();
    """#
}
