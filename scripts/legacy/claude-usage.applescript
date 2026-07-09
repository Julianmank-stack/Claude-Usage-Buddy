-- Ask the logged-in Google Chrome to fetch your Claude usage from inside an
-- open claude.ai tab. Because the request runs in the real page context, it's
-- already authenticated and past Cloudflare — no session key, no 403.
--
-- The percent math runs in the page too, so no local Node/jq is needed: this
-- script returns the remaining fraction ("0.4600"), or "ERR:<reason>".
--
-- Usage: osascript claude-usage.applescript [session|weekly_all|min]
--   (which limit to track; default "min" = whichever is closest to its cap)
--
-- Requires: Chrome menu  View > Developer > "Allow JavaScript from Apple Events"
-- turned on, and a claude.ai tab open and logged in.

on run argv
	set whichLimit to "min"
	if (count of argv) > 0 then set whichLimit to item 1 of argv

	-- Synchronous same-origin XHRs: discover the org, read its usage, and
	-- reduce it to a remaining fraction — all inside the page.
	set jsCode to "(function(){" & ¬
		"function g(u){var x=new XMLHttpRequest();x.open('GET',u,false);x.send();if(x.status!==200)throw new Error('HTTP '+x.status);return x.responseText;}" & ¬
		"try{" & ¬
		"var o=JSON.parse(g('/api/organizations'));var id=(Array.isArray(o)?o[0]:o).uuid;" & ¬
		"var j=JSON.parse(g('/api/organizations/'+id+'/usage'));" & ¬
		"var which='" & whichLimit & "';" & ¬
		"var lim=Array.isArray(j.limits)?j.limits:[];var used=null;" & ¬
		"function num(v){return typeof v==='number'&&isFinite(v);}" & ¬
		"if(which!=='min'){for(var i=0;i<lim.length;i++){var l=lim[i];if((l.kind===which||l.group===which)&&num(l.percent)){used=l.percent;break;}}}" & ¬
		"if(used===null){var ps=lim.filter(function(l){return num(l.percent);}).map(function(l){return l.percent;});if(ps.length)used=Math.max.apply(null,ps);}" & ¬
		"if(used===null){var m=[j.five_hour,j.seven_day].filter(function(t){return t&&num(t.utilization);}).map(function(t){return t.utilization;});if(m.length)used=Math.max.apply(null,m);}" & ¬
		"if(used===null)return 'ERR:no-percent-in-response';" & ¬
		"var r=1-used/100;if(r<0)r=0;if(r>1)r=1;return r.toFixed(4);" & ¬
		"}catch(e){return 'ERR:'+e.message;}" & ¬
		"})()"

	set out to ""
	tell application "Google Chrome"
		repeat with w in windows
			repeat with t in tabs of w
				if (URL of t) starts with "https://claude.ai" then
					set out to (execute t javascript jsCode)
					exit repeat
				end if
			end repeat
			if out is not "" then exit repeat
		end repeat
	end tell

	if out is "" then return "ERR:no-claude.ai-tab-found"
	return out
end run
