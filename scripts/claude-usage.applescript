-- Ask the logged-in Google Chrome to fetch your Claude usage from inside an
-- open claude.ai tab. Because the request runs in the real page context, it's
-- already authenticated and past Cloudflare — no session key, no 403.
--
-- Requires: Chrome menu  View > Developer > "Allow JavaScript from Apple Events"
-- turned on, and a claude.ai tab open and logged in.
--
-- Prints the /usage endpoint's JSON to stdout (empty if no claude.ai tab found).

-- Synchronous same-origin XHRs: discover the org, then read its usage.
set jsCode to "(function(){function g(u){var x=new XMLHttpRequest();x.open('GET',u,false);x.send();return x.responseText;}var o=JSON.parse(g('/api/organizations'));var id=(Array.isArray(o)?o[0]:o).uuid;return g('/api/organizations/'+id+'/usage');})()"

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

return out
