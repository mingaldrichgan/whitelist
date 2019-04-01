#!/bin/bash
# Project homepage: https://github.com/anudeepND/whitelist
# Licence: https://github.com/anudeepND/whitelist/blob/master/LICENSE
# Created by Anudeep (Personal fork by Ming)
#================================================================================
set -e          # Exit on error.
export LC_ALL=C # Force consistent sort order.

readonly PIHOLE_DIR='/etc/pihole'
readonly PIHOLE_COMMAND='/usr/local/bin/pihole'

readonly URLS=$(
	curl -fsS 'https://api.github.com/repos/anudeepND/whitelist/contents/domains' |
		jq -r '.[].download_url'
)
readonly FILE="${PIHOLE_DIR}/whitelist.txt"
readonly LOG='/var/log/pihole_whitelist.log'

# Remove comments and empty lines.
function compact() {
	grep -vE '^(#|$)' "$@"
}

readonly downloaded=$(mktemp)
trap 'rm "${downloaded}"' EXIT

for url in ${URLS}; do
	echo "# ${url}"
	curl -fsSL "${url}" | compact
done | sort -u >>"${downloaded}"

if [[ -e "${FILE}" ]]; then
	# Append custom entries, i.e. those in ${FILE} that are not in ${downloaded}.
	readonly custom=$(comm -23 <(compact "${FILE}" | sort -u) "${downloaded}")
	if [[ "${custom}" ]]; then
		echo -e "\\n# Custom whitelist:\\n${custom}" >>"${downloaded}"
	fi

	# Backup ${FILE} if the whitelist has changed.
	if ! cmp -s <(tail -n+2 "${FILE}" | head -n-1) "${downloaded}"; then
		mv "${FILE}" "${FILE}.old"
	fi
fi
echo -e "# Whitelist sources (updated $(date -R)):\\n$(<"${downloaded}")\\n" >"${FILE}"

# Squash output to log, then splat the log to stdout on error to allow for
# standard crontab job error handling (credit: pihole.cron).
"${PIHOLE_COMMAND}" updateGravity --skip-download --whitelist-only >"${LOG}" || cat "${LOG}"
