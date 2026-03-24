"""
inject_ads.py — mitmproxy addon for China Mode
Injects a Baidu-style ad banner into HTTP HTML responses.
Runs inside CT 200 as a mitmproxy addon.

Usage:
    mitmdump -p 8080 -s /opt/china-mode/inject_ads.py --mode transparent
"""

from mitmproxy import http
import re

BAIDU_AD_SCRIPT = b"""
<!-- [China Mode] Injected Ad Block -->
<div id="china-mode-ad" style="
    position:fixed; bottom:0; left:0; right:0; z-index:99999;
    background:#c00; color:#fff; font-family:sans-serif;
    padding:8px 16px; font-size:13px; display:flex;
    align-items:center; justify-content:space-between;
    border-top:2px solid #ffde00; box-shadow:0 -2px 8px rgba(0,0,0,0.4);">
  <span>
    &#x767E;&#x5EA6;&#x4E00;&#x4E0B;&#xFF0C;&#x4F60;&#x5C31;&#x77E5;&#x9053;
    &nbsp;&mdash;&nbsp;
    <a href="https://www.baidu.com" style="color:#ffde00;text-decoration:none;font-weight:bold;">
      &#x767E;&#x5EA6;&#x641C;&#x7D22; baidu.com
    </a>
    &nbsp;|&nbsp;
    <a href="https://www.jd.com" style="color:#ffde00;text-decoration:none;">&#x4EAC;&#x4E1C;</a>
    &nbsp;|&nbsp;
    <a href="https://www.taobao.com" style="color:#ffde00;text-decoration:none;">&#x6DE1;&#x5B9D;</a>
    &nbsp;|&nbsp;
    <a href="https://www.weibo.com" style="color:#ffde00;text-decoration:none;">&#x5FAE;&#x535A;</a>
  </span>
  <span style="font-size:11px;opacity:0.7;">[China Mode Active &mdash; WHS CyberSTEMLab]</span>
</div>
<!-- [/China Mode] -->
"""

DISMISS_SCRIPT = b"""
<script>
(function(){
  var ad = document.getElementById('china-mode-ad');
  if(ad){ ad.onclick = function(){ ad.style.display='none'; }; }
})();
</script>
"""


class BaiduAdInjector:
    """Inject a Baidu-style banner ad into every HTML page response."""

    def response(self, flow: http.HTTPFlow) -> None:
        # Only process HTTP (not HTTPS — mitmproxy handles HTTPS separately)
        content_type = flow.response.headers.get("content-type", "")
        if "text/html" not in content_type:
            return

        # Skip very small responses (error pages, redirects)
        if len(flow.response.content) < 200:
            return

        content = flow.response.content

        # Inject banner before </body>
        if b"</body>" in content.lower():
            content = re.sub(
                rb"(?i)</body>",
                BAIDU_AD_SCRIPT + DISMISS_SCRIPT + b"</body>",
                content,
                count=1,
            )
            flow.response.content = content
            # Remove content-length so the client accepts the modified length
            if "content-length" in flow.response.headers:
                del flow.response.headers["content-length"]


addons = [BaiduAdInjector()]
