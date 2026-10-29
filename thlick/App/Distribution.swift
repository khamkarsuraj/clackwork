/// The channel this build ships through. The App Store target compiles with `APP_STORE`.
nonisolated enum Distribution {
    #if APP_STORE
    /// True in the Mac App Store build, which gets updates from the App Store, not Sparkle.
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
