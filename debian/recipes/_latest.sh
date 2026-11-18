# shared helper for Debian override recipes: latest GitHub release tag (without leading v)
_latest() { curl -fsSI "https://github.com/$1/releases/latest" | sed -n 's#^location: .*/tag/v\{0,1\}\([^[:space:]]*\).*#\1#Ip' | tr -d '\r'; }
