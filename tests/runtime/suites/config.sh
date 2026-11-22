. /tests/lib.sh
SUITE=config
if [ ! -r /proc/config.gz ]; then fail config-gz-present "/proc/config.gz does not exist"; exit 0; fi
pass config-gz-present "/proc/config.gz exists"
if load_config; then pass config-gz-readable "decompressed $(wc -l <"$CONFIG") lines"; else fail config-gz-readable "cannot decompress /proc/config.gz"; exit 0; fi
# the host compares this hash with the build's own .config (scripts/xlin-runtime-test)
echo "XLIN-CONFIG-SHA256: $(sha256sum "$CONFIG" | cut -d' ' -f1)"
rel=$(uname -r)
grep -q "^# Linux/x86 .* Kernel Configuration" "$CONFIG" && pass config-header "header present" || fail config-header "no kernel configuration header"
config_is LOCALVERSION '"-xlin"' && pass config-localversion "CONFIG_LOCALVERSION=\"-xlin\" (release $rel)" || info config-localversion "CONFIG_LOCALVERSION is not -xlin (release $rel)"
