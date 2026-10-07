# OpenTune build environment — source this:  source ~/workspace/opentune/ENV.sh
# Sets up Flutter + Android SDK toolchain installed under /home/hatch.
export JAVA_HOME="$HOME/jdk-17"
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export PATH="$HOME/flutter/bin:$HOME/android-sdk/cmdline-tools/latest/bin:$HOME/android-sdk/platform-tools:$JAVA_HOME/bin:$PATH"
# GNU tar honors TAR_OPTIONS: flutter's artifact extractor runs plain `tar -xzf`
# which tries to chown to the tarball's uid/gid and fails in this container.
export TAR_OPTIONS="--no-same-owner --no-same-permissions"
# The VM's egress proxy URL embeds credentials containing characters that break
# Java's proxy-URL parsing (sdkmanager/Gradle die in HttpURLConnection).
# The proxy does not require auth (verified 2026-10-07), so strip the userinfo
# and keep plain host:port for every tool in the shell.
_sanitize_proxy() {
  case "$1" in
    *://*@*) printf '%s' "$1" | sed -E 's|^([^:]+://)[^@]+@|\1|' ;;
    *) printf '%s' "$1" ;;
  esac
}
for _pv in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; do
  if [ -n "${!_pv:-}" ]; then export "$_pv"="$(_sanitize_proxy "${!_pv}")"; fi
done
unset _sanitize_proxy _pv
# Java ignores *proxy env vars entirely; sdkmanager/Gradle need the proxy via
# JVM flags. JAVA_TOOL_OPTIONS is picked up by every JVM launch automatically.
# (Verified: the egress proxy MITMs TLS, so its CA was imported into the
# JDK truststore: keytool -list -alias hatch-egress-ca.)
export JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=hatch-egress-proxy -Dhttps.proxyPort=3128 -Dhttp.proxyHost=hatch-egress-proxy -Dhttp.proxyPort=3128 -Dhttp.nonProxyHosts=localhost|127.0.0.1 -Djava.net.preferIPv4Stack=true"
# Gradle: Java's user.home is /root for the root user, but our files live under
# $HOME. Pin GRADLE_USER_HOME so the wrapper and builds use one consistent place.
export GRADLE_USER_HOME="$HOME/.gradle"
