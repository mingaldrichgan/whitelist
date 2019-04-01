#!/bin/bash
set -e            # Exit on error.
export LC_ALL=C   # Force consistent glob order.
shopt -s nullglob # Prevent literal * in the FILES array.

readonly PIHOLE_DIR='/etc/pihole'
readonly PIHOLE_COMMAND='/usr/local/bin/pihole'

mapfile -t URL <"${PIHOLE_DIR}/adlists.list"
if ((${#URL[@]} != 1)); then
	echo "This script requires exactly 1 blocklist URL but found ${#URL[@]}."
	exit 1
fi
readonly URL

# Files to sync with the blocklist URL.
readonly FILES=("${PIHOLE_DIR}"/list.*.domains "${PIHOLE_DIR}/list.preEventHorizon")

readonly LOG='/var/log/pihole_wormhole.log'
touch "${LOG}"
readonly LOG_START=$(($(wc -l <"${LOG}") + 1))

function log() {
	echo -e "$(date -R)\\t${1}" >>"${LOG}"
}

function cleanup() {
	local status="$?"
	rm "${downloaded}" 2>/dev/null || true # Ignore errors.
	if ((status != 0)); then
		tail -n+"${LOG_START}" "${LOG}"
	fi
	exit "${status}"
}

readonly downloaded=$(mktemp)
trap 'cleanup' EXIT
curl -fsSL -o"${downloaded}" -z"${FILES[0]}" "${URL}"

if [[ ! -s "${downloaded}" ]]; then
	# HTTP response was 304 Not Modified.
	exit 0
fi

if cmp -s "${downloaded}" "${FILES[0]}"; then
	log 'Blocklist was updated but not modified. Updating file timestamps...'
	touch -r"${downloaded}" "${FILES[@]}"
	exit 0
fi

log "Updating files... [✓] ${FILES[0]}"
str='                  [✓] '
mv "${downloaded}" "${FILES[0]}"
for file in "${FILES[@]:1}"; do
	log "${str}${file}"
	cp "${FILES[0]}" "${file}"
done

log 'Updating Pi-hole gravity...'
"${PIHOLE_COMMAND}" updateGravity --skip-download --whitelist-only >>"${LOG}"
