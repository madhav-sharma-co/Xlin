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
# informational: the options that decide whether the kernel's CPU-vulnerability mitigations and
# W^X checks exist, as the running kernel itself reports them (used to compare Xlin with the Arch
# baseline when a boot-log line differs, e.g. the ITS mitigation and the early-boot W^X notice)
opts=$(grep -E '^(# )?CONFIG_(CPU_MITIGATIONS|MITIGATION_[A-Z0-9_]+|STRICT_KERNEL_RWX|STRICT_MODULE_RWX|DEBUG_WX|EXECMEM_ROX|ARCH_HAS_EXECMEM_ROX|FINEIBT|CFI_CLANG|X86_KERNEL_IBT)[= ]' "$CONFIG" | sed 's/^# CONFIG_\([A-Z0-9_]*\) is not set/\1=n/; s/^CONFIG_//' | tr '\n' ' ')
info config-mitigation-options "$opts"
